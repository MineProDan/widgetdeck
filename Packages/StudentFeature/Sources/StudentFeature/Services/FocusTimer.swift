import ActivityKit
import CoreKit
import Foundation
import Observation
import os
import StudentFeatureWidgetKit
import UserNotifications

/// A focus session in progress, persisted in the App Group so it survives the app being closed.
public struct FocusSessionState: Codable, Sendable, Equatable {
    public var plan: FocusPlan
    public var title: String
    public var courseID: UUID?
    public var paint: CoursePaint
    /// Set while paused.
    public var pausedAt: Date?

    public init(plan: FocusPlan, title: String, courseID: UUID?, paint: CoursePaint, pausedAt: Date? = nil) {
        self.plan = plan
        self.title = title
        self.courseID = courseID
        self.paint = paint
        self.pausedAt = pausedAt
    }

    /// The block shown at `date` (while paused: the block that was running when paused).
    public func block(at date: Date) -> FocusBlock? {
        plan.block(at: pausedAt ?? date)
    }

    public func isFinished(at date: Date) -> Bool { pausedAt == nil && plan.isFinished(at: date) }

    /// Live Activity state at `date`.
    public func activityState(at date: Date) -> FocusActivityAttributes.ContentState? {
        guard let block = block(at: date) else { return nil }
        let remaining = pausedAt.map { block.end.timeIntervalSince($0) }
        return .init(kind: block.kind, round: block.round, blockStart: block.start, blockEnd: block.end, pausedRemaining: remaining)
    }
}

/// End-of-block notifications for a focus session. Own prefix: the Student sync never touches them.
public enum FocusNotifications {
    public static let identifierPrefix = "studentfocus."

    /// One notification at the end of every block still ahead ("Break time", "Back to focus", "Session done").
    public static func plan(_ state: FocusSessionState, now: Date) -> [PlannedReminder] {
        guard state.pausedAt == nil else { return [] }
        let blocks = state.plan.blocks
        return blocks.enumerated().compactMap { index, block in
            guard block.end > now else { return nil }
            let next = index + 1 < blocks.count ? blocks[index + 1] : nil
            let title: String
            let body: String
            switch (block.kind, next?.kind) {
            case (_, nil):
                title = String(localized: "Focus session done")
                body = String(localized: "\(state.plan.preset.rounds) × \(state.plan.preset.focusMinutes) min on \(state.title). Nice work.")
            case (.focus, .rest?):
                title = String(localized: "Break time")
                body = String(localized: "Session \(block.round) of \(state.plan.preset.rounds) done. \(state.plan.preset.breakMinutes) min break.")
            default:
                title = String(localized: "Back to focus")
                body = String(localized: "Session \(next?.round ?? block.round + 1) of \(state.plan.preset.rounds): \(state.title).")
            }
            return PlannedReminder(identifier: "\(identifierPrefix)\(index).\(Int(block.end.timeIntervalSince1970))",
                                   fireDate: block.end, title: title, body: body, courseID: state.courseID)
        }
    }
}

/// Runs the focus timer (S-08): plan, persistence, end notifications and the Live Activity.
///
/// Nothing runs in the background. Every view counts down with `Text(timerInterval:)`; local
/// notifications mark each block's end; while the app is open a single sleeping task moves the
/// Live Activity to the next block. When the app comes back, `restore()` catches up.
@MainActor
@Observable
public final class FocusTimer {
    public private(set) var state: FocusSessionState?
    public private(set) var message: String?

    @ObservationIgnored private let file: URL
    @ObservationIgnored private let center: any NotificationScheduling
    @ObservationIgnored private let liveActivities: Bool
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private var activityID: String?
    @ObservationIgnored private let now: @Sendable () -> Date
    private static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Student")

    public init(appGroup: AppGroupContainer = .shared, center: any NotificationScheduling = SystemNotificationScheduler(),
                liveActivities: Bool = true, now: @escaping @Sendable () -> Date = { .now }) {
        file = appGroup.applicationSupportURL.appending(path: "Student/focus.json")
        self.center = center
        self.liveActivities = liveActivities
        self.now = now
        state = Self.load(file)
    }

    public var isRunning: Bool { state != nil }
    public var isPaused: Bool { state?.pausedAt != nil }

    // MARK: Controls

    /// Starts a session. Asks for notification permission the first time (block-end alerts).
    public func start(preset: FocusPreset, title: String, courseID: UUID?, paint: CoursePaint, permissions: PermissionManager?) async {
        await stop()
        let session = FocusSessionState(plan: FocusPlan(preset: preset, start: now()), title: title, courseID: courseID, paint: paint)
        state = session
        save()
        if let permissions, await permissions.request(.notifications).isUsable == false {
            message = String(localized: "Notifications are off, so you won't hear when a block ends. The timer still runs.")
        } else {
            message = nil
        }
        await scheduleNotifications()
        startActivity()
        startTick()
    }

    public func pause() async {
        guard var session = state, session.pausedAt == nil, !session.isFinished(at: now()) else { return }
        session.pausedAt = now()
        state = session
        save()
        tick?.cancel()
        await scheduleNotifications()
        await updateActivity()
    }

    public func resume() async {
        guard var session = state, let pausedAt = session.pausedAt else { return }
        session.plan = session.plan.resumed(pausedAt: pausedAt, now: now())
        session.pausedAt = nil
        state = session
        save()
        await scheduleNotifications()
        await updateActivity()
        startTick()
    }

    public func stop() async {
        tick?.cancel()
        tick = nil
        guard state != nil else { return }
        state = nil
        save()
        await scheduleNotifications()
        endActivity()
    }

    /// Call when the app becomes active: ends a finished session, reattaches the Live Activity and
    /// moves it to the current block.
    public func restore() async {
        guard let session = state else {
            endStrayActivities()
            return
        }
        if session.isFinished(at: now()) {
            await stop()
            return
        }
        if activityID == nil {
            activityID = Activity<FocusActivityAttributes>.activities.first?.id
            if activityID == nil { startActivity() }
        }
        await updateActivity()
        if session.pausedAt == nil { startTick() }
    }

    // MARK: Internals

    private func startTick() {
        tick?.cancel()
        tick = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let session = self.state, session.pausedAt == nil else { return }
                let date = self.now()
                guard let block = session.plan.block(at: date) else {
                    if session.isFinished(at: date) { await self.stop() }
                    return
                }
                try? await Task.sleep(for: .seconds(max(block.end.timeIntervalSince(date), 0.2)))
                guard !Task.isCancelled else { return }
                await self.updateActivity()
            }
        }
    }

    private func scheduleNotifications() async {
        let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(FocusNotifications.identifierPrefix) }
        await center.removePending(pending)
        guard let state else { return }
        for reminder in FocusNotifications.plan(state, now: now()) {
            try? await center.add(reminder)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let state {
                try JSONEncoder().encode(state).write(to: file, options: .atomic)
            } else if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            Self.logger.error("Focus state write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(_ url: URL) -> FocusSessionState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FocusSessionState.self, from: data)
    }

    // MARK: Live Activity

    private func content(at date: Date) -> ActivityContent<FocusActivityAttributes.ContentState>? {
        guard let state, let activityState = state.activityState(at: date) else { return nil }
        // Paused: never stale. Running: stale at the block end, so a missed update reads "done".
        return ActivityContent(state: activityState, staleDate: state.pausedAt == nil ? activityState.blockEnd : nil)
    }

    private func startActivity() {
        guard liveActivities, ActivityAuthorizationInfo().areActivitiesEnabled, let state, let content = content(at: now()) else { return }
        let attributes = FocusActivityAttributes(title: state.title, courseID: state.courseID, paint: state.paint, rounds: state.plan.preset.rounds)
        do {
            activityID = try Activity.request(attributes: attributes, content: content, pushType: nil).id
        } catch {
            // Live Activities off, or too many running: the in-app timer and notifications still work.
            Self.logger.info("Focus Live Activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateActivity() async {
        guard liveActivities, let activityID else { return }
        guard let content = content(at: now()) else {
            if state?.isFinished(at: now()) == true { await stop() }
            return
        }
        await Self.update(id: activityID, content: content)
    }

    private func endActivity() {
        guard liveActivities, let activityID else { return }
        self.activityID = nil
        Task { await Self.end(id: activityID) }
    }

    /// An activity left over from a session that ended while the app was closed.
    private func endStrayActivities() {
        guard liveActivities else { return }
        Task { await Self.endAll() }
    }

    // Activities are looked up by id inside nonisolated helpers (`Activity` isn't Sendable).
    private nonisolated static func update(id: String, content: ActivityContent<FocusActivityAttributes.ContentState>) async {
        await Activity<FocusActivityAttributes>.activities.first { $0.id == id }?.update(content)
    }

    private nonisolated static func end(id: String) async {
        await Activity<FocusActivityAttributes>.activities.first { $0.id == id }?.end(nil, dismissalPolicy: .immediate)
    }

    private nonisolated static func endAll() async {
        for activity in Activity<FocusActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
