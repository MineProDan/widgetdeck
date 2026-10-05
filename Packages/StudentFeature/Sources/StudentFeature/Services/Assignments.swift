@preconcurrency import EventKit
import Foundation
import StudentFeatureWidgetKit

/// S-05 logic: assignments → "Due soon" rows, widget items and due reminders. Pure, no I/O.
public enum AssignmentPlanner {
    /// Notification identifier prefix for assignment reminders.
    public static let identifierPrefix = "student.due."

    /// Assignments as `DeadlineItem`s so they sit next to calendar deadlines in "Due soon".
    public static func deadlineItems(_ assignments: [Assignment], courses: [Course]) -> [DeadlineItem] {
        let byID = Dictionary(courses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return assignments.map { assignment in
            let course = assignment.courseID.flatMap { byID[$0] }
            return DeadlineItem(id: assignment.occurrenceID, seriesKey: assignment.occurrenceID, title: assignment.title,
                                courseID: course?.id, code: course?.code, due: assignment.due,
                                paint: course?.paint ?? .coral, isDone: assignment.isDone, assignmentID: assignment.id)
        }
    }

    /// Calendar deadlines + assignments, by due date.
    public static func merged(calendar: [DeadlineItem], assignments: [DeadlineItem]) -> [DeadlineItem] {
        (calendar + assignments).sorted { ($0.due, $0.id) < ($1.due, $1.id) }
    }

    /// Open, not-yet-due items for the Assignments widget.
    public static func widgetSnapshot(_ deadlines: [DeadlineItem], now: Date) -> AssignmentsSnapshot {
        AssignmentsSnapshot(items: deadlines.filter { !$0.isDone && $0.due > now }.map {
            DueSlot(id: $0.id, title: $0.title, code: $0.code, courseID: $0.courseID, due: $0.due, paint: $0.paint)
        }, generatedAt: now)
    }

    /// One reminder per open assignment, `offset` before it's due.
    public static func reminders(_ assignments: [Assignment], courses: [Course], offset: ReminderOffset?, now: Date,
                                 calendar: Calendar = .current) -> [PlannedReminder] {
        guard let offset else { return [] }
        let codes = Dictionary(courses.map { ($0.id, $0.code) }, uniquingKeysWith: { a, _ in a })
        return assignments.compactMap { assignment in
            guard !assignment.isDone, assignment.due > now else { return nil }
            let fire = offset == .oneDay
                ? calendar.date(byAdding: .day, value: -1, to: assignment.due) ?? assignment.due.addingTimeInterval(-offset.interval)
                : assignment.due.addingTimeInterval(-offset.interval)
            guard fire > now else { return nil }
            let code = assignment.courseID.flatMap { codes[$0] }
            return PlannedReminder(// The fire time is part of the id: the scheduler keeps pending ids as they are, so a
                                   // changed due date must produce a new id to replace the old request.
                                   identifier: "\(identifierPrefix)\(assignment.id.uuidString).\(Int(fire.timeIntervalSince1970))",
                                   fireDate: fire,
                                   title: String(localized: "\(assignment.title) due in \(offset.title)"),
                                   body: [code, ScheduleFormat.dayAndTime(assignment.due, now: fire)].compactMap { $0 }.joined(separator: " · "),
                                   courseID: assignment.courseID)
        }
    }
}

// MARK: - Reminders import

/// A read-only copy of one Apple Reminders item.
public struct ReminderItem: Hashable, Sendable {
    public var externalID: String
    public var title: String
    public var due: Date?
    public var isCompleted: Bool

    public init(externalID: String, title: String, due: Date?, isCompleted: Bool) {
        self.externalID = externalID
        self.title = title
        self.due = due
        self.isCompleted = isCompleted
    }
}

public struct ReminderListSource: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var sourceTitle: String

    public init(id: String, title: String, sourceTitle: String) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
    }
}

/// Read-only access to Apple Reminders (mockable).
public protocol RemindersProviding: Sendable {
    func lists() async -> [ReminderListSource]
    func reminders(inList listID: String) async -> [ReminderItem]
}

/// EventKit implementation. Only fetches; there's no save or remove call, so it never writes to Reminders.
public final class EventKitRemindersProvider: RemindersProviding, @unchecked Sendable {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public func lists() async -> [ReminderListSource] {
        reminderCalendars()
            .map { ReminderListSource(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source?.title ?? "") }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    public func reminders(inList listID: String) async -> [ReminderItem] {
        let calendars = reminderCalendars().filter { $0.calendarIdentifier == listID }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForReminders(in: calendars)
        let items: [ReminderItem] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.makeItem))
            }
        }
        return items
    }

    private func reminderCalendars() -> [EKCalendar] {
        let calendars = store.calendars(for: .reminder)
        guard calendars.isEmpty, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return calendars }
        store.reset()
        return store.calendars(for: .reminder)
    }

    static func makeItem(_ reminder: EKReminder) -> ReminderItem {
        ReminderItem(externalID: reminder.calendarItemExternalIdentifier ?? reminder.calendarItemIdentifier,
                     title: reminder.title ?? "",
                     due: reminder.dueDateComponents.flatMap { components in
                         // A date-only due date means "by the end of that day".
                         let hasTime = components.hour != nil
                         guard let date = Calendar.current.date(from: components) else { return nil }
                         return hasTime ? date : Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: date)
                     },
                     isCompleted: reminder.isCompleted)
    }
}

/// Merges a Reminders list into assignments (S-05). Pure.
public enum ReminderImporter {
    public struct Result: Equatable, Sendable {
        /// New or changed assignments to save.
        public var changed: [Assignment]
        /// Imported assignments whose reminder is gone from the list: delete these.
        public var removed: [UUID]
    }

    /// Rules:
    ///   - Only reminders with a due date and a title are imported.
    ///   - A new reminder becomes an assignment; its course is guessed from a code in the title.
    ///   - An existing import keeps the user's course and done flag; title and due date follow
    ///     Reminders; completing it in Reminders marks it done here (never the other way round).
    ///   - An import from `listID` whose reminder was deleted there (or lost its due date) is removed.
    public static func merge(_ reminders: [ReminderItem], listID: String, into existing: [Assignment], courses: [Course], now: Date) -> Result {
        let byExternal = Dictionary(existing.compactMap { a in a.reminderExternalID.map { ($0, a) } }, uniquingKeysWith: { a, _ in a })
        var changed: [Assignment] = []
        var kept: Set<String> = []
        for item in reminders {
            guard let due = item.due, let title = item.title.nilIfBlank else { continue }
            kept.insert(item.externalID)
            if var current = byExternal[item.externalID] {
                let before = current
                current.title = title
                current.due = due
                if item.isCompleted { current.isDone = true }
                if current != before {
                    current.updatedAt = now
                    changed.append(current)
                }
            } else {
                // Completed reminders that we never imported stay out.
                guard !item.isCompleted else { continue }
                let code = EventClassifier.courseCode(in: title)
                let course = code.flatMap { code in courses.first { $0.code == code } }
                changed.append(Assignment(title: title, courseID: course?.id, due: due, reminderExternalID: item.externalID,
                                          reminderListID: listID, updatedAt: now))
            }
        }
        let removed = existing.filter { a in
            a.reminderListID == listID && a.reminderExternalID.map { !kept.contains($0) } == true
        }.map(\.id)
        return Result(changed: changed, removed: removed)
    }
}
