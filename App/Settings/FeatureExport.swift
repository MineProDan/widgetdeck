import CoreKit
import Foundation
import StudentFeature
import WellnessFeature

/// Adds each section's own data to "Export my data" (the CoreKit exporter only knows the profile,
/// themes and widget settings). Calendar events themselves aren't Widgetdeck's data, so they're
/// left out; the courses, corrections and reminders built on them are included.
struct FeatureExportContributor: DataExportContributor {
    let exportKey: String
    let makeJSON: @Sendable () async throws -> Data

    func exportJSON() async throws -> Data { try await makeJSON() }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private struct StudentExport: Encodable {
        var courses: [Course]
        var calendarCorrections: [CourseEventLink]
        var reminderRules: [ReminderRule]
        var assignments: [Assignment]
        var gradeCategories: [GradeCategory]
        var grades: [GradeEntry]
        var settings: StudentSettings
    }

    private struct WellnessExport: Encodable {
        var habits: [Habit]
        var habitCompletions: [HabitCompletion]
        var moods: [MoodLog]
        var goals: [Goal]
    }

    static func student(_ repository: any StudentRepository) -> FeatureExportContributor {
        FeatureExportContributor(exportKey: "student") {
            try encode(StudentExport(courses: try await repository.courses(),
                                     calendarCorrections: try await repository.links(),
                                     reminderRules: try await repository.reminderRules(),
                                     assignments: try await repository.assignments(),
                                     gradeCategories: try await repository.gradeCategories(),
                                     grades: try await repository.gradeEntries(),
                                     settings: await repository.settings()))
        }
    }

    static func wellness(_ repository: any WellnessRepository) -> FeatureExportContributor {
        FeatureExportContributor(exportKey: "wellness") {
            try encode(WellnessExport(habits: try await repository.habits(),
                                      habitCompletions: try await repository.completions(),
                                      moods: try await repository.moods(),
                                      goals: try await repository.goals()))
        }
    }
}
