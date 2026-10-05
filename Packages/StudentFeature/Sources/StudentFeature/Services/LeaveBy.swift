import Foundation
import MapKit
import os
import CoreKit
import StudentFeatureWidgetKit

/// S-07 "Leave by" alerts. Pure planning; the ETA comes from `TravelTimeEstimating`.
///
/// The ETA is computed **once, when reminders are scheduled** (on sync), from where the iPhone is
/// at that moment. It isn't live: there's no continuous or background location.
public enum LeaveByPlanner {
    public static let identifierPrefix = "student.leave."
    /// Only classes starting within this window get an ETA (keeps MapKit requests few and the
    /// "current location" meaningful).
    public static let lookahead: TimeInterval = 18 * 3600
    /// At most this many distinct places are looked up per sync (MapKit throttles heavy use).
    public static let maxLookups = 4
    /// A trip this long is almost certainly a wrong geocode; skip it.
    public static let maxTravel: TimeInterval = 3 * 3600

    /// Classes that need an ETA: upcoming within `lookahead`, with a location, soonest first.
    public static func candidates(_ classes: [ClassSlot], now: Date, lookahead: TimeInterval = lookahead) -> [ClassSlot] {
        classes.filter { $0.start > now && $0.start <= now.addingTimeInterval(lookahead) && $0.location?.nilIfBlank != nil }
            .sorted { $0.start < $1.start }
    }

    /// Distinct locations to look up, soonest first, capped at `maxLookups`.
    /// Widgets show the next class even days ahead (e.g. Monday's class on a Saturday), so the Auto
    /// widget time looks further ahead than alerts do.
    public static let widgetLookahead: TimeInterval = 7 * 24 * 3600

    public static func locationsToLookUp(_ classes: [ClassSlot], now: Date, lookahead: TimeInterval = lookahead) -> [String] {
        var seen: [String] = []
        for slot in candidates(classes, now: now, lookahead: lookahead) {
            guard let location = slot.location?.nilIfBlank, !seen.contains(location) else { continue }
            seen.append(location)
            if seen.count == maxLookups { break }
        }
        return seen
    }

    /// - Parameters:
    ///   - etas: travel time per location string (missing = unknown).
    ///   - remindedClassIDs: classes that already get a normal class reminder.
    /// - Returns: a "Leave by" reminder for each class with a known ETA. When the ETA is unknown
    ///   (no address match, no permission, MapKit failed), a plain 15-minute reminder instead,
    ///   unless the class already has a normal reminder.
    public static func plan(classes: [ClassSlot], etas: [String: TimeInterval], bufferMinutes: Int, mode: TravelMode,
                            remindedClassIDs: Set<String>, now: Date) -> [PlannedReminder] {
        candidates(classes, now: now).compactMap { slot in
            guard let location = slot.location?.nilIfBlank else { return nil }
            if let eta = etas[location], eta > 0, eta <= maxTravel {
                let leave = slot.start.addingTimeInterval(-eta - TimeInterval(max(0, bufferMinutes) * 60))
                // Round down to the minute so "Leave by 8:41" is never later than the true time.
                let fire = Date(timeIntervalSince1970: (leave.timeIntervalSince1970 / 60).rounded(.down) * 60)
                guard fire > now else { return nil }
                let minutes = Int((eta / 60).rounded(.up))
                return PlannedReminder(
                    identifier: "\(identifierPrefix)\(slot.id).\(Int(fire.timeIntervalSince1970))",
                    fireDate: fire,
                    title: String(localized: "Leave by \(ScheduleFormat.time(fire)) for \(slot.code)"),
                    body: String(localized: "About \(minutes) min \(mode.phrase) to \(location). Class starts \(ScheduleFormat.time(slot.start))."),
                    courseID: slot.courseID)
            }
            guard !remindedClassIDs.contains(slot.id) else { return nil }
            let fire = slot.start.addingTimeInterval(-15 * 60)
            guard fire > now else { return nil }
            return PlannedReminder(identifier: "\(identifierPrefix)\(slot.id).fallback", fireDate: fire,
                                   title: String(localized: "\(slot.code) in 15 min"),
                                   body: String(localized: "\(location) · couldn't estimate travel time"),
                                   courseID: slot.courseID)
        }
    }
}

extension LeaveByPlanner {
    /// Widget "Leave by" for courses set to Auto: class start − ETA − extra minutes, rounded down
    /// to the minute. Classes without a known ETA keep whatever `leaveBy` they already had (the
    /// course's fixed minutes, or none).
    public static func applyAuto(to classes: [ClassSlot], autoCourseIDs: Set<UUID>, etas: [String: TimeInterval],
                                 bufferMinutes: Int) -> [ClassSlot] {
        classes.map { slot in
            guard let courseID = slot.courseID, autoCourseIDs.contains(courseID),
                  let location = slot.location?.nilIfBlank, let eta = etas[location], eta > 0, eta <= maxTravel else { return slot }
            var slot = slot
            let leave = slot.start.addingTimeInterval(-eta - TimeInterval(max(0, bufferMinutes) * 60))
            slot.leaveBy = Date(timeIntervalSince1970: (leave.timeIntervalSince1970 / 60).rounded(.down) * 60)
            slot.leaveByIsEstimate = true
            return slot
        }
    }
}

extension TravelMode {
    /// "on foot" / "by car" / "by transit".
    var phrase: String {
        switch self {
        case .walking: String(localized: "on foot")
        case .driving: String(localized: "by car")
        case .transit: String(localized: "by transit")
        }
    }
}

/// Lets exactly one of several racing tasks resume a continuation.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// One travel-time estimate from the current location to a place (mockable).
public protocol TravelTimeEstimating: Sendable {
    /// Seconds, or `nil` when the place can't be found or there's no route / location.
    func travelTime(to location: String, mode: TravelMode) async -> TimeInterval?
}

/// MapKit implementation (free, no API key): `MKLocalSearch` resolves the event's location text,
/// then one `MKDirections.calculateETA` from `MKMapItem.forCurrentLocation()`. Needs When In Use
/// location permission; the app only uses it while it's running (no background location).
public struct MapKitTravelTimeEstimator: TravelTimeEstimating {
    private static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Student")

    public init() {}

    /// MapKit can wait indefinitely for a location fix (indoors, no GPS, the Simulator with no
    /// location set). A refresh must never hang on it, so each lookup gives up after this long.
    public static let timeout: Duration = .seconds(8)

    public func travelTime(to location: String, mode: TravelMode) async -> TimeInterval? {
        // Not a task group: a group waits for every child, and a MapKit call that ignores
        // cancellation would still block. The first of (answer, timeout) resumes; the other is ignored.
        let once = ResumeOnce()
        return await withCheckedContinuation { (continuation: CheckedContinuation<TimeInterval?, Never>) in
            let lookup = Task {
                let eta = await lookUp(location, mode: mode)
                if once.claim() { continuation.resume(returning: eta) }
            }
            Task {
                try? await Task.sleep(for: Self.timeout)
                if once.claim() {
                    Self.logger.info("Leave-by ETA timed out")
                    lookup.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func lookUp(_ location: String, mode: TravelMode) async -> TimeInterval? {
        do {
            let search = MKLocalSearch.Request()
            search.naturalLanguageQuery = location
            search.resultTypes = [.address, .pointOfInterest]
            guard let destination = try await MKLocalSearch(request: search).start().mapItems.first else { return nil }
            let request = MKDirections.Request()
            request.source = MKMapItem.forCurrentLocation()
            request.destination = destination
            request.transportType = switch mode {
            case .walking: .walking
            case .driving: .automobile
            case .transit: .transit
            }
            return try await MKDirections(request: request).calculateETA().expectedTravelTime
        } catch {
            // Room numbers like "Room 3B" won't resolve; that's expected, not an error to show.
            Self.logger.info("Leave-by ETA unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
