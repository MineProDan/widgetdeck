import CoreKit
import Foundation
import os
import WellnessFeatureWidgetKit

/// Storage for the Wellness section.
public protocol WellnessRepository: Sendable {
    func habits() async throws -> [Habit]
    func completions() async throws -> [HabitCompletion]
    func moods() async throws -> [MoodLog]
    func goals() async throws -> [Goal]
    func save(_ habit: Habit) async throws
    func deleteHabit(id: UUID) async throws
    func save(_ completion: HabitCompletion) async throws
    func save(_ mood: MoodLog) async throws
    func save(_ goal: Goal) async throws
    func deleteGoal(id: UUID) async throws
}

/// Synced storage: CoreKit's Core Data stack (CloudKit private DB). Requires the app to load
/// `WellnessModel` as a persistence contributor.
public struct CoreDataWellnessRepository: WellnessRepository {
    private let stack: CoreDataStack

    public init(stack: CoreDataStack) {
        self.stack = stack
    }

    public func habits() async throws -> [Habit] { try await RecordStore<Habit>(stack: stack).fetchAll() }
    public func completions() async throws -> [HabitCompletion] { try await RecordStore<HabitCompletion>(stack: stack).fetchAll() }
    public func moods() async throws -> [MoodLog] { try await RecordStore<MoodLog>(stack: stack).fetchAll() }
    public func goals() async throws -> [Goal] { try await RecordStore<Goal>(stack: stack).fetchAll() }
    public func save(_ habit: Habit) async throws { try await RecordStore<Habit>(stack: stack).upsert(habit) }
    public func save(_ completion: HabitCompletion) async throws { try await RecordStore<HabitCompletion>(stack: stack).upsert(completion) }
    public func save(_ mood: MoodLog) async throws { try await RecordStore<MoodLog>(stack: stack).upsert(mood) }
    public func save(_ goal: Goal) async throws { try await RecordStore<Goal>(stack: stack).upsert(goal) }
    public func deleteGoal(id: UUID) async throws { try await RecordStore<Goal>(stack: stack).delete(id: id) }

    public func deleteHabit(id: UUID) async throws {
        try await RecordStore<Habit>(stack: stack).delete(id: id)
        let store = RecordStore<HabitCompletion>(stack: stack)
        for completion in try await store.fetchAll() where completion.habitID == id {
            try await store.delete(id: completion.id)
        }
    }
}

/// Local JSON storage in the App Group (not synced). Used until the app wires the Core Data
/// repository, when Core Data fails to load, and in tests.
public actor FileWellnessRepository: WellnessRepository {
    private struct Contents: Codable {
        var habits: [Habit] = []
        var completions: [HabitCompletion] = []
        var moods: [MoodLog] = []
        var goals: [Goal] = []
    }

    private let url: URL
    private var cache: Contents?
    private static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Wellness")

    public init(appGroup: AppGroupContainer = .shared) {
        self.url = appGroup.applicationSupportURL.appending(path: "Wellness/wellness.json")
    }

    private func load() -> Contents {
        if let cache { return cache }
        var contents = Contents()
        if let data = try? Data(contentsOf: url) {
            do { contents = try JSONDecoder().decode(Contents.self, from: data) } catch {
                Self.logger.error("Wellness store unreadable: \(error.localizedDescription, privacy: .public)")
            }
        }
        cache = contents
        return contents
    }

    private func mutate(_ body: (inout Contents) -> Void) throws {
        var contents = load()
        body(&contents)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(contents).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        cache = contents
    }

    public func habits() -> [Habit] { load().habits }
    public func completions() -> [HabitCompletion] { load().completions }
    public func moods() -> [MoodLog] { load().moods }
    public func goals() -> [Goal] { load().goals }

    public func save(_ habit: Habit) throws { try mutate { upsert(habit, into: &$0.habits) } }
    public func save(_ completion: HabitCompletion) throws { try mutate { upsert(completion, into: &$0.completions) } }
    public func save(_ mood: MoodLog) throws { try mutate { upsert(mood, into: &$0.moods) } }
    public func save(_ goal: Goal) throws { try mutate { upsert(goal, into: &$0.goals) } }
    public func deleteGoal(id: UUID) throws { try mutate { $0.goals.removeAll { $0.id == id } } }

    public func deleteHabit(id: UUID) throws {
        try mutate {
            $0.habits.removeAll { $0.id == id }
            $0.completions.removeAll { $0.habitID == id }
        }
    }

    private func upsert<T: Identifiable>(_ value: T, into array: inout [T]) {
        if let index = array.firstIndex(where: { $0.id == value.id }) { array[index] = value } else { array.append(value) }
    }
}

/// Local, per-device settings (App Group JSON).
public struct WellnessSettingsFile: Sendable {
    public let url: URL

    public init(appGroup: AppGroupContainer = .shared) {
        self.url = appGroup.applicationSupportURL.appending(path: "Wellness/settings.json")
    }

    public func read() -> WellnessSettings {
        guard let data = try? Data(contentsOf: url), let settings = try? JSONDecoder().decode(WellnessSettings.self, from: data) else {
            return WellnessSettings()
        }
        return settings
    }

    public func write(_ settings: WellnessSettings) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: url, options: .atomic)
    }
}
