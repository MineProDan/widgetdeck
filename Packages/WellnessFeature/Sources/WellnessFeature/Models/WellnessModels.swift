import CoreData
import CoreKit
import Foundation
import WellnessFeatureWidgetKit

// MARK: - Habits (W-02)

/// When a habit is due.
public enum HabitSchedule: Codable, Hashable, Sendable {
    case daily
    /// Due on these weekdays (1 = Sunday … 7 = Saturday).
    case weekdays(Set<Int>)
    /// Any days, `x` times per week; the streak counts weeks.
    case timesPerWeek(Int)

    /// Monday–Friday.
    public static let workweek = HabitSchedule.weekdays([2, 3, 4, 5, 6])

    public func isDue(on day: DayKey) -> Bool {
        switch self {
        case .daily, .timesPerWeek: true
        case let .weekdays(days): days.contains(day.weekday)
        }
    }

    public var streakUnit: StreakUnit {
        if case .timesPerWeek = self { .week } else { .day }
    }

    public var summary: String {
        switch self {
        case .daily: String(localized: "Every day")
        case let .weekdays(days) where days == [2, 3, 4, 5, 6]: String(localized: "Weekdays")
        case let .weekdays(days):
            days.sorted().map { Calendar.current.shortWeekdaySymbols[($0 - 1) % 7] }.joined(separator: " ")
        case let .timesPerWeek(n): String(localized: "\(n)× a week")
        }
    }
}

public struct Habit: PersistableRecord, Hashable {
    public static let entityName = WellnessModel.Entity.habit

    public var id: UUID
    public var name: String
    public var schedule: HabitSchedule
    public var sortOrder: Int
    public var createdAt: Date
    public var isArchived: Bool
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, schedule: HabitSchedule = .daily, sortOrder: Int = 0,
                createdAt: Date = .now, isArchived: Bool = false, updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.schedule = schedule
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.updatedAt = updatedAt
    }
}

/// "Habit X on day D". Idempotent: the id is derived from (habit, day), so the same tick on two
/// devices is one logical record, and unticking writes `isDone = false` instead of deleting, so the
/// newest write wins after a CloudKit merge.
public struct HabitCompletion: PersistableRecord, Hashable {
    public static let entityName = WellnessModel.Entity.habitCompletion

    public var id: UUID
    public var habitID: UUID
    public var day: DayKey
    /// The time zone the tick was made in (for export/debugging; days are already normalised).
    public var timeZoneID: String
    public var isDone: Bool
    public var updatedAt: Date

    public init(habitID: UUID, day: DayKey, isDone: Bool = true, timeZoneID: String = TimeZone.current.identifier, updatedAt: Date = .now) {
        self.id = StableID.completion(habit: habitID, day: day)
        self.habitID = habitID
        self.day = day
        self.timeZoneID = timeZoneID
        self.isDone = isDone
        self.updatedAt = updatedAt
    }
}

// MARK: - Mood (W-03)

/// One mood per wellness day. The whole payload (mood + note) is end-to-end encrypted in CloudKit.
public struct MoodLog: PersistableRecord, Hashable {
    public static let entityName = WellnessModel.Entity.mood

    public var id: UUID
    public var day: DayKey
    public var mood: Mood
    public var note: String?
    public var timeZoneID: String
    public var updatedAt: Date

    public init(day: DayKey, mood: Mood, note: String? = nil, timeZoneID: String = TimeZone.current.identifier, updatedAt: Date = .now) {
        self.id = StableID.mood(day: day)
        self.day = day
        self.mood = mood
        self.note = note
        self.timeZoneID = timeZoneID
        self.updatedAt = updatedAt
    }
}

// MARK: - Goals (W-05)

public struct GoalProgress: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var amount: Double
    public var date: Date

    public init(id: UUID = UUID(), amount: Double, date: Date = .now) {
        self.id = id
        self.amount = amount
        self.date = date
    }
}

public struct Goal: PersistableRecord, Hashable {
    public static let entityName = WellnessModel.Entity.goal

    public var id: UUID
    public var title: String
    public var target: Double
    /// Free text: "km", "pages", "books".
    public var unit: String
    public var createdAt: Date
    public var progress: [GoalProgress]
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String, target: Double, unit: String, createdAt: Date = .now,
                progress: [GoalProgress] = [], updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.target = target
        self.unit = unit
        self.createdAt = createdAt
        self.progress = progress
        self.updatedAt = updatedAt
    }
}

// MARK: - Settings (local, App Group)

public struct WellnessSettings: Codable, Hashable, Sendable {
    /// Hour (0–12) when a new wellness day begins.
    public var dayStartHour: Int = 0
    /// Optional daily mood reminder ("How was today?").
    public var moodReminderEnabled: Bool = false
    public var moodReminderHour: Int = 20
    public var quoteCategory: ContentCategory?
    public var breathingPattern: BreathingPattern = .box
    public var breathingMinutes: Int = 3
    /// Soft chime at each phase change (plays only during a session the user started).
    public var breathingSound: Bool = false

    public init() {}
}

// MARK: - Core Data

/// Wellness entities for CoreKit's shared model (payload-entity pattern). All four sync through the
/// "Cloud" configuration; the mood payload (which holds the note) is cloud-encrypted.
public enum WellnessModel: PersistenceModelContributor {
    public enum Entity {
        public static let habit = "WellnessHabitRecord"
        public static let habitCompletion = "WellnessHabitCompletionRecord"
        public static let mood = "WellnessMoodRecord"
        public static let goal = "WellnessGoalRecord"
    }

    /// Register with `DeduplicationService` so CloudKit merge duplicates collapse to one row.
    public static let syncedEntityNames = [Entity.habit, Entity.habitCompletion, Entity.mood, Entity.goal]

    public static func makeEntities() -> [StoreConfiguration: [NSEntityDescription]] {
        [.cloud: [
            PayloadEntity.make(name: Entity.habit),
            PayloadEntity.make(name: Entity.habitCompletion),
            PayloadEntity.make(name: Entity.mood, encryptPayload: true),
            PayloadEntity.make(name: Entity.goal),
        ]]
    }
}
