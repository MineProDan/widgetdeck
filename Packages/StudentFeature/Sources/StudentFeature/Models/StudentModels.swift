import CoreData
import CoreKit
import Foundation
import StudentFeatureWidgetKit

/// How an event is treated in the Student section.
public enum EventCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case classSession = "class"
    case deadline
    /// Not school-related; hidden from the schedule.
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .classSession: String(localized: "Class")
        case .deadline: String(localized: "Deadline")
        case .other: String(localized: "Not school")
        }
    }
}

/// A read-only copy of one calendar event occurrence. Lives in memory only: events are never
/// mirrored to CloudKit or written to our stores (S-02). We keep identifiers + annotations.
public struct CalendarEvent: Hashable, Sendable, Identifiable {
    /// Occurrence identifier (`eventIdentifier` + start), unique per occurrence.
    public var id: String
    /// Identifies the whole recurring series across occurrences (and, via the external
    /// identifier, across devices). User corrections are keyed by it.
    public var seriesKey: String
    public var calendarID: String
    public var title: String
    public var location: String?
    public var notes: String?
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// The event repeats weekly (EKRecurrenceRule frequency .weekly, any interval).
    public var isWeeklyRecurring: Bool

    public init(id: String, seriesKey: String, calendarID: String, title: String, location: String? = nil, notes: String? = nil,
                start: Date, end: Date, isAllDay: Bool = false, isWeeklyRecurring: Bool = false) {
        self.id = id
        self.seriesKey = seriesKey
        self.calendarID = calendarID
        self.title = title
        self.location = location
        self.notes = notes
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isWeeklyRecurring = isWeeklyRecurring
    }
}

/// A calendar the user can mark as "school".
public struct CalendarSource: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var sourceTitle: String

    public init(id: String, title: String, sourceTitle: String) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
    }
}

// MARK: - Persisted records

/// A course (synced, CoreKit "Cloud" configuration).
public struct Course: PersistableRecord, Hashable {
    public static var entityName: String { StudentModel.Entity.course }
    public var id: UUID
    /// Normalised course code, e.g. "BIO 201".
    public var code: String
    public var name: String?
    public var paint: CoursePaint
    /// Credit hours for GPA weighting (S-06). `nil` counts as 1.
    public var credits: Double?
    /// "Leave by" time the user set for this course, as minutes before each class starts.
    /// Shown on the Next Class widget. `nil` = not set (nothing shown).
    public var leaveMinutesBefore: Int?
    /// "Leave by" worked out from travel time (MapKit ETA at sync + the leave-by extra minutes).
    /// When on, the course sheet clears `leaveMinutesBefore`; with no ETA the widget shows the room.
    public var leaveAuto: Bool?
    /// What the user calls the place ("ICS 192"). Shown instead of the calendar location in
    /// widgets and rows; the calendar's address still drives travel time.
    public var room: String?
    /// How the user gets to this course. `nil` = the usual way (Leave-by alerts setting).
    public var travelMode: TravelMode?
    /// `false` = no leave-by alerts for this course even when the feature is on. `nil` = follow it.
    public var leaveAlerts: Bool?
    /// The class setup questions were answered (or skipped) for this course. Synced, so a second
    /// device doesn't ask again.
    public var isSetUp: Bool?
    public var updatedAt: Date

    public init(id: UUID = UUID(), code: String, name: String? = nil, paint: CoursePaint, credits: Double? = nil,
                leaveMinutesBefore: Int? = nil, leaveAuto: Bool? = nil, room: String? = nil, travelMode: TravelMode? = nil, updatedAt: Date = .now) {
        self.id = id
        self.code = code
        self.name = name
        self.paint = paint
        self.credits = credits
        self.leaveMinutesBefore = leaveMinutesBefore
        self.leaveAuto = leaveAuto
        self.room = room
        self.travelMode = travelMode
        self.updatedAt = updatedAt
    }
}

/// Our annotation on a calendar series: the user's category correction and course assignment.
/// Stores **only identifiers**, never event titles, times or notes (CoreKit "Local" configuration).
public struct CourseEventLink: PersistableRecord, Hashable {
    public static var entityName: String { StudentModel.Entity.courseEventLink }
    public var id: UUID
    /// `CalendarEvent.seriesKey`: a correction applies to the whole recurring series.
    public var seriesKey: String
    public var courseID: UUID?
    /// The user's tag. Wins over every automatic rule.
    public var userCategory: EventCategory?
    /// Deadline occurrences the user ticked off in "Due soon" (occurrence ids).
    public var completedOccurrences: Set<String>
    /// SHA-256 of calendar + event title (`ScheduleBuilder.titleKey`), never the title itself. Lets a
    /// correction survive when iOS gives the series a new identifier (e.g. "edit all future events").
    public var titleKey: String?
    public var updatedAt: Date

    public init(id: UUID = UUID(), seriesKey: String, courseID: UUID? = nil, userCategory: EventCategory? = nil,
                completedOccurrences: Set<String> = [], titleKey: String? = nil, updatedAt: Date = .now) {
        self.id = id
        self.titleKey = titleKey
        self.seriesKey = seriesKey
        self.courseID = courseID
        self.userCategory = userCategory
        self.completedOccurrences = completedOccurrences
        self.updatedAt = updatedAt
    }
}

/// When to remind before a class.
public enum ReminderOffset: Int, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case oneDay = 1440

    public var id: Int { rawValue }
    public var interval: TimeInterval { TimeInterval(rawValue * 60) }

    public var title: String {
        switch self {
        case .fifteenMinutes: String(localized: "15 min")
        case .thirtyMinutes: String(localized: "30 min")
        case .oneHour: String(localized: "1 hr")
        case .oneDay: String(localized: "1 day")
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Reminder settings. `courseID == nil` is the global rule; a course rule overrides it.
public struct ReminderRule: PersistableRecord, Hashable {
    public static var entityName: String { StudentModel.Entity.reminderRule }
    public var id: UUID
    public var courseID: UUID?
    public var offsets: Set<ReminderOffset>
    public var isEnabled: Bool
    public var updatedAt: Date

    public init(id: UUID = UUID(), courseID: UUID? = nil, offsets: Set<ReminderOffset> = [.fifteenMinutes],
                isEnabled: Bool = false, updatedAt: Date = .now) {
        self.id = id
        self.courseID = courseID
        self.offsets = offsets
        self.isEnabled = isEnabled
        self.updatedAt = updatedAt
    }
}

/// Student entities for `CoreDataStack.load(mode:contributors:)`.
public enum StudentModel: PersistenceModelContributor {
    public enum Entity {
        public static let course = "StudentCourseRecord"
        public static let courseEventLink = "StudentCourseEventLinkRecord"
        public static let reminderRule = "StudentReminderRuleRecord"
        public static let assignment = "StudentAssignmentRecord"
        public static let gradeCategory = "StudentGradeCategoryRecord"
        public static let gradeEntry = "StudentGradeEntryRecord"
    }

    /// Synced entity names, for `DeduplicationService(stack:entityNames:)`.
    public static let syncedEntityNames = [Entity.course, Entity.reminderRule, Entity.assignment, Entity.gradeCategory, Entity.gradeEntry]

    public static func makeEntities() -> [StoreConfiguration: [NSEntityDescription]] {
        [.cloud: [PayloadEntity.make(name: Entity.course), PayloadEntity.make(name: Entity.reminderRule),
                  PayloadEntity.make(name: Entity.assignment),
                  // Grades are personal: both payloads use CloudKit encryption.
                  PayloadEntity.make(name: Entity.gradeCategory, encryptPayload: true),
                  PayloadEntity.make(name: Entity.gradeEntry, encryptPayload: true)],
         .local: [PayloadEntity.make(name: Entity.courseEventLink)]]
    }
}
