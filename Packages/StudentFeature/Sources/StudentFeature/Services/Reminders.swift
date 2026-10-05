import Foundation
import StudentFeatureWidgetKit
import UserNotifications

/// A local notification the Student section wants pending.
public struct PlannedReminder: Hashable, Sendable {
    public var identifier: String
    public var fireDate: Date
    public var title: String
    public var body: String
    public var courseID: UUID?
}

/// Chooses which class reminders to keep pending (S-04).
///
/// iOS keeps at most 64 pending local notifications per app, shared by every section. We plan a
/// rolling window: the soonest reminders up to `budget` (never more than 64), and the app
/// reschedules after every sync so later ones move into the window as earlier ones fire.
public enum ReminderPlanner {
    /// The system's hard cap per app.
    public static let systemLimit = 64
    /// Student's share, leaving room for Wellness reminders and streak nudges.
    public static let defaultBudget = 48
    /// All Student notification identifiers start with this prefix.
    public static let identifierPrefix = "student.class."
    /// Every prefix the Student sync owns: class, assignment and leave-by reminders. Focus timer
    /// notifications use their own prefix (`FocusNotifications`) so a sync never cancels them.
    public static let managedPrefixes = [identifierPrefix, AssignmentPlanner.identifierPrefix, LeaveByPlanner.identifierPrefix]

    /// Merges plans from every Student source into one rolling window (soonest first, `budget` max).
    public static func combine(_ plans: [PlannedReminder]..., budget: Int = defaultBudget) -> [PlannedReminder] {
        let all = plans.flatMap { $0 }.sorted { ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier) }
        return Array(all.prefix(max(0, min(budget, systemLimit))))
    }

    public static func plan(classes: [ClassSlot], rules: [ReminderRule], now: Date,
                            budget: Int = defaultBudget, calendar: Calendar = .current) -> [PlannedReminder] {
        let limit = max(0, min(budget, systemLimit))
        let global = rules.first { $0.courseID == nil }
        let byCourse = Dictionary(rules.compactMap { rule in rule.courseID.map { ($0, rule) } }, uniquingKeysWith: { a, b in
            a.updatedAt >= b.updatedAt ? a : b
        })

        var planned: [PlannedReminder] = []
        for slot in classes where slot.start > now {
            // A course rule (enabled or not) overrides the global rule for that course.
            guard let rule = slot.courseID.flatMap({ byCourse[$0] }) ?? global, rule.isEnabled else { continue }
            for offset in rule.offsets.sorted() {
                // "1 day" keeps the wall-clock time across DST changes; shorter offsets are durations.
                let fire = offset == .oneDay
                    ? calendar.date(byAdding: .day, value: -1, to: slot.start) ?? slot.start.addingTimeInterval(-offset.interval)
                    : slot.start.addingTimeInterval(-offset.interval)
                guard fire > now else { continue }
                planned.append(PlannedReminder(
                    identifier: "\(identifierPrefix)\(slot.id).\(offset.rawValue)",
                    fireDate: fire,
                    title: String(localized: "\(slot.code) in \(offset.title)"),
                    body: [ScheduleFormat.dayAndTime(slot.start, now: fire), slot.shortLocation].compactMap { $0 }.joined(separator: " · "),
                    courseID: slot.courseID))
            }
        }
        planned.sort { ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier) }
        return Array(planned.prefix(limit))
    }
}

/// The parts of `UNUserNotificationCenter` the scheduler uses (mockable in tests).
public protocol NotificationScheduling: Sendable {
    func pendingIdentifiers() async -> [String]
    func removePending(_ identifiers: [String]) async
    func add(_ reminder: PlannedReminder) async throws
}

public struct SystemNotificationScheduler: NotificationScheduling {
    public init() {}

    public func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    public func removePending(_ identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func add(_ reminder: PlannedReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = "student"
        content.userInfo = ["url": StudentDeepLink.url(course: reminder.courseID).absoluteString]
        // Calendar-component trigger in the current time zone, so DST shifts keep wall-clock time.
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
    }
}

/// Replaces the Student section's pending reminders with a fresh plan (only our prefix is touched).
public struct ReminderScheduler: Sendable {
    private let center: any NotificationScheduling

    public init(center: any NotificationScheduling = SystemNotificationScheduler()) {
        self.center = center
    }

    /// - Returns: the number of reminders now pending for Student.
    @discardableResult
    public func reschedule(_ plan: [PlannedReminder]) async -> Int {
        let pending = await center.pendingIdentifiers()
        let ours = pending.filter { id in ReminderPlanner.managedPrefixes.contains { id.hasPrefix($0) } }
        // Never exceed the system cap even if other sections already hold slots.
        let othersCount = pending.count - ours.count
        let allowed = max(0, ReminderPlanner.systemLimit - othersCount)
        let wanted = Array(plan.prefix(allowed))
        let wantedIDs = Set(wanted.map(\.identifier))

        await center.removePending(ours.filter { !wantedIDs.contains($0) })
        let existing = Set(ours)
        var count = 0
        for reminder in wanted {
            if existing.contains(reminder.identifier) {
                count += 1
                continue
            }
            do {
                try await center.add(reminder)
                count += 1
            } catch {
                continue
            }
        }
        return count
    }
}
