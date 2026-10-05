import Foundation
import WellnessFeatureWidgetKit

// MARK: - Streaks

/// A habit's streak for one day, both ways (ticked or not), so the UI and widgets can flip it
/// without recomputing history.
public struct StreakInfo: Equatable, Sendable {
    public var ifDone: Int
    public var ifOpen: Int
    public var unit: StreakUnit
    public var isDone: Bool
    /// Weeks unit only: ticks this week before today.
    public var weekCountBeforeToday: Int

    public var current: Int { isDone ? ifDone : ifOpen }
}

/// Streak rules (W-02):
/// - **Daily / weekdays:** consecutive *due* days that are done. Days the habit isn't due are
///   skipped (they neither count nor break). Today counts once ticked; an open today doesn't
///   break the streak yet ("open today").
/// - **x per week:** consecutive weeks that reached the target. The current week counts once it
///   reaches the target; an unfinished current week doesn't break the streak yet.
///
/// All arithmetic is on `DayKey`s, so DST, time-zone travel and a custom day start can't shift it.
public enum StreakCalculator {
    /// Looks back at most this many days (a streak longer than this still displays correctly up to it).
    public static let lookback = 1100

    public static func streak(for habit: Habit, completedDays: Set<DayKey>, today: DayKey, firstWeekday: Int = 1) -> StreakInfo {
        let doneToday = completedDays.contains(today)
        switch habit.schedule {
        case .daily, .weekdays:
            let dueToday = habit.schedule.isDue(on: today)
            var count = 0
            var day = today.adding(days: -1)
            let floor = max(today.adding(days: -lookback), earliest(habit, completedDays))
            while day >= floor {
                if habit.schedule.isDue(on: day) {
                    guard completedDays.contains(day) else { break }
                    count += 1
                }
                day = day.adding(days: -1)
            }
            return StreakInfo(ifDone: dueToday ? count + 1 : count, ifOpen: count, unit: .day, isDone: doneToday, weekCountBeforeToday: 0)

        case let .timesPerWeek(target):
            let target = max(target, 1)
            let weekStart = today.startOfWeek(firstWeekday: firstWeekday)
            let before = (0..<(today.ordinal - weekStart.ordinal)).filter { completedDays.contains(weekStart.adding(days: $0)) }.count
            var previousWeeks = 0
            var start = weekStart.adding(days: -7)
            let floor = max(today.adding(days: -lookback), earliest(habit, completedDays).startOfWeek(firstWeekday: firstWeekday))
            while start >= floor {
                let count = (0..<7).filter { completedDays.contains(start.adding(days: $0)) }.count
                guard count >= target else { break }
                previousWeeks += 1
                start = start.adding(days: -7)
            }
            let open = previousWeeks + (before >= target ? 1 : 0)
            let done = previousWeeks + (before + 1 >= target ? 1 : 0)
            return StreakInfo(ifDone: done, ifOpen: open, unit: .week, isDone: doneToday, weekCountBeforeToday: before)
        }
    }

    private static func earliest(_ habit: Habit, _ days: Set<DayKey>) -> DayKey {
        days.min() ?? DayKey(ordinal: Int.min / 2)
    }

    /// Milestones celebrated in the UI.
    public static let milestones = [7, 30, 100]

    /// The milestone reached by going from `previous` to `current`, if any.
    public static func milestone(from previous: Int, to current: Int) -> Int? {
        milestones.first { previous < $0 && current >= $0 }
    }
}

// MARK: - Mood trends

public struct MoodTrend: Equatable, Sendable {
    /// Average on the 0 (rough) … 4 (great) scale, `nil` with no logs.
    public var average: Double?
    public var loggedDays: Int
    /// The most frequent mood (ties go to the more positive one).
    public var mostCommon: Mood?

    /// "Mostly good" / "No check-ins yet".
    public var summary: String {
        guard let mostCommon else { return String(localized: "No check-ins yet") }
        return String(localized: "Mostly \(mostCommon.word.lowercased())")
    }
}

public enum MoodTrends {
    /// Trend over the `days` days ending `today` (inclusive).
    public static func trend(_ logs: [MoodLog], days: Int, today: DayKey) -> MoodTrend {
        let from = today.adding(days: -(days - 1))
        let window = latestPerDay(logs).filter { $0.day >= from && $0.day <= today }
        guard !window.isEmpty else { return MoodTrend(average: nil, loggedDays: 0, mostCommon: nil) }
        let average = Double(window.map(\.mood.rawValue).reduce(0, +)) / Double(window.count)
        let counts = Dictionary(grouping: window, by: \.mood).mapValues(\.count)
        let most = counts.max { ($0.value, $0.key.rawValue) < ($1.value, $1.key.rawValue) }?.key
        return MoodTrend(average: average, loggedDays: window.count, mostCommon: most)
    }

    /// Logged values (0…4) for the last `days` days, oldest first; days without a log are skipped.
    public static func history(_ logs: [MoodLog], days: Int, today: DayKey) -> [Int] {
        let from = today.adding(days: -(days - 1))
        return latestPerDay(logs).filter { $0.day >= from && $0.day <= today }.sorted { $0.day < $1.day }.map(\.mood.rawValue)
    }

    /// One log per day (the newest), even if a merge produced duplicates.
    public static func latestPerDay(_ logs: [MoodLog]) -> [MoodLog] {
        Dictionary(grouping: logs, by: \.day).compactMap { $0.value.max { $0.updatedAt < $1.updatedAt } }
    }
}

// MARK: - Goals

public enum GoalMath {
    public static func total(_ goal: Goal) -> Double { goal.progress.reduce(0) { $0 + $1.amount } }

    /// 0…1.
    public static func fraction(_ goal: Goal) -> Double {
        guard goal.target > 0 else { return 0 }
        return min(max(total(goal) / goal.target, 0), 1)
    }

    /// Estimated completion from the recent trend: the average daily rate over the last
    /// `window` days (or since the first entry, if newer), extrapolated linearly.
    /// `nil` when done, with no progress yet, or when the recent rate is zero or negative.
    public static func eta(_ goal: Goal, now: Date, window: Int = 14) -> Date? {
        let remaining = goal.target - total(goal)
        guard remaining > 0, let first = goal.progress.map(\.date).min() else { return nil }
        let windowStart = now.addingTimeInterval(-Double(window) * 86_400)
        let start = max(first, windowStart)
        let recent = goal.progress.filter { $0.date >= start }.reduce(0) { $0 + $1.amount }
        let days = max(now.timeIntervalSince(start) / 86_400, 1)
        let rate = recent / days
        guard rate > 0 else { return nil }
        return now.addingTimeInterval(remaining / rate * 86_400)
    }
}

// MARK: - Merge

public enum CompletionMerge {
    /// One completion per (habit, day): the newest write wins. Handles duplicates from a CloudKit
    /// merge or from a widget tick racing an in-app tick.
    public static func resolve(_ completions: [HabitCompletion]) -> [HabitCompletion] {
        Dictionary(grouping: completions) { "\($0.habitID.uuidString)|\($0.day)" }
            .compactMap { $0.value.max { $0.updatedAt < $1.updatedAt } }
    }

    /// Days a habit is done, after resolving duplicates.
    public static func doneDays(_ completions: [HabitCompletion], habit: UUID) -> Set<DayKey> {
        Set(resolve(completions).filter { $0.habitID == habit && $0.isDone }.map(\.day))
    }
}
