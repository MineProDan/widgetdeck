import Foundation

/// The mockup's week (Student.png), placed in the current week. Shown when calendar access is
/// denied or deferred ("Connect later"), and in previews. Never written to widget snapshots.
public enum DemoSchedule {
    private struct Item {
        let weekday: Int // 0 = Monday
        let start: Double
        let end: Double
        let title: String
        let location: String?
        let weekly: Bool
    }

    private static let items: [Item] = [
        Item(weekday: 0, start: 9, end: 10, title: "BIO 201", location: "Room 3B", weekly: true),
        Item(weekday: 2, start: 9, end: 10, title: "BIO 201", location: "Room 3B", weekly: true),
        Item(weekday: 4, start: 9, end: 10, title: "BIO 201", location: "Room 3B", weekly: true),
        Item(weekday: 1, start: 9, end: 10, title: "ENG 110", location: "Hall A", weekly: true),
        Item(weekday: 3, start: 9, end: 10, title: "ENG 110", location: "Hall A", weekly: true),
        Item(weekday: 1, start: 10.5, end: 12, title: "CHEM 150", location: "Hall C", weekly: true),
        Item(weekday: 3, start: 10.5, end: 12, title: "CHEM 150", location: "Hall C", weekly: true),
        Item(weekday: 0, start: 13, end: 14, title: "PSY 101", location: "Room 12", weekly: true),
        Item(weekday: 2, start: 13, end: 14, title: "PSY 101", location: "Room 12", weekly: true),
        Item(weekday: 3, start: 14, end: 15.5, title: "CHEM 150 Lab", location: "Lab 2", weekly: true)
    ]

    /// The mockup's course paints (BIO coral, ENG sand, CHEM tide, PSY sage).
    public static let courses: [Course] = [
        Course(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, code: "BIO 201", paint: .coral, updatedAt: .distantPast),
        Course(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, code: "ENG 110", paint: .sand, updatedAt: .distantPast),
        Course(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, code: "CHEM 150", paint: .tide, updatedAt: .distantPast),
        Course(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, code: "PSY 101", paint: .sage, updatedAt: .distantPast)
    ]

    public static func events(now: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        let monday = WeekMath.monday(of: now, calendar: calendar)
        func date(_ weekday: Int, _ hour: Double, weekOffset: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: weekday + weekOffset * 7, to: monday) ?? monday
            return calendar.date(bySettingHour: Int(hour), minute: Int((hour.truncatingRemainder(dividingBy: 1)) * 60), second: 0, of: day) ?? day
        }
        var events: [CalendarEvent] = []
        for week in 0...1 {
            for (index, item) in items.enumerated() {
                let start = date(item.weekday, item.start, weekOffset: week)
                events.append(CalendarEvent(id: "demo-\(index)-\(week)", seriesKey: "demo-series-\(index)", calendarID: "demo",
                                            title: item.title, location: item.location, start: start,
                                            end: date(item.weekday, item.end, weekOffset: week), isWeeklyRecurring: item.weekly))
            }
        }
        // Due soon, relative to today like the mockup (tomorrow night, Friday, next Monday).
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        events.append(CalendarEvent(id: "demo-due-1", seriesKey: "demo-due-1", calendarID: "demo", title: "CHEM 150 Lab report due",
                                    start: tomorrow.addingTimeInterval(23 * 3600 + 59 * 60), end: tomorrow.addingTimeInterval(24 * 3600)))
        events.append(CalendarEvent(id: "demo-due-2", seriesKey: "demo-due-2", calendarID: "demo", title: "ENG 110 Reading response due",
                                    start: date(4, 17, weekOffset: date(4, 17) < now ? 1 : 0), end: date(4, 17.5, weekOffset: date(4, 17) < now ? 1 : 0)))
        events.append(CalendarEvent(id: "demo-due-3", seriesKey: "demo-due-3", calendarID: "demo", title: "BIO 201 Problem set 4 due",
                                    start: date(0, 9, weekOffset: 1), end: date(0, 9.5, weekOffset: 1)))
        return events
    }
}

/// Week helpers (Monday-first, like the mockup grid).
public enum WeekMath {
    public static func monday(of date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day) // 1 = Sunday
        let offset = (weekday + 5) % 7 // Monday → 0 … Sunday → 6
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    /// Monday-based index (0…6) of `date`.
    public static func weekdayIndex(_ date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }
}
