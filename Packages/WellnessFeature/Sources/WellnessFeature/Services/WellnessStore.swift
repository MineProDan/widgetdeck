import CoreKit
import Foundation
import Observation
import os
import WellnessFeatureWidgetKit

/// Builds the widget snapshots from the section's data.
public enum WellnessSnapshotBuilder {
    public static func habits(_ habits: [Habit], completions: [HabitCompletion], clock: WellnessDayClock,
                              now: Date, firstWeekday: Int) -> HabitsSnapshot {
        let today = clock.day(for: now)
        let resolved = CompletionMerge.resolve(completions)
        let items = habits.filter { !$0.isArchived }.sorted(by: WellnessStore.order).map { habit in
            let days = Set(resolved.filter { $0.habitID == habit.id && $0.isDone }.map(\.day))
            let info = StreakCalculator.streak(for: habit, completedDays: days, today: today, firstWeekday: firstWeekday)
            var weekdays: [Int]?
            var target: Int?
            switch habit.schedule {
            case .daily: break
            case let .weekdays(set): weekdays = set.sorted()
            case let .timesPerWeek(n): target = n
            }
            return HabitWidgetItem(id: habit.id, name: habit.name, isDue: habit.schedule.isDue(on: today), isDone: info.isDone,
                                   streakIfDone: info.ifDone, streakIfOpen: info.ifOpen, unit: info.unit,
                                   dueWeekdays: weekdays, weeklyTarget: target, weekCountBeforeToday: info.weekCountBeforeToday)
        }
        return HabitsSnapshot(generatedAt: now, day: today, dayStartHour: clock.dayStartHour, firstWeekday: firstWeekday, items: items)
    }

    public static func mood(_ logs: [MoodLog], clock: WellnessDayClock, now: Date) -> MoodSnapshot {
        let today = clock.day(for: now)
        let recent = MoodTrends.latestPerDay(logs)
            .filter { $0.day <= today && $0.day > today.adding(days: -14) }
            .sorted { $0.day < $1.day }
            .map { DayMood(day: $0.day, mood: $0.mood) }
        return MoodSnapshot(generatedAt: now, dayStartHour: clock.dayStartHour, recent: recent)
    }
}

/// State and actions for the Wellness section (W-01…W-05).
@MainActor
@Observable
public final class WellnessStore {
    public private(set) var habits: [Habit] = []
    public private(set) var completions: [HabitCompletion] = []
    public private(set) var moods: [MoodLog] = []
    public private(set) var goals: [Goal] = []
    public private(set) var settings: WellnessSettings
    public private(set) var today: DayKey
    public private(set) var isLoaded = false
    /// User-facing error line (never a blank screen).
    public var errorMessage: String?
    /// Set when a tick reaches 7 / 30 / 100 (shown once in the habit row).
    public private(set) var milestone: (habitID: UUID, count: Int)?

    @ObservationIgnored private let repository: any WellnessRepository
    @ObservationIgnored private let settingsFile: WellnessSettingsFile
    @ObservationIgnored private let inbox: WellnessWidgetInbox
    @ObservationIgnored private let reloadCoordinator: WidgetReloadCoordinator
    @ObservationIgnored private let reminders: any MoodReminding
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let firstWeekday: Int
    private static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Wellness")

    /// One coordinator for the section, so its debounce spans every store instance.
    public static let sharedReloadCoordinator = WidgetReloadCoordinator()

    public init(repository: any WellnessRepository = FileWellnessRepository(),
                settingsFile: WellnessSettingsFile = WellnessSettingsFile(),
                inbox: WellnessWidgetInbox = WellnessWidgetInbox(),
                reloadCoordinator: WidgetReloadCoordinator = WellnessStore.sharedReloadCoordinator,
                reminders: any MoodReminding = MoodReminderScheduler(),
                firstWeekday: Int = Calendar.current.firstWeekday,
                now: @escaping @Sendable () -> Date = { .now }) {
        self.repository = repository
        self.settingsFile = settingsFile
        self.inbox = inbox
        self.reloadCoordinator = reloadCoordinator
        self.reminders = reminders
        self.firstWeekday = firstWeekday
        self.now = now
        let settings = settingsFile.read()
        self.settings = settings
        self.today = WellnessDayClock(dayStartHour: settings.dayStartHour).day(for: now())
    }

    public var clock: WellnessDayClock { WellnessDayClock(dayStartHour: settings.dayStartHour) }

    nonisolated static func order(_ a: Habit, _ b: Habit) -> Bool { (a.sortOrder, a.createdAt) < (b.sortOrder, b.createdAt) }

    // MARK: Loading

    /// Loads everything, folds in widget taps and republishes widgets. Call on appear, when the
    /// scene becomes active and from background refresh.
    public func load() async {
        today = clock.day(for: now())
        do {
            try await applyInbox()
            async let habits = repository.habits()
            async let completions = repository.completions()
            async let moods = repository.moods()
            async let goals = repository.goals()
            self.habits = try await habits.filter { !$0.isArchived }.sorted(by: Self.order)
            self.completions = CompletionMerge.resolve(try await completions)
            self.moods = MoodTrends.latestPerDay(try await moods)
            self.goals = try await goals.sorted { $0.createdAt < $1.createdAt }
            errorMessage = nil
        } catch {
            Self.logger.error("Wellness load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "Couldn't load your wellness data. Pull to try again.")
        }
        isLoaded = true
        await publish(flush: false)
    }

    /// Applies taps made on widgets. A tap only wins over a newer in-app change if it's newer.
    func applyInbox() async throws {
        let actions = try inbox.drain()
        guard !actions.isEmpty else { return }
        let existingCompletions = CompletionMerge.resolve(try await repository.completions())
        let existingMoods = MoodTrends.latestPerDay(try await repository.moods())
        for action in actions {
            switch action {
            case let .setHabit(habitID, day, isDone, at, zone):
                let id = StableID.completion(habit: habitID, day: day)
                if let current = existingCompletions.first(where: { $0.id == id }), current.updatedAt > at { continue }
                try await repository.save(HabitCompletion(habitID: habitID, day: day, isDone: isDone, timeZoneID: zone, updatedAt: at))
            case let .logMood(day, mood, at, zone):
                let current = existingMoods.first { $0.day == day }
                if let current, current.updatedAt > at { continue }
                try await repository.save(MoodLog(day: day, mood: mood, note: current?.note, timeZoneID: zone, updatedAt: at))
            }
        }
    }

    // MARK: Habits

    public var dueHabits: [Habit] { habits.filter { $0.schedule.isDue(on: today) } }

    public func isDone(_ habit: Habit, on day: DayKey? = nil) -> Bool {
        completions.contains { $0.habitID == habit.id && $0.day == (day ?? today) && $0.isDone }
    }

    public func streak(for habit: Habit) -> StreakInfo {
        StreakCalculator.streak(for: habit, completedDays: CompletionMerge.doneDays(completions, habit: habit.id),
                                today: today, firstWeekday: firstWeekday)
    }

    /// Header line: "2 of 3 habits done today".
    public var subtitle: String {
        let due = dueHabits
        guard !due.isEmpty else { return habits.isEmpty ? String(localized: "Small habits, one tap a day") : String(localized: "No habits due today") }
        return String(localized: "\(due.filter { isDone($0) }.count) of \(due.count) habits done today")
    }

    public func toggle(_ habit: Habit) async {
        let before = streak(for: habit)
        let completion = HabitCompletion(habitID: habit.id, day: today, isDone: !isDone(habit), updatedAt: now())
        await perform {
            try await repository.save(completion)
            completions.removeAll { $0.id == completion.id }
            completions.append(completion)
        }
        let after = streak(for: habit)
        if completion.isDone, let reached = StreakCalculator.milestone(from: before.ifOpen, to: after.current) {
            milestone = (habit.id, reached)
        } else if milestone?.habitID == habit.id {
            milestone = nil
        }
    }

    public func addHabit(name: String, schedule: HabitSchedule) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let habit = Habit(name: String(trimmed.prefix(40)), schedule: schedule, sortOrder: (habits.map(\.sortOrder).max() ?? -1) + 1,
                          createdAt: now(), updatedAt: now())
        await perform {
            try await repository.save(habit)
            habits.append(habit)
        }
    }

    public func updateHabit(_ habit: Habit) async {
        var updated = habit
        updated.name = String(habit.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !updated.name.isEmpty else { return }
        updated.updatedAt = now()
        await perform {
            try await repository.save(updated)
            if let index = habits.firstIndex(where: { $0.id == habit.id }) { habits[index] = updated }
        }
    }

    public func deleteHabit(_ habit: Habit) async {
        await perform {
            try await repository.deleteHabit(id: habit.id)
            habits.removeAll { $0.id == habit.id }
            completions.removeAll { $0.habitID == habit.id }
        }
    }

    public func moveHabit(_ habit: Habit, by offset: Int) async {
        guard let index = habits.firstIndex(of: habit) else { return }
        let target = min(max(index + offset, 0), habits.count - 1)
        guard target != index else { return }
        var reordered = habits
        reordered.move(fromOffsets: IndexSet(integer: index), toOffset: target > index ? target + 1 : target)
        await perform {
            for (order, var item) in reordered.enumerated() where item.sortOrder != order {
                item.sortOrder = order
                item.updatedAt = now()
                try await repository.save(item)
                reordered[order] = item
            }
            habits = reordered
        }
    }

    // MARK: Mood

    public var todayMood: MoodLog? { moods.first { $0.day == today } }
    public var trend14: MoodTrend { MoodTrends.trend(moods, days: 14, today: today) }
    public var trend7: MoodTrend { MoodTrends.trend(moods, days: 7, today: today) }
    public var trend30: MoodTrend { MoodTrends.trend(moods, days: 30, today: today) }
    public var history14: [Int] { MoodTrends.history(moods, days: 14, today: today) }
    /// The last 14 days oldest first, `nil` where there's no check-in (for the strip).
    public var daily14: [Int?] { MoodTrends.daily(moods, days: 14, today: today) }

    public func logMood(_ mood: Mood) async {
        let log = MoodLog(day: today, mood: mood, note: todayMood?.note, updatedAt: now())
        await saveMood(log)
    }

    public func setNote(_ note: String) async {
        guard var log = todayMood else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        log.note = trimmed.isEmpty ? nil : String(trimmed.prefix(500))
        log.updatedAt = now()
        await saveMood(log)
    }

    private func saveMood(_ log: MoodLog) async {
        await perform {
            try await repository.save(log)
            moods.removeAll { $0.day == log.day }
            moods.append(log)
        }
    }

    // MARK: Goals

    public func addGoal(title: String, target: Double, unit: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, target > 0 else { return }
        let goal = Goal(title: String(trimmed.prefix(40)), target: target, unit: String(unit.prefix(12)), createdAt: now(), updatedAt: now())
        await perform {
            try await repository.save(goal)
            goals.append(goal)
        }
    }

    public func logProgress(_ amount: Double, to goal: Goal) async {
        guard amount != 0, var updated = goals.first(where: { $0.id == goal.id }) else { return }
        updated.progress.append(GoalProgress(amount: amount, date: now()))
        updated.updatedAt = now()
        await perform {
            try await repository.save(updated)
            if let index = goals.firstIndex(where: { $0.id == goal.id }) { goals[index] = updated }
        }
    }

    public func deleteGoal(_ goal: Goal) async {
        await perform {
            try await repository.deleteGoal(id: goal.id)
            goals.removeAll { $0.id == goal.id }
        }
    }

    // MARK: Quotes

    public var todaysQuote: Quote { DailyPicker.quote(for: today, category: settings.quoteCategory) }
    public var todaysAffirmation: Affirmation { DailyPicker.affirmation(for: today, category: settings.quoteCategory) }

    // MARK: Settings

    public func updateSettings(_ change: (inout WellnessSettings) -> Void) async {
        var next = settings
        change(&next)
        guard next != settings else { return }
        let reminderChanged = next.moodReminderEnabled != settings.moodReminderEnabled || next.moodReminderHour != settings.moodReminderHour
        do {
            try settingsFile.write(next)
            settings = next
            today = clock.day(for: now())
        } catch {
            errorMessage = String(localized: "Couldn't save your settings.")
            return
        }
        if reminderChanged, next.moodReminderEnabled, await !reminders.requestAuthorization() {
            var off = settings
            off.moodReminderEnabled = false
            try? settingsFile.write(off)
            settings = off
            errorMessage = String(localized: "Turn on notifications for Widgetdeck in Settings to get the reminder.")
        }
        await publish(flush: true)
    }

    // MARK: Publishing

    private func perform(_ body: () async throws -> Void) async {
        do {
            try await body()
            errorMessage = nil
        } catch {
            Self.logger.error("Wellness save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "Couldn't save that change. Please try again.")
        }
        await publish(flush: true)
    }

    /// Writes the widget snapshots and reschedules the mood reminder.
    /// - Parameter flush: reload widgets now (user actions in the foreground don't use the budget).
    public func publish(flush: Bool) async {
        let date = now()
        let habitsSnapshot = WellnessSnapshotBuilder.habits(habits, completions: completions, clock: clock, now: date, firstWeekday: firstWeekday)
        let moodSnapshot = WellnessSnapshotBuilder.mood(moods, clock: clock, now: date)
        do {
            _ = try await reloadCoordinator.publish(habitsSnapshot)
            _ = try await reloadCoordinator.publish(moodSnapshot)
            _ = try await reloadCoordinator.publish(WellnessFlowSnapshot(habits: habitsSnapshot, mood: moodSnapshot, day: today, now: date))
        } catch {
            Self.logger.error("Wellness snapshot publish failed: \(error.localizedDescription, privacy: .public)")
        }
        if flush { await reloadCoordinator.flushNow() }
        await reminders.reschedule(enabled: settings.moodReminderEnabled, hour: settings.moodReminderHour,
                                   loggedDays: Set(moods.map(\.day)), clock: clock, now: date)
    }

    /// Re-evaluates "today" (call when the scene becomes active; the day may have rolled over).
    public func refreshDay() async {
        let current = clock.day(for: now())
        if current != today || !inbox.peek().isEmpty { await load() }
    }
}

/// Background refresh entry point (BGAppRefreshTask): fold in widget taps, roll the day over and
/// republish snapshots. No network.
public enum WellnessBackgroundRefresh {
    @MainActor
    public static func run(repository: any WellnessRepository) async {
        await WellnessStore(repository: repository).load()
    }
}
