@preconcurrency import EventKit
import Foundation

/// Read-only calendar access. There is deliberately no save/remove API here: Widgetdeck never
/// writes to the user's calendar.
public protocol CalendarProviding: Sendable {
    func calendars() async -> [CalendarSource]
    func events(from start: Date, to end: Date, calendarIDs: Set<String>) async -> [CalendarEvent]
}

/// The rolling sync window (S-02): yesterday through two weeks ahead.
public enum SyncWindow {
    public static func range(now: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 15, to: today) ?? now
        return (start, end)
    }
}

/// EventKit implementation. Needs full event access (`NSCalendarsFullAccessUsageDescription`),
/// requested through CoreKit's `PermissionManager`.
public final class EventKitCalendarProvider: CalendarProviding, @unchecked Sendable {
    // EKEventStore is thread-safe for reads; it is only used for queries here.
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public func calendars() async -> [CalendarSource] {
        eventCalendars()
            .map { CalendarSource(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source?.title ?? "") }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    public func events(from start: Date, to end: Date, calendarIDs: Set<String>) async -> [CalendarEvent] {
        let calendars = eventCalendars().filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).compactMap(Self.makeEvent)
    }

    /// An `EKEventStore` created before the user granted access keeps returning no calendars until it
    /// reloads its sources (access is granted later, from the primer, on a different store). If access
    /// is granted but the list is empty, reset once and ask again.
    private func eventCalendars() -> [EKCalendar] {
        let calendars = store.calendars(for: .event)
        guard calendars.isEmpty, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return calendars }
        store.reset()
        return store.calendars(for: .event)
    }

    static func makeEvent(_ event: EKEvent) -> CalendarEvent? {
        guard let start = event.startDate, let end = event.endDate else { return nil }
        let base = event.eventIdentifier ?? event.calendarItemIdentifier
        let series = event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
        // A single edited occurrence ("this event only") is detached from its series and reports no
        // recurrence rules; it's still part of a repeating event, so keep treating it as recurring.
        let weekly = (event.recurrenceRules?.contains { $0.frequency == .weekly } ?? false) || event.isDetached
        return CalendarEvent(id: "\(base)@\(Int(start.timeIntervalSince1970))", seriesKey: series,
                             calendarID: event.calendar?.calendarIdentifier ?? "", title: event.title ?? "",
                             location: event.location, notes: event.notes, start: start, end: end,
                             isAllDay: event.isAllDay, isWeeklyRecurring: weekly)
    }
}
