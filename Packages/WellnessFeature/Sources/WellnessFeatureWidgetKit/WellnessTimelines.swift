import CoreKit
import Foundation
import WidgetKit

// MARK: - Entries

public struct HabitsEntry: TimelineEntry, Sendable {
    public var date: Date
    public var snapshot: HabitsSnapshot?
    /// Gallery / placeholder content. Never compared with the real clock.
    public var isSample: Bool

    public init(date: Date, snapshot: HabitsSnapshot?, isSample: Bool = false) {
        self.date = date
        self.snapshot = snapshot
        self.isSample = isSample
    }
}

public struct MoodWidgetEntry: TimelineEntry, Sendable {
    public var date: Date
    public var today: DayKey
    public var mood: Mood?
    public var hasSnapshot: Bool
    public var isSample: Bool

    /// Evening and not logged yet: ask the Smart Stack to surface the Mood widget.
    public var isEveningPrompt = false

    public init(date: Date, today: DayKey, mood: Mood?, hasSnapshot: Bool, isSample: Bool = false, isEveningPrompt: Bool = false) {
        self.date = date
        self.today = today
        self.mood = mood
        self.hasSnapshot = hasSnapshot
        self.isSample = isSample
        self.isEveningPrompt = isEveningPrompt
    }

    /// Smart Stack hint (iOS decides whether to act on it).
    public var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: isEveningPrompt && mood == nil ? 80 : 1)
    }
}

public struct DailyContentEntry: TimelineEntry, Sendable {
    public var date: Date
    public var quote: Quote
    public var affirmation: Affirmation

    public init(date: Date, quote: Quote, affirmation: Affirmation) {
        self.date = date
        self.quote = quote
        self.affirmation = affirmation
    }
}

// MARK: - Samples (fixed content: nothing here depends on the clock)

public enum WellnessSamples {
    public static let day = DayKey(year: 2026, month: 9, day: 24)

    /// The mockup's Habits widget: Water, Read done; Stretch open.
    public static let habits = HabitsSnapshot(
        generatedAt: Date(timeIntervalSince1970: 0), day: day, dayStartHour: 0, firstWeekday: 1,
        items: [
            HabitWidgetItem(id: StableID.uuid("sample/water"), name: "Water", isDue: true, isDone: true, streakIfDone: 9, streakIfOpen: 8),
            HabitWidgetItem(id: StableID.uuid("sample/read"), name: "Read", isDue: true, isDone: true, streakIfDone: 23, streakIfOpen: 22),
            HabitWidgetItem(id: StableID.uuid("sample/stretch"), name: "Stretch", isDue: true, isDone: false, streakIfDone: 4, streakIfOpen: 3),
        ])

    public static let streakName = "Read 20 min"

    public static let quote = Quote(id: "sample", text: "Look within. Within is the fountain of good, and it will ever bubble up, if thou wilt ever dig.",
                                    author: "Marcus Aurelius", source: "Meditations, Book VII (trans. George Long, 1862)", category: .calm)
    public static let affirmation = Affirmation(id: "sample", text: "Small steps still move me forward.", category: .focus)
}

// MARK: - Providers

/// Habits and Streak widgets. Reads the App Group snapshot only; projects it across the next
/// day boundary so the widget unticks at the user's "day starts at" hour without the app.
public struct HabitsProvider: TimelineProvider {
    private let read: @Sendable () -> HabitsSnapshot?

    public init(read: @escaping @Sendable () -> HabitsSnapshot? = { SnapshotStore().read(HabitsSnapshot.self) }) {
        self.read = read
    }

    public func placeholder(in context: Context) -> HabitsEntry { HabitsEntry(date: .now, snapshot: WellnessSamples.habits, isSample: true) }

    public func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        let snapshot = read()
        if context.isPreview, snapshot == nil {
            completion(placeholder(in: context))
        } else {
            completion(Self.entries(now: .now, snapshot: snapshot).first ?? placeholder(in: context))
        }
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let now = Date.now
        let snapshot = read()
        completion(Timeline(entries: Self.entries(now: now, snapshot: snapshot), policy: .after(Self.reloadDate(now: now, snapshot: snapshot))))
    }

    /// Now, and the next day boundary (everything unticked, streaks rolled).
    public static func entries(now: Date, snapshot: HabitsSnapshot?) -> [HabitsEntry] {
        guard let snapshot else { return [HabitsEntry(date: now, snapshot: nil)] }
        let clock = snapshot.clock
        let today = clock.day(for: now)
        let boundary = clock.nextBoundary(after: now)
        return [
            HabitsEntry(date: now, snapshot: snapshot.projected(to: today)),
            HabitsEntry(date: boundary, snapshot: snapshot.projected(to: today.adding(days: 1))),
        ]
    }

    public static func reloadDate(now: Date, snapshot: HabitsSnapshot?) -> Date {
        guard let snapshot else { return now.addingTimeInterval(6 * 3600) }
        return snapshot.clock.nextBoundary(after: snapshot.clock.nextBoundary(after: now))
    }
}

/// Mood widget: today's logged mood, cleared at the day boundary.
public struct MoodProvider: TimelineProvider {
    private let read: @Sendable () -> MoodSnapshot?

    public init(read: @escaping @Sendable () -> MoodSnapshot? = { SnapshotStore().read(MoodSnapshot.self) }) {
        self.read = read
    }

    public func placeholder(in context: Context) -> MoodWidgetEntry {
        MoodWidgetEntry(date: .now, today: WellnessSamples.day, mood: nil, hasSnapshot: true, isSample: true)
    }

    public func getSnapshot(in context: Context, completion: @escaping (MoodWidgetEntry) -> Void) {
        completion(Self.entries(now: .now, snapshot: read()).first ?? placeholder(in: context))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<MoodWidgetEntry>) -> Void) {
        let now = Date.now
        let entries = Self.entries(now: now, snapshot: read())
        let clock = read()?.clock ?? WellnessDayClock()
        completion(Timeline(entries: entries, policy: .after(clock.nextBoundary(after: clock.nextBoundary(after: now)))))
    }

    public static func entries(now: Date, snapshot: MoodSnapshot?) -> [MoodWidgetEntry] {
        let clock = snapshot?.clock ?? WellnessDayClock()
        let today = clock.day(for: now)
        let boundary = clock.nextBoundary(after: now)
        let mood = snapshot?.mood(on: today)
        let calendar = Calendar.current
        // 20:00 today (matches the optional evening reminder): from then until the day boundary the
        // widget asks to be on top of its stack if no mood is logged.
        let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? boundary
        var entries = [MoodWidgetEntry(date: now, today: today, mood: mood, hasSnapshot: snapshot != nil,
                                       isEveningPrompt: now >= evening && now < boundary)]
        if evening > now && evening < boundary {
            entries.append(MoodWidgetEntry(date: evening, today: today, mood: mood, hasSnapshot: snapshot != nil, isEveningPrompt: true))
        }
        entries.append(MoodWidgetEntry(date: boundary, today: today.adding(days: 1), mood: nil, hasSnapshot: snapshot != nil))
        return entries
    }
}

/// Quote and affirmation timelines: the pick is deterministic per day, so a few days of entries
/// are built ahead from the bundled JSON (no snapshot, no network).
public enum DailyContentTimeline {
    public static func entries(now: Date, category: ContentCategory?, days: Int = 3,
                               clock: WellnessDayClock = WellnessDayClock(
                                   dayStartHour: SnapshotStore().read(HabitsSnapshot.self)?.dayStartHour ?? 0)) -> [DailyContentEntry] {
        var entries: [DailyContentEntry] = []
        var date = now
        for _ in 0..<days {
            let day = clock.day(for: date)
            entries.append(DailyContentEntry(date: date, quote: DailyPicker.quote(for: day, category: category),
                                             affirmation: DailyPicker.affirmation(for: day, category: category)))
            date = clock.nextBoundary(after: date)
        }
        return entries
    }

    public static var sample: DailyContentEntry {
        DailyContentEntry(date: .now, quote: WellnessSamples.quote, affirmation: WellnessSamples.affirmation)
    }
}

/// Affirmation widget provider (static configuration: all categories).
public struct AffirmationProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> DailyContentEntry { DailyContentTimeline.sample }

    public func getSnapshot(in context: Context, completion: @escaping (DailyContentEntry) -> Void) {
        completion(context.isPreview ? DailyContentTimeline.sample : DailyContentTimeline.entries(now: .now, category: nil, days: 1)[0])
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<DailyContentEntry>) -> Void) {
        completion(Timeline(entries: DailyContentTimeline.entries(now: .now, category: nil), policy: .atEnd))
    }
}

/// Breathe shortcut widget: static content.
public struct BreatheEntry: TimelineEntry, Sendable {
    public var date: Date
    public init(date: Date) { self.date = date }
}

public struct BreatheProvider: TimelineProvider {
    public init() {}
    public func placeholder(in context: Context) -> BreatheEntry { BreatheEntry(date: .now) }
    public func getSnapshot(in context: Context, completion: @escaping (BreatheEntry) -> Void) { completion(BreatheEntry(date: .now)) }
    public func getTimeline(in context: Context, completion: @escaping (Timeline<BreatheEntry>) -> Void) {
        completion(Timeline(entries: [BreatheEntry(date: .now)], policy: .never))
    }
}
