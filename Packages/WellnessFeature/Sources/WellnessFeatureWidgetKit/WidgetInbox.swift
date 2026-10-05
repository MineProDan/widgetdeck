import CoreKit
import Foundation
import os

/// A tap made on a widget, waiting for the app to fold it into the synced store.
public enum WellnessWidgetAction: Codable, Hashable, Sendable {
    case setHabit(habitID: UUID, day: DayKey, isDone: Bool, at: Date, timeZoneID: String)
    case logMood(day: DayKey, mood: Mood, at: Date, timeZoneID: String)
}

/// Small App Group file where interactive widgets record their taps (Platform Reality Rule 6: the
/// extension writes one small record locally, never CloudKit). The app drains it on launch,
/// foreground and background refresh. Access is coordinated with `NSFileCoordinator`, since the
/// app and the extension are separate processes.
public struct WellnessWidgetInbox: Sendable {
    /// Oldest actions are dropped beyond this (a year of daily taps for a few habits is far less).
    public static let capacity = 500
    public let url: URL
    private static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Wellness")

    public init(appGroup: AppGroupContainer = .shared) {
        self.url = appGroup.applicationSupportURL.appending(path: "Wellness/widget-inbox.json")
    }

    public func append(_ action: WellnessWidgetAction) throws {
        try coordinate { current in (Array((current + [action]).suffix(Self.capacity)), ()) }
    }

    /// Returns all pending actions and empties the inbox.
    public func drain() throws -> [WellnessWidgetAction] {
        try coordinate { current in ([], current) }
    }

    public func peek() -> [WellnessWidgetAction] { Self.decode(try? Data(contentsOf: url)) }

    private func coordinate<T>(_ body: ([WellnessWidgetAction]) -> ([WellnessWidgetAction], T)) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var result: Result<T, Error> = .failure(CocoaError(.fileWriteUnknown))
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { url in
            let (next, value) = body(Self.decode(try? Data(contentsOf: url)))
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970
                try encoder.encode(next).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                result = .success(value)
            } catch {
                result = .failure(error)
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private static func decode(_ data: Data?) -> [WellnessWidgetAction] {
        guard let data else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do { return try decoder.decode([WellnessWidgetAction].self, from: data) } catch {
            logger.error("Widget inbox unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

/// What the interactive widget intents do. Kept here (not in the intents) so it's unit-tested.
public enum WellnessWidgetActions {
    public enum ActionError: Error, LocalizedError {
        case noHabits
        public var errorDescription: String? { String(localized: "Open Widgetdeck to set up your habits.") }
    }

    /// Ticks or unticks a habit for today: updates the Habits snapshot in place (so the widget
    /// redraws immediately), records the tap in the inbox and refreshes the Flow facts.
    @discardableResult
    public static func toggleHabit(id: UUID, now: Date = .now, store: SnapshotStore = SnapshotStore(),
                                   inbox: WellnessWidgetInbox = WellnessWidgetInbox()) throws -> Bool {
        guard var snapshot = store.read(HabitsSnapshot.self) else { throw ActionError.noHabits }
        let today = snapshot.clock.day(for: now)
        snapshot = snapshot.projected(to: today)
        guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else { throw ActionError.noHabits }
        snapshot.items[index].isDone.toggle()
        snapshot.generatedAt = now
        let isDone = snapshot.items[index].isDone
        try store.write(snapshot)
        try inbox.append(.setHabit(habitID: id, day: today, isDone: isDone, at: now, timeZoneID: TimeZone.current.identifier))
        _ = try? store.write(WellnessFlowSnapshot(habits: snapshot, mood: store.read(MoodSnapshot.self), day: today, now: now))
        return isDone
    }

    /// Logs today's mood (one per day; a second tap replaces it).
    public static func logMood(_ mood: Mood, now: Date = .now, dayStartHour fallbackDayStart: Int = 0,
                               store: SnapshotStore = SnapshotStore(), inbox: WellnessWidgetInbox = WellnessWidgetInbox()) throws {
        var snapshot = store.read(MoodSnapshot.self) ?? MoodSnapshot(generatedAt: now, dayStartHour: fallbackDayStart, recent: [])
        let today = snapshot.clock.day(for: now)
        snapshot.log(mood, on: today)
        snapshot.generatedAt = now
        try store.write(snapshot)
        try inbox.append(.logMood(day: today, mood: mood, at: now, timeZoneID: TimeZone.current.identifier))
        _ = try? store.write(WellnessFlowSnapshot(habits: store.read(HabitsSnapshot.self), mood: snapshot, day: today, now: now))
    }
}
