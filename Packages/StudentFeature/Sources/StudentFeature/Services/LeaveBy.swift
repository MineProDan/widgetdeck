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
            // Alerts show on the Lock Screen: name the room or building, never the full street address.
            let place = slot.shortLocation ?? location
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
                    body: String(localized: "About \(minutes) min \(mode.phrase) to \(place). Class starts \(ScheduleFormat.time(slot.start))."),
                    courseID: slot.courseID)
            }
            guard !remindedClassIDs.contains(slot.id) else { return nil }
            let fire = slot.start.addingTimeInterval(-15 * 60)
            guard fire > now else { return nil }
            return PlannedReminder(identifier: "\(identifierPrefix)\(slot.id).fallback", fireDate: fire,
                                   title: String(localized: "\(slot.code) in 15 min"),
                                   body: String(localized: "\(place) · couldn't estimate travel time"),
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
    public static let timeout: Duration = .seconds(12)

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
                    SyncTrace.log("eta timed out after \(Self.timeout)")
                    lookup.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func lookUp(_ location: String, mode: TravelMode) async -> TimeInterval? {
        var stage = "place search"
        do {
            let destination: MKMapItem
            if let cached = PlaceCache.shared.coordinate(for: location) {
                destination = MKMapItem(placemark: MKPlacemark(coordinate: cached))
            } else {
                let search = MKLocalSearch.Request()
                search.naturalLanguageQuery = location
                search.resultTypes = [.address, .pointOfInterest]
                guard let found = try await MKLocalSearch(request: search).start().mapItems.first else {
                    SyncTrace.log("eta: place not found")
                    return nil
                }
                PlaceCache.shared.store(found.placemark.coordinate, for: location)
                destination = found
            }
            stage = "location fix"
            guard let here = await CurrentLocation.shared.fix() else {
                SyncTrace.log("eta: no location fix")
                return nil
            }
            stage = "directions"
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: here.coordinate))
            request.destination = destination
            request.transportType = switch mode {
            case .walking: .walking
            case .driving: .automobile
            case .transit: .transit
            }
            return try await MKDirections(request: request).calculateETA().expectedTravelTime
        } catch {
            // Room numbers like "Room 3B" won't resolve; that's expected, not an error to show.
            SyncTrace.log("eta: \(stage) failed (\((error as NSError).domain) \((error as NSError).code))")
            Self.logger.info("Leave-by ETA unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// Resolved class locations for this app session, so each place is searched once, not on every sync.
final class PlaceCache: Sendable {
    static let shared = PlaceCache()
    private let items = OSAllocatedUnfairLock(initialState: [String: CLLocationCoordinate2D]())
    func coordinate(for location: String) -> CLLocationCoordinate2D? { items.withLock { $0[location] } }
    func store(_ coordinate: CLLocationCoordinate2D, for location: String) { items.withLock { $0[location] = coordinate } }
}

/// One location fix shared by every travel-time lookup. Uses Core Location's last known fix when it's
/// recent, otherwise asks for one (city-block accuracy, which arrives fastest) and gives up after
/// 6 s. `MKMapItem.forCurrentLocation()` instead waits for a fix with no limit, indoors forever.
@MainActor
final class CurrentLocation: NSObject, CLLocationManagerDelegate {
    static let shared = CurrentLocation()
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []
    private var timeoutTask: Task<Void, Never>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fix(maxAge: TimeInterval = 10 * 60) async -> CLLocation? {
        if let last = manager.location, -last.timestamp.timeIntervalSinceNow < maxAge { return last }
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            guard waiting.count == 1 else { return } // a request is already out
            let started = Date.now
            manager.requestLocation()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                SyncTrace.log("location fix timed out after \(Int(Date.now.timeIntervalSince(started)))s")
                self?.finish(self?.manager.location)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuations = waiting
        waiting.removeAll()
        continuations.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in self.finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let code = (error as NSError).code
        Task { @MainActor in
            SyncTrace.log("location fix failed (code \(code))")
            self.finish(nil)
        }
    }
}
