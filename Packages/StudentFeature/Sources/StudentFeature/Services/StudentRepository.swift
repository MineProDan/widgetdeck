import CoreKit
import Foundation
import os
import StudentFeatureWidgetKit

/// Section settings that are per device (not synced).
public struct StudentSettings: Codable, Sendable, Equatable {
    /// Calendars the user marked as "school". Empty = not chosen yet.
    public var schoolCalendarIDs: Set<String> = []
    /// The user tapped "Connect later": show the demo schedule, don't re-prompt.
    public var deferredConnect = false
    /// Reminders list imported as assignments (S-05). `nil` = no import.
    public var remindersListID: String?
    /// When to remind before an assignment is due (S-05). `nil` = off.
    public var assignmentReminder: ReminderOffset?
    /// Letter/GPA scale (S-06).
    public var gradeScale: GradeScale = .plusMinus
    /// "Leave by" alerts (S-07).
    public var leaveByEnabled = false
    public var travelMode: TravelMode = .walking
    /// Extra minutes on top of the ETA (finding the room, locking a bike).
    public var leaveBufferMinutes = 5
    /// Last focus preset used (S-08).
    public var focusPreset: FocusPreset = .pomodoro

    public init(schoolCalendarIDs: Set<String> = [], deferredConnect: Bool = false) {
        self.schoolCalendarIDs = schoolCalendarIDs
        self.deferredConnect = deferredConnect
    }

    private enum CodingKeys: String, CodingKey {
        case schoolCalendarIDs, deferredConnect, remindersListID, assignmentReminder, gradeScale
        case leaveByEnabled, travelMode, leaveBufferMinutes, focusPreset
    }

    // Every key is optional so settings files written by older builds keep loading.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schoolCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .schoolCalendarIDs) ?? []
        deferredConnect = try c.decodeIfPresent(Bool.self, forKey: .deferredConnect) ?? false
        remindersListID = try c.decodeIfPresent(String.self, forKey: .remindersListID)
        assignmentReminder = try? c.decodeIfPresent(ReminderOffset.self, forKey: .assignmentReminder)
        gradeScale = (try? c.decodeIfPresent(GradeScale.self, forKey: .gradeScale)) ?? .plusMinus
        leaveByEnabled = try c.decodeIfPresent(Bool.self, forKey: .leaveByEnabled) ?? false
        travelMode = (try? c.decodeIfPresent(TravelMode.self, forKey: .travelMode)) ?? .walking
        leaveBufferMinutes = try c.decodeIfPresent(Int.self, forKey: .leaveBufferMinutes) ?? 5
        focusPreset = (try? c.decodeIfPresent(FocusPreset.self, forKey: .focusPreset)) ?? .pomodoro
    }
}

/// Storage for Student records.
public protocol StudentRepository: Sendable {
    func courses() async throws -> [Course]
    func links() async throws -> [CourseEventLink]
    func reminderRules() async throws -> [ReminderRule]
    func save(_ course: Course) async throws
    func deleteCourse(id: UUID) async throws
    func save(_ link: CourseEventLink) async throws
    func save(_ rule: ReminderRule) async throws
    func deleteRule(id: UUID) async throws
    func assignments() async throws -> [Assignment]
    func save(_ assignment: Assignment) async throws
    func deleteAssignment(id: UUID) async throws
    func gradeCategories() async throws -> [GradeCategory]
    func save(_ category: GradeCategory) async throws
    func deleteGradeCategory(id: UUID) async throws
    func gradeEntries() async throws -> [GradeEntry]
    func save(_ entry: GradeEntry) async throws
    func deleteGradeEntry(id: UUID) async throws
    func settings() async -> StudentSettings
    func save(_ settings: StudentSettings) async
}

/// Core Data implementation (CoreKit `RecordStore`): courses + reminder rules in "Cloud",
/// event links in "Local". Requires the app to load `StudentModel` as a contributor.
public struct CoreDataStudentRepository: StudentRepository {
    private let stack: CoreDataStack
    private let defaults: SettingsFile

    public init(stack: CoreDataStack, appGroup: AppGroupContainer = .shared) {
        self.stack = stack
        self.defaults = SettingsFile(appGroup: appGroup)
    }

    public func courses() async throws -> [Course] { try await RecordStore<Course>(stack: stack).fetchAll() }
    public func links() async throws -> [CourseEventLink] { try await RecordStore<CourseEventLink>(stack: stack).fetchAll() }
    public func reminderRules() async throws -> [ReminderRule] { try await RecordStore<ReminderRule>(stack: stack).fetchAll() }
    public func save(_ course: Course) async throws { try await RecordStore<Course>(stack: stack).upsert(course) }
    public func deleteCourse(id: UUID) async throws { try await RecordStore<Course>(stack: stack).delete(id: id) }
    public func save(_ link: CourseEventLink) async throws { try await RecordStore<CourseEventLink>(stack: stack).upsert(link) }
    public func save(_ rule: ReminderRule) async throws { try await RecordStore<ReminderRule>(stack: stack).upsert(rule) }
    public func deleteRule(id: UUID) async throws { try await RecordStore<ReminderRule>(stack: stack).delete(id: id) }
    public func assignments() async throws -> [Assignment] { try await RecordStore<Assignment>(stack: stack).fetchAll() }
    public func save(_ assignment: Assignment) async throws { try await RecordStore<Assignment>(stack: stack).upsert(assignment) }
    public func deleteAssignment(id: UUID) async throws { try await RecordStore<Assignment>(stack: stack).delete(id: id) }
    public func gradeCategories() async throws -> [GradeCategory] { try await RecordStore<GradeCategory>(stack: stack).fetchAll() }
    public func save(_ category: GradeCategory) async throws { try await RecordStore<GradeCategory>(stack: stack).upsert(category) }
    public func deleteGradeCategory(id: UUID) async throws { try await RecordStore<GradeCategory>(stack: stack).delete(id: id) }
    public func gradeEntries() async throws -> [GradeEntry] { try await RecordStore<GradeEntry>(stack: stack).fetchAll() }
    public func save(_ entry: GradeEntry) async throws { try await RecordStore<GradeEntry>(stack: stack).upsert(entry) }
    public func deleteGradeEntry(id: UUID) async throws { try await RecordStore<GradeEntry>(stack: stack).delete(id: id) }
    public func settings() async -> StudentSettings { defaults.read() }
    public func save(_ settings: StudentSettings) async { defaults.write(settings) }
}

/// JSON-file implementation in the App Group (device-local, not synced). Used until the app
/// wires `StudentModel` into its Core Data stack (see README, "CoreKit requests"), and in tests.
public actor FileStudentRepository: StudentRepository {
    private struct Contents: Codable {
        var courses: [Course] = []
        var links: [CourseEventLink] = []
        var rules: [ReminderRule] = []
        var assignments: [Assignment] = []
        var gradeCategories: [GradeCategory] = []
        var gradeEntries: [GradeEntry] = []

        init() {}

        // Files from builds before S-05/S-06 have no assignment or grade keys.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            courses = try c.decodeIfPresent([Course].self, forKey: .courses) ?? []
            links = try c.decodeIfPresent([CourseEventLink].self, forKey: .links) ?? []
            rules = try c.decodeIfPresent([ReminderRule].self, forKey: .rules) ?? []
            assignments = try c.decodeIfPresent([Assignment].self, forKey: .assignments) ?? []
            gradeCategories = try c.decodeIfPresent([GradeCategory].self, forKey: .gradeCategories) ?? []
            gradeEntries = try c.decodeIfPresent([GradeEntry].self, forKey: .gradeEntries) ?? []
        }
    }

    private let url: URL
    private let settingsFile: SettingsFile
    private var cache: Contents?
    private static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Student")

    public init(appGroup: AppGroupContainer = .shared) {
        url = appGroup.applicationSupportURL.appending(path: "Student/records.json")
        settingsFile = SettingsFile(appGroup: appGroup)
    }

    public func courses() -> [Course] { load().courses }
    public func links() -> [CourseEventLink] { load().links }
    public func reminderRules() -> [ReminderRule] { load().rules }

    public func save(_ course: Course) throws { try mutate { $0.courses.upsert(course) } }
    public func deleteCourse(id: UUID) throws { try mutate { $0.courses.removeAll { $0.id == id } } }
    public func save(_ link: CourseEventLink) throws { try mutate { $0.links.upsert(link) } }
    public func save(_ rule: ReminderRule) throws { try mutate { $0.rules.upsert(rule) } }
    public func deleteRule(id: UUID) throws { try mutate { $0.rules.removeAll { $0.id == id } } }
    public func assignments() -> [Assignment] { load().assignments }
    public func save(_ assignment: Assignment) throws { try mutate { $0.assignments.upsert(assignment) } }
    public func deleteAssignment(id: UUID) throws { try mutate { $0.assignments.removeAll { $0.id == id } } }
    public func gradeCategories() -> [GradeCategory] { load().gradeCategories }
    public func save(_ category: GradeCategory) throws { try mutate { $0.gradeCategories.upsert(category) } }
    public func deleteGradeCategory(id: UUID) throws { try mutate { $0.gradeCategories.removeAll { $0.id == id } } }
    public func gradeEntries() -> [GradeEntry] { load().gradeEntries }
    public func save(_ entry: GradeEntry) throws { try mutate { $0.gradeEntries.upsert(entry) } }
    public func deleteGradeEntry(id: UUID) throws { try mutate { $0.gradeEntries.removeAll { $0.id == id } } }
    public func settings() -> StudentSettings { settingsFile.read() }
    public func save(_ settings: StudentSettings) { settingsFile.write(settings) }

    private func load() -> Contents {
        if let cache { return cache }
        var contents = Contents()
        if let data = try? Data(contentsOf: url) {
            do {
                contents = try JSONDecoder().decode(Contents.self, from: data)
            } catch {
                Self.logger.error("Student records unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
            }
        }
        cache = contents
        return contents
    }

    private func mutate(_ change: (inout Contents) -> Void) throws {
        var contents = load()
        change(&contents)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(contents).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        cache = contents
    }
}

/// `StudentSettings` as a small JSON file in the App Group (erased by "Delete all data").
struct SettingsFile: Sendable {
    let url: URL

    init(appGroup: AppGroupContainer) {
        url = appGroup.applicationSupportURL.appending(path: "Student/settings.json")
    }

    func read() -> StudentSettings {
        guard let data = try? Data(contentsOf: url) else { return StudentSettings() }
        return (try? JSONDecoder().decode(StudentSettings.self, from: data)) ?? StudentSettings()
    }

    func write(_ settings: StudentSettings) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(settings).write(to: url, options: .atomic)
        } catch {
            Logger(subsystem: AppIdentifiers.appBundleID, category: "Student")
                .error("Settings write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension Array where Element: Identifiable {
    mutating func upsert(_ element: Element) {
        if let index = firstIndex(where: { $0.id == element.id }) {
            self[index] = element
        } else {
            append(element)
        }
    }
}
