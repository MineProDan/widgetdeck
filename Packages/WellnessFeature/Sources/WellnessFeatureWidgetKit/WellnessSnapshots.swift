import CoreKit
import Foundation

// MARK: - Habits

/// How a habit's streak is counted.
public enum StreakUnit: String, Codable, Sendable {
    /// Consecutive due days (daily and weekday schedules).
    case day
    /// Consecutive weeks that met an "x per week" target.
    case week
}

/// One habit as the widgets see it for one day. The app precomputes both possible streaks
/// (`streakIfDone` / `streakIfOpen`), so a widget tick can flip the number without any history.
public struct HabitWidgetItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var isDue: Bool
    public var isDone: Bool
    public var streakIfDone: Int
    public var streakIfOpen: Int
    public var unit: StreakUnit
    /// Due weekdays (1 = Sunday … 7 = Saturday); `nil` = every day. Used to project tomorrow.
    public var dueWeekdays: [Int]?
    /// "x per week" target (unit `.week` only).
    public var weeklyTarget: Int?
    /// Completions this week before today (unit `.week` only).
    public var weekCountBeforeToday: Int

    public init(id: UUID, name: String, isDue: Bool, isDone: Bool, streakIfDone: Int, streakIfOpen: Int,
                unit: StreakUnit = .day, dueWeekdays: [Int]? = nil, weeklyTarget: Int? = nil, weekCountBeforeToday: Int = 0) {
        self.id = id
        self.name = name
        self.isDue = isDue
        self.isDone = isDone
        self.streakIfDone = streakIfDone
        self.streakIfOpen = streakIfOpen
        self.unit = unit
        self.dueWeekdays = dueWeekdays
        self.weeklyTarget = weeklyTarget
        self.weekCountBeforeToday = weekCountBeforeToday
    }

    /// The streak to show right now.
    public var streak: Int { isDone ? streakIfDone : streakIfOpen }

    /// This item on the following day (nothing ticked yet). Mirrors `StreakCalculator` rules.
    func projectedToNextDay(from day: DayKey, firstWeekday: Int) -> HabitWidgetItem {
        var next = self
        let tomorrow = day.adding(days: 1)
        next.isDone = false
        switch unit {
        case .day:
            let open = isDue ? (isDone ? streakIfDone : 0) : streak
            let dueTomorrow = dueWeekdays.map { $0.contains(tomorrow.weekday) } ?? true
            next.isDue = dueTomorrow
            next.streakIfOpen = open
            next.streakIfDone = dueTomorrow ? open + 1 : open
        case .week:
            let target = max(weeklyTarget ?? 1, 1)
            let count = weekCountBeforeToday + (isDone ? 1 : 0)
            if tomorrow.weekday == firstWeekday {
                // New week: an unmet week breaks the streak.
                let open = count >= target ? streak : 0
                next.weekCountBeforeToday = 0
                next.streakIfOpen = open
                next.streakIfDone = target <= 1 ? open + 1 : open
            } else {
                let open = streak
                next.weekCountBeforeToday = count
                next.streakIfOpen = open
                next.streakIfDone = (count < target && count + 1 >= target) ? open + 1 : open
            }
            next.isDue = true
        }
        return next
    }
}

/// Habits widget snapshot (W-02). Written by the app; ticked in place by `ToggleHabitIntent`.
public struct HabitsSnapshot: WidgetSnapshot, Equatable {
    public static let kind: WidgetKind = .habits

    public var generatedAt: Date
    public var day: DayKey
    public var dayStartHour: Int
    /// 1 = Sunday, 2 = Monday (the user's locale at generation time).
    public var firstWeekday: Int
    /// Active habits in the user's order.
    public var items: [HabitWidgetItem]

    public init(generatedAt: Date, day: DayKey, dayStartHour: Int, firstWeekday: Int, items: [HabitWidgetItem]) {
        self.generatedAt = generatedAt
        self.day = day
        self.dayStartHour = dayStartHour
        self.firstWeekday = firstWeekday
        self.items = items
    }

    public var clock: WellnessDayClock { WellnessDayClock(dayStartHour: dayStartHour) }

    /// Habits due on `day`.
    public var dueItems: [HabitWidgetItem] { items.filter(\.isDue) }
    public var doneCount: Int { dueItems.filter(\.isDone).count }

    /// The snapshot as it will look on `target` (up to two weeks ahead; older data resets).
    public func projected(to target: DayKey) -> HabitsSnapshot {
        guard target > day else { return self }
        var snapshot = self
        let steps = target.ordinal - day.ordinal
        guard steps <= 14 else {
            snapshot.items = items.map {
                var item = $0
                item.isDone = false
                item.streakIfOpen = 0
                item.streakIfDone = 1
                item.weekCountBeforeToday = 0
                item.isDue = $0.dueWeekdays.map { $0.contains(target.weekday) } ?? true
                return item
            }
            snapshot.day = target
            return snapshot
        }
        for _ in 0..<steps {
            snapshot.items = snapshot.items.map { $0.projectedToNextDay(from: snapshot.day, firstWeekday: firstWeekday) }
            snapshot.day = snapshot.day.adding(days: 1)
        }
        return snapshot
    }

    /// The habit with the longest current streak (Streak widget).
    public var topStreak: HabitWidgetItem? {
        items.filter { $0.streak > 0 }.max { ($0.streak, $1.name) < ($1.streak, $0.name) }
    }
}

// MARK: - Mood

/// One logged day for the mood widgets.
public struct DayMood: Codable, Hashable, Sendable {
    public var day: DayKey
    public var mood: Mood

    public init(day: DayKey, mood: Mood) {
        self.day = day
        self.mood = mood
    }
}

/// Mood widget snapshot (W-03). Notes never leave the app: only the day and the mood are here.
public struct MoodSnapshot: WidgetSnapshot, Equatable {
    public static let kind: WidgetKind = .mood

    public var generatedAt: Date
    public var dayStartHour: Int
    /// Up to the last 14 logged days, oldest first.
    public var recent: [DayMood]

    public init(generatedAt: Date, dayStartHour: Int, recent: [DayMood]) {
        self.generatedAt = generatedAt
        self.dayStartHour = dayStartHour
        self.recent = recent
    }

    public var clock: WellnessDayClock { WellnessDayClock(dayStartHour: dayStartHour) }

    public func mood(on day: DayKey) -> Mood? { recent.last { $0.day == day }?.mood }

    /// Records `mood` for `day`, replacing that day's entry (one mood per day).
    public mutating func log(_ mood: Mood, on day: DayKey) {
        recent.removeAll { $0.day == day }
        recent.append(DayMood(day: day, mood: mood))
        recent.sort { $0.day < $1.day }
        recent = Array(recent.suffix(14))
    }
}

// MARK: - Flow

/// Wellness facts for the cross-section Flow widget (P-11): what's left today and whether the
/// mood check-in is done. Written next to the other snapshots as `wellness-flow.json`.
public struct WellnessFlowSnapshot: WidgetSnapshot, Equatable {
    public static let kind: WidgetKind = .flow
    public static let fileName = "wellness-flow"

    public var generatedAt: Date
    public var day: DayKey
    public var habitsDue: Int
    public var habitsDone: Int
    /// Names of habits still open today, in order ("Stretch").
    public var openHabitNames: [String]
    public var moodLoggedToday: Bool

    public init(generatedAt: Date, day: DayKey, habitsDue: Int, habitsDone: Int, openHabitNames: [String], moodLoggedToday: Bool) {
        self.generatedAt = generatedAt
        self.day = day
        self.habitsDue = habitsDue
        self.habitsDone = habitsDone
        self.openHabitNames = openHabitNames
        self.moodLoggedToday = moodLoggedToday
    }

    public init(habits: HabitsSnapshot?, mood: MoodSnapshot?, day: DayKey, now: Date) {
        let today = habits?.projected(to: day)
        self.init(generatedAt: now, day: day,
                  habitsDue: today?.dueItems.count ?? 0,
                  habitsDone: today?.doneCount ?? 0,
                  openHabitNames: today?.dueItems.filter { !$0.isDone }.map(\.name) ?? [],
                  moodLoggedToday: mood?.mood(on: day) != nil)
    }
}

// MARK: - Deep links

/// `widgetx://section/wellness?habit=<uuid>` · `?breathe=box` · `?mood=log`.
public enum WellnessDeepLink {
    public static func url(habit: UUID? = nil, breathe: BreathingPattern? = nil, mood: Bool = false) -> URL {
        var components = URLComponents()
        components.scheme = AppIdentifiers.urlScheme
        components.host = "section"
        components.path = "/\(AppSection.wellness.rawValue)"
        var items: [URLQueryItem] = []
        if let habit { items.append(URLQueryItem(name: "habit", value: habit.uuidString)) }
        if let breathe { items.append(URLQueryItem(name: "breathe", value: breathe.rawValue)) }
        if mood { items.append(URLQueryItem(name: "mood", value: "log")) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url ?? AppSection.wellness.deepLink
    }

    private static func value(_ name: String, in url: URL) -> String? {
        guard AppSection(deepLink: url) == .wellness else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    public static func habitID(from url: URL) -> UUID? { value("habit", in: url).flatMap(UUID.init(uuidString:)) }
    public static func breathingPattern(from url: URL) -> BreathingPattern? { value("breathe", in: url).flatMap(BreathingPattern.init(rawValue:)) }
    public static func opensMood(_ url: URL) -> Bool { value("mood", in: url) == "log" }
}
