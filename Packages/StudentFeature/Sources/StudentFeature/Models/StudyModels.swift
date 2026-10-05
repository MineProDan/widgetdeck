import CoreKit
import Foundation

// MARK: - S-05 Assignments

/// Something to hand in (synced, CoreKit "Cloud" configuration).
///
/// Created by hand, or imported read-only from Apple Reminders (`reminderExternalID` set). We never
/// write back to Reminders: ticking an imported assignment off only changes our copy.
public struct Assignment: PersistableRecord, Hashable {
    public static var entityName: String { StudentModel.Entity.assignment }
    public var id: UUID
    public var title: String
    public var courseID: UUID?
    public var due: Date
    public var isDone: Bool
    /// `calendarItemExternalIdentifier` of the source reminder, for imported items.
    public var reminderExternalID: String?
    /// The Reminders list it came from (an import removes items deleted from that list).
    public var reminderListID: String?
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String, courseID: UUID? = nil, due: Date, isDone: Bool = false,
                reminderExternalID: String? = nil, reminderListID: String? = nil, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.courseID = courseID
        self.due = due
        self.isDone = isDone
        self.reminderExternalID = reminderExternalID
        self.reminderListID = reminderListID
        self.updatedAt = updatedAt
    }

    public var isImported: Bool { reminderExternalID != nil }

    /// `DeadlineItem.id` / notification key for this assignment.
    public var occurrenceID: String { "assignment.\(id.uuidString)" }
}

// MARK: - S-06 Grades

/// A weighted part of a course grade ("Exams 50%"). Synced, payload cloud-encrypted.
public struct GradeCategory: PersistableRecord, Hashable {
    public static var entityName: String { StudentModel.Entity.gradeCategory }
    public var id: UUID
    public var courseID: UUID
    public var name: String
    /// Share of the course grade, in percent (0…100).
    public var weight: Double
    public var updatedAt: Date

    public init(id: UUID = UUID(), courseID: UUID, name: String, weight: Double, updatedAt: Date = .now) {
        self.id = id
        self.courseID = courseID
        self.name = name
        self.weight = weight
        self.updatedAt = updatedAt
    }
}

/// One graded item ("Quiz 2: 18 / 20"). Synced, payload cloud-encrypted.
public struct GradeEntry: PersistableRecord, Hashable {
    public static var entityName: String { StudentModel.Entity.gradeEntry }
    public var id: UUID
    public var courseID: UUID
    /// `nil` = uncategorised (see `GradeMath.coursePercent`).
    public var categoryID: UUID?
    public var title: String
    public var score: Double
    public var maxScore: Double
    public var updatedAt: Date

    public init(id: UUID = UUID(), courseID: UUID, categoryID: UUID? = nil, title: String, score: Double, maxScore: Double,
                updatedAt: Date = .now) {
        self.id = id
        self.courseID = courseID
        self.categoryID = categoryID
        self.title = title
        self.score = score
        self.maxScore = maxScore
        self.updatedAt = updatedAt
    }
}

/// How percentages turn into letter grades and grade points.
public enum GradeScale: String, Codable, CaseIterable, Sendable, Identifiable {
    /// A 93 · A− 90 · B+ 87 … D− 60, F below (4.0 max). The common US plus/minus scale.
    case plusMinus
    /// A 90 · B 80 · C 70 · D 60 (4.0 max), no plus/minus.
    case simple
    /// Like `plusMinus`, with A+ (97+) worth 4.3.
    case plusMinus43

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plusMinus: String(localized: "4.0 with + / −")
        case .simple: String(localized: "4.0, letters only")
        case .plusMinus43: String(localized: "4.3 with A+")
        }
    }

    public var maxPoints: Double { self == .plusMinus43 ? 4.3 : 4.0 }

    /// Cut-offs, highest first: (minimum percent, letter, points).
    public var bands: [(min: Double, letter: String, points: Double)] {
        switch self {
        case .simple:
            [(90, "A", 4), (80, "B", 3), (70, "C", 2), (60, "D", 1), (0, "F", 0)]
        case .plusMinus, .plusMinus43:
            (self == .plusMinus43 ? [(97, "A+", 4.3)] : []) + [
                (93, "A", 4), (90, "A−", 3.7), (87, "B+", 3.3), (83, "B", 3), (80, "B−", 2.7), (77, "C+", 2.3),
                (73, "C", 2), (70, "C−", 1.7), (67, "D+", 1.3), (63, "D", 1), (60, "D−", 0.7), (0, "F", 0)]
        }
    }
}

// MARK: - S-07 Leave by

/// How the user gets to class, for the MapKit ETA.
public enum TravelMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case walking, driving, transit

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .walking: String(localized: "Walking")
        case .driving: String(localized: "Driving")
        case .transit: String(localized: "Transit")
        }
    }
}
