import Foundation

/// What a Student widget shows at one moment. Pure value so timelines are testable without WidgetKit.
public struct ScheduleMoment: Hashable, Sendable {
    public var date: Date
    /// The class in progress at `date`, if any.
    public var current: ClassSlot?
    /// The next class starting after `date`.
    public var next: ClassSlot?
    /// Classes on `date`'s calendar day (for Today's Schedule), in start order.
    public var today: [ClassSlot]
    /// No snapshot yet: the widget shows its "connect your calendar" state.
    public var hasData: Bool

    /// The class the Next Class widget features: the one in progress, else the next one.
    public var featured: ClassSlot? { current ?? next }
}

/// Builds timeline moments at every class boundary (start, end and "leave by") plus each midnight, so the
/// widget flips between classes without a reload. Countdowns inside a moment use
/// `Text(date, style: .relative)`, which the system updates on its own (Platform Reality Rule 1).
public enum ScheduleTimeline {
    /// How long before a class the widgets ask to be on top of their Smart Stack.
    public static let relevanceLead: TimeInterval = 60 * 60

    /// Smart Stack score for a moment: highest from an hour before class until it starts, still
    /// high during class, low otherwise. iOS treats it as a hint.
    public static func relevanceScore(_ moment: ScheduleMoment) -> Float {
        guard moment.hasData else { return 0 }
        if moment.current != nil { return 60 }
        guard let next = moment.next else { return 0 }
        let until = next.start.timeIntervalSince(moment.date)
        if until <= relevanceLead { return 100 }
        return Calendar.current.isDate(next.start, inSameDayAs: moment.date) ? 10 : 1
    }

    /// How far ahead one timeline reaches. WidgetKit asks again at the end (`reloadDate`).
    public static let horizon: TimeInterval = 24 * 60 * 60

    public static func moments(classes: [ClassSlot]?, now: Date, calendar: Calendar = .current,
                               horizon: TimeInterval = horizon) -> [ScheduleMoment] {
        guard let classes else {
            return [ScheduleMoment(date: now, current: nil, next: nil, today: [], hasData: false)]
        }
        let sorted = classes.sorted { $0.start < $1.start }
        let limit = now.addingTimeInterval(horizon)

        var dates: Set<Date> = [now]
        for slot in sorted {
            if slot.start > now && slot.start <= limit { dates.insert(slot.start) }
            if slot.end > now && slot.end <= limit { dates.insert(slot.end) }
            if let leave = slot.leaveBy, leave > now && leave <= limit { dates.insert(leave) }
            // An hour before class the widget asks the Smart Stack to bring it to the top.
            let soon = slot.start.addingTimeInterval(-relevanceLead)
            if soon > now && soon <= limit { dates.insert(soon) }
        }
        // Midnights inside the horizon (DST-safe: computed by the calendar, not by adding 24 h).
        var day = calendar.startOfDay(for: now)
        while let nextDay = calendar.date(byAdding: .day, value: 1, to: day), nextDay <= limit {
            dates.insert(nextDay)
            day = nextDay
        }
        return dates.sorted().map { moment(at: $0, sorted: sorted, calendar: calendar) }
    }

    public static func moment(at date: Date, sorted: [ClassSlot], calendar: Calendar = .current) -> ScheduleMoment {
        let current = sorted.first { $0.isInProgress(at: date) }
        let next = sorted.first { $0.start > date }
        let today = sorted.filter { calendar.isDate($0.start, inSameDayAs: date) }
        return ScheduleMoment(date: date, current: current, next: next, today: today, hasData: true)
    }

    /// When WidgetKit should ask for a new timeline: the end of the horizon, or sooner when the
    /// snapshot runs out of classes (the app will have written a fresher one by then).
    public static func reloadDate(classes: [ClassSlot]?, now: Date, horizon: TimeInterval = horizon) -> Date {
        let end = now.addingTimeInterval(horizon)
        guard let last = classes?.map(\.end).max(), last > now else { return now.addingTimeInterval(6 * 60 * 60) }
        return min(end, last)
    }
}
