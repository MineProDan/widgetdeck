import CoreKit
import Foundation
import Testing
@testable import WellnessFeature
@testable import WellnessFeatureWidgetKit

// MARK: - Helpers

private func day(_ string: String) -> DayKey { DayKey(string)! }

private func date(_ string: String, zone: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.timeZone = TimeZone(identifier: zone)
    return formatter.date(from: string)!
}

private func daily(_ name: String = "Read") -> Habit { Habit(name: name, schedule: .daily, createdAt: Date(timeIntervalSince1970: 0)) }

private struct NoReminders: MoodReminding {
    func requestAuthorization() async -> Bool { true }
    func reschedule(enabled: Bool, hour: Int, loggedDays: Set<DayKey>, clock: WellnessDayClock, now: Date) async {}
}

// MARK: - Days, DST, time zones, day start

@Suite("Wellness days")
struct WellnessDayTests {
    @Test func dayKeyRoundTripsAndSteps() {
        let key = day("2026-12-31")
        #expect(key.adding(days: 1) == day("2027-01-01"))
        #expect(DayKey(ordinal: key.ordinal) == key)
        #expect(day("2028-02-28").adding(days: 1) == day("2028-02-29"))
        #expect(day("2026-09-27").weekday == 1) // Sunday
        #expect(day("2026-09-30").startOfWeek(firstWeekday: 2) == day("2026-09-28"))
    }

    @Test func midnightBelongsToTheNewDay() {
        let clock = WellnessDayClock(dayStartHour: 0, timeZone: TimeZone(identifier: "Europe/Berlin")!)
        #expect(clock.day(for: date("2026-09-29 23:59", zone: "Europe/Berlin")) == day("2026-09-29"))
        #expect(clock.day(for: date("2026-09-30 00:00", zone: "Europe/Berlin")) == day("2026-09-30"))
    }

    @Test func customDayStartKeepsLateNightsOnThePreviousDay() {
        let zone = "America/New_York"
        let clock = WellnessDayClock(dayStartHour: 4, timeZone: TimeZone(identifier: zone)!)
        #expect(clock.day(for: date("2026-09-30 02:30", zone: zone)) == day("2026-09-29"))
        #expect(clock.day(for: date("2026-09-30 04:00", zone: zone)) == day("2026-09-30"))
        #expect(clock.nextBoundary(after: date("2026-09-30 02:30", zone: zone)) == date("2026-09-30 04:00", zone: zone))
    }

    @Test(arguments: [("2026-03-08", 23.0), ("2026-11-01", 25.0), ("2026-09-29", 24.0)])
    func dstDaysAreOneDay(start: String, hours: Double) {
        let zone = "America/New_York"
        let clock = WellnessDayClock(dayStartHour: 0, timeZone: TimeZone(identifier: zone)!)
        let key = day(start)
        let length = clock.start(of: key.adding(days: 1)).timeIntervalSince(clock.start(of: key)) / 3600
        #expect(length == hours)
        #expect(clock.day(for: clock.start(of: key).addingTimeInterval(length * 3600 - 60)) == key)
    }

    @Test func dstDayStartHourStillLandsOnTheWallClock() {
        let zone = "America/New_York"
        let clock = WellnessDayClock(dayStartHour: 4, timeZone: TimeZone(identifier: zone)!)
        // Clocks jump 2 → 3 AM on 8 March; the day still starts at 4:00 local.
        #expect(clock.start(of: day("2026-03-08")) == date("2026-03-08 04:00", zone: zone))
        #expect(clock.day(for: date("2026-03-08 03:30", zone: zone)) == day("2026-03-07"))
        #expect(clock.day(for: date("2026-03-08 04:30", zone: zone)) == day("2026-03-08"))
        #expect(clock.day(for: date("2026-11-01 03:30", zone: zone)) == day("2026-10-31"))
    }

    @Test func timeZoneTravelKeepsTheStreak() {
        // Tick in Berlin in the evening, fly to New York, tick again the next evening there.
        let habit = daily()
        let berlin = WellnessDayClock(timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let newYork = WellnessDayClock(timeZone: TimeZone(identifier: "America/New_York")!)
        let first = berlin.day(for: date("2026-09-28 21:00", zone: "Europe/Berlin"))
        let second = newYork.day(for: date("2026-09-29 21:00", zone: "America/New_York"))
        let today = newYork.day(for: date("2026-09-30 08:00", zone: "America/New_York"))
        let info = StreakCalculator.streak(for: habit, completedDays: [first, second], today: today)
        #expect(info.ifOpen == 2)
        #expect(info.ifDone == 3)
    }

    @Test func stableIDsAreDeterministic() {
        let habit = UUID()
        #expect(StableID.completion(habit: habit, day: day("2026-09-29")) == StableID.completion(habit: habit, day: day("2026-09-29")))
        #expect(StableID.completion(habit: habit, day: day("2026-09-29")) != StableID.completion(habit: habit, day: day("2026-09-30")))
        #expect(StableID.mood(day: day("2026-09-29")) == MoodLog(day: day("2026-09-29"), mood: .good).id)
    }
}

// MARK: - Streaks

@Suite("Streaks")
struct StreakTests {
    @Test func dailyStreakCountsConsecutiveDaysAndTodayIsOpen() {
        let today = day("2026-09-29")
        let done: Set<DayKey> = [today.adding(days: -1), today.adding(days: -2), today.adding(days: -3), today.adding(days: -5)]
        let info = StreakCalculator.streak(for: daily(), completedDays: done, today: today)
        #expect(info.ifOpen == 3)
        #expect(info.ifDone == 4)
        #expect(info.current == 3)
        #expect(!info.isDone)
    }

    @Test func tickingTodayCounts() {
        let today = day("2026-09-29")
        let info = StreakCalculator.streak(for: daily(), completedDays: [today, today.adding(days: -1)], today: today)
        #expect(info.current == 2)
    }

    @Test func missedYesterdayResets() {
        let today = day("2026-09-29")
        let info = StreakCalculator.streak(for: daily(), completedDays: [today.adding(days: -2)], today: today)
        #expect(info.ifOpen == 0)
        #expect(info.ifDone == 1)
    }

    @Test func weekdayScheduleSkipsDaysOff() {
        let habit = Habit(name: "Run", schedule: .workweek)
        let monday = day("2026-09-28")
        // Thu, Fri done; weekend off; Monday is today.
        let info = StreakCalculator.streak(for: habit, completedDays: [day("2026-09-24"), day("2026-09-25")], today: monday)
        #expect(info.ifOpen == 2)
        #expect(info.ifDone == 3)
        // On a Sunday (not due) ticking doesn't add.
        let sunday = StreakCalculator.streak(for: habit, completedDays: [day("2026-09-25")], today: day("2026-09-27"))
        #expect(sunday.ifDone == sunday.ifOpen)
    }

    @Test func timesPerWeekCountsWeeks() {
        let habit = Habit(name: "Gym", schedule: .timesPerWeek(2))
        // Weeks start Monday. Two previous weeks hit 2; this week has 1 so far (Mon), today is Wed.
        let done: Set<DayKey> = [day("2026-09-14"), day("2026-09-16"), day("2026-09-21"), day("2026-09-25"), day("2026-09-28")]
        let info = StreakCalculator.streak(for: habit, completedDays: done, today: day("2026-09-30"), firstWeekday: 2)
        #expect(info.unit == .week)
        #expect(info.weekCountBeforeToday == 1)
        #expect(info.ifOpen == 2)
        #expect(info.ifDone == 3)
    }

    @Test func milestones() {
        #expect(StreakCalculator.milestone(from: 6, to: 7) == 7)
        #expect(StreakCalculator.milestone(from: 29, to: 30) == 30)
        #expect(StreakCalculator.milestone(from: 99, to: 100) == 100)
        #expect(StreakCalculator.milestone(from: 7, to: 8) == nil)
    }

    /// The widget's own day-rollover projection must agree with a fresh app computation.
    @Test(arguments: [HabitSchedule.daily, .workweek, .timesPerWeek(2), .timesPerWeek(1)])
    func widgetProjectionMatchesCalculator(schedule: HabitSchedule) {
        let habit = Habit(name: "H", schedule: schedule, createdAt: Date(timeIntervalSince1970: 0))
        let clock = WellnessDayClock(timeZone: TimeZone(identifier: "UTC")!)
        let start = day("2026-09-01")
        // A pseudo-random but fixed tick pattern over five weeks.
        let pattern = [1, 1, 0, 1, 1, 1, 0, 1, 0, 0, 1, 1, 1, 1, 1, 0, 1, 1, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1]
        for offset in 0..<(pattern.count - 1) {
            let today = start.adding(days: offset)
            let completions = (0...offset).filter { pattern[$0] == 1 }.map { HabitCompletion(habitID: habit.id, day: start.adding(days: $0)) }
            let now = clock.start(of: today).addingTimeInterval(3600)
            let snapshot = WellnessSnapshotBuilder.habits([habit], completions: completions, clock: clock, now: now, firstWeekday: 2)
            let tomorrow = WellnessSnapshotBuilder.habits([habit], completions: completions, clock: clock,
                                                          now: now.addingTimeInterval(86_400), firstWeekday: 2)
            let projected = snapshot.projected(to: today.adding(days: 1))
            #expect(projected.items[0].streakIfOpen == tomorrow.items[0].streakIfOpen, "open, day \(offset)")
            #expect(projected.items[0].streakIfDone == tomorrow.items[0].streakIfDone, "done, day \(offset)")
            #expect(projected.items[0].isDue == tomorrow.items[0].isDue)
        }
    }
}

// MARK: - Dedupe

@Suite("Dedupe")
struct DedupeTests {
    @Test func duplicateCompletionsCollapseNewestWins() {
        let habit = UUID()
        let today = day("2026-09-29")
        let a = HabitCompletion(habitID: habit, day: today, isDone: true, updatedAt: Date(timeIntervalSince1970: 100))
        let b = HabitCompletion(habitID: habit, day: today, isDone: true, updatedAt: Date(timeIntervalSince1970: 50))
        let untick = HabitCompletion(habitID: habit, day: today, isDone: false, updatedAt: Date(timeIntervalSince1970: 200))
        #expect(a.id == b.id)
        #expect(CompletionMerge.resolve([a, b]).count == 1)
        #expect(CompletionMerge.doneDays([a, b], habit: habit) == [today])
        #expect(CompletionMerge.doneDays([a, b, untick], habit: habit).isEmpty)
    }

    @Test func oneMoodPerDay() {
        let today = day("2026-09-29")
        let early = MoodLog(day: today, mood: .bad, updatedAt: Date(timeIntervalSince1970: 1))
        let late = MoodLog(day: today, mood: .great, updatedAt: Date(timeIntervalSince1970: 2))
        #expect(MoodTrends.latestPerDay([early, late]).map(\.mood) == [.great])
    }

    @MainActor
    @Test func widgetTapsMergeIntoTheStoreIdempotently() async throws {
        let group = AppGroupContainer.temporary()
        let snapshots = SnapshotStore(appGroup: group)
        let inbox = WellnessWidgetInbox(appGroup: group)
        let repository = FileWellnessRepository(appGroup: group)
        let clock = WellnessDayClock()
        let now = Date.now
        let habit = Habit(name: "Stretch", createdAt: now.addingTimeInterval(-86_400))
        try await repository.save(habit)
        try snapshots.write(WellnessSnapshotBuilder.habits([habit], completions: [], clock: clock, now: now, firstWeekday: 1))

        // Tick twice on the widget, then once more: done, not done, done.
        #expect(try WellnessWidgetActions.toggleHabit(id: habit.id, now: now, store: snapshots, inbox: inbox))
        #expect(try !WellnessWidgetActions.toggleHabit(id: habit.id, now: now.addingTimeInterval(1), store: snapshots, inbox: inbox))
        #expect(try WellnessWidgetActions.toggleHabit(id: habit.id, now: now.addingTimeInterval(2), store: snapshots, inbox: inbox))
        try WellnessWidgetActions.logMood(.good, now: now, store: snapshots, inbox: inbox)
        #expect(snapshots.read(HabitsSnapshot.self)?.items.first?.isDone == true)
        #expect(snapshots.read(WellnessFlowSnapshot.self)?.moodLoggedToday == true)
        #expect(inbox.peek().count == 4)

        let coordinator = WidgetReloadCoordinator(store: snapshots, reloader: { _ in })
        let store = WellnessStore(repository: repository, settingsFile: WellnessSettingsFile(appGroup: group), inbox: inbox,
                                  reloadCoordinator: coordinator, reminders: NoReminders(), now: { now.addingTimeInterval(5) })
        await store.load()
        #expect(store.isDone(habit))
        #expect(store.todayMood?.mood == .good)
        #expect(await repository.completions().count == 1)
        #expect(inbox.peek().isEmpty)

        // Replaying an older tap never overrides a newer in-app change.
        await store.toggle(habit) // untick in the app at now + 5
        try inbox.append(.setHabit(habitID: habit.id, day: clock.day(for: now), isDone: true, at: now, timeZoneID: "UTC"))
        await store.load()
        #expect(!store.isDone(habit))
    }
}

// MARK: - Quotes and affirmations

@Suite("Daily content")
struct ContentTests {
    @Test func bundledContentMeetsTheBrief() {
        let quotes = WellnessContentLibrary.quotes
        let affirmations = WellnessContentLibrary.affirmations
        #expect(quotes.count >= 100)
        #expect(affirmations.count >= 50)
        #expect(Set(quotes.map(\.id)).count == quotes.count)
        #expect(Set(quotes.map(\.text)).count == quotes.count)
        #expect(quotes.allSatisfy { !$0.author.isEmpty && !$0.source.isEmpty && !$0.text.isEmpty })
        #expect(Set(affirmations.map(\.id)).count == affirmations.count)
        for category in ContentCategory.allCases {
            #expect(quotes.contains { $0.category == category })
        }
    }

    @Test func rotationIsDeterministic() {
        let key = day("2026-09-29")
        #expect(DailyPicker.quote(for: key) == DailyPicker.quote(for: key))
        #expect(DailyPicker.quote(for: key, category: .calm).category == .calm)
        #expect(DailyPicker.affirmation(for: key, category: .courage).category == .courage)
        #expect(DailyPicker.permutation(count: 5, seed: 42) == DailyPicker.permutation(count: 5, seed: 42))
    }

    @Test func noRepeatsWithinACycle() {
        let quotes = WellnessContentLibrary.quotes
        let start = DayKey(ordinal: (day("2026-09-29").ordinal / quotes.count) * quotes.count)
        let picked = (0..<quotes.count).map { DailyPicker.quote(for: start.adding(days: $0)).id }
        #expect(Set(picked).count == quotes.count)
    }

    @Test func neighbouringDaysDiffer() {
        let key = day("2026-09-29")
        #expect(DailyPicker.quote(for: key).id != DailyPicker.quote(for: key.adding(days: 1)).id)
    }
}

// MARK: - Mood, goals, breathing, reminders

@Suite("Mood, goals, breathing")
struct MiscTests {
    @Test func moodTrendSummary() {
        let today = day("2026-09-29")
        let logs = [MoodLog(day: today, mood: .good), MoodLog(day: today.adding(days: -1), mood: .good),
                    MoodLog(day: today.adding(days: -2), mood: .bad), MoodLog(day: today.adding(days: -20), mood: .awful)]
        let week = MoodTrends.trend(logs, days: 7, today: today)
        #expect(week.loggedDays == 3)
        #expect(week.mostCommon == .good)
        #expect(week.summary == "Mostly good")
        #expect(MoodTrends.trend(logs, days: 30, today: today).loggedDays == 4)
        #expect(MoodTrends.history(logs, days: 14, today: today) == [1, 3, 3])
        #expect(MoodTrends.trend([], days: 7, today: today).summary == "No check-ins yet")
    }

    @Test func goalPercentAndETA() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let goal = Goal(title: "Walk", target: 20, unit: "km", createdAt: now.addingTimeInterval(-10 * 86_400),
                        progress: [GoalProgress(amount: 5, date: now.addingTimeInterval(-10 * 86_400)),
                                   GoalProgress(amount: 5, date: now.addingTimeInterval(-86_400))])
        #expect(GoalMath.total(goal) == 10)
        #expect(GoalMath.fraction(goal) == 0.5)
        // 10 km over 10 days = 1 km/day → 10 more days.
        let eta = GoalMath.eta(goal, now: now)
        #expect(abs((eta?.timeIntervalSince(now) ?? 0) - 10 * 86_400) < 1)
        var done = goal
        done.progress.append(GoalProgress(amount: 15, date: now))
        #expect(GoalMath.fraction(done) == 1)
        #expect(GoalMath.eta(done, now: now) == nil)
        #expect(GoalMath.eta(Goal(title: "x", target: 5, unit: ""), now: now) == nil)
    }

    @Test func breathingPlansAreWholeCycles() {
        let start = Date(timeIntervalSince1970: 0)
        let box = BreathingPlan(pattern: .box, minutes: 3, start: start)
        #expect(box.cycles == 11) // 180 / 16 = 11.25 → 11
        #expect(box.end.timeIntervalSince(start) == 176)
        let relax = BreathingPlan(pattern: .fourSevenEight, minutes: 3, start: start)
        #expect(relax.cycles == 9)
        #expect(relax.phase(at: start.addingTimeInterval(5))?.kind == .holdIn)
        #expect(relax.phase(at: start.addingTimeInterval(12))?.kind == .exhale)
        #expect(relax.phase(at: start.addingTimeInterval(19))?.kind == .inhale)
        #expect(relax.phase(at: relax.end) == nil)
        #expect(BreathingPlan(pattern: .box, minutes: 10, start: start).cycles == 38)
    }

    @Test func moodReminderSkipsLoggedDaysAndPastTimes() {
        let zone = "Europe/London"
        let clock = WellnessDayClock(timeZone: TimeZone(identifier: zone)!)
        let now = date("2026-09-29 21:00", zone: zone) // after 8 PM today
        let plan = MoodReminderScheduler.plan(hour: 20, loggedDays: [day("2026-09-30")], clock: clock, now: now)
        #expect(plan.map(\.day) == [day("2026-10-01"), day("2026-10-02"), day("2026-10-03"), day("2026-10-04"), day("2026-10-05")])
        #expect(plan.first?.date == date("2026-10-01 20:00", zone: zone))
    }

    @Test func snapshotsStayUnderTheSizeCap() throws {
        let habits = (0..<40).map { Habit(name: String(repeating: "x", count: 40) + "\($0)") }
        let snapshot = WellnessSnapshotBuilder.habits(habits, completions: [], clock: WellnessDayClock(), now: .now, firstWeekday: 1)
        #expect(try SnapshotStore.encode(snapshot).count < SnapshotStore.maxSize)
    }

    @Test func deepLinksRoundTrip() {
        let id = UUID()
        #expect(WellnessDeepLink.habitID(from: WellnessDeepLink.url(habit: id)) == id)
        #expect(WellnessDeepLink.breathingPattern(from: WellnessDeepLink.url(breathe: .fourSevenEight)) == .fourSevenEight)
        #expect(WellnessDeepLink.opensMood(WellnessDeepLink.url(mood: true)))
        #expect(AppSection(deepLink: WellnessDeepLink.url(mood: true)) == .wellness)
        #expect(WellnessRequest(url: WellnessDeepLink.url(breathe: .box)) == .breathe(.box))
    }

    @Test func coreDataModelFollowsCloudKitRules() throws {
        _ = try PersistenceModel.make(contributors: [WellnessModel.self])
    }
}

@Suite("Mood strip days")
struct MoodDailyTests {
    @Test func oneSlotPerDayWithGaps() {
        let today = DayKey(year: 2026, month: 10, day: 5)
        let logs = [MoodLog(day: today, mood: .good), MoodLog(day: today.adding(days: -2), mood: .bad)]
        let daily = MoodTrends.daily(logs, days: 14, today: today)
        #expect(daily.count == 14)
        #expect(daily.last == Mood.good.rawValue)
        #expect(daily[11] == Mood.bad.rawValue)
        #expect(daily[12] == nil)
    }
}
