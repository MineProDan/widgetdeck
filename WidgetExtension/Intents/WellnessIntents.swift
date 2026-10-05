import AppIntents
import CoreKit
import WellnessFeatureWidgetKit
import WidgetKit

/// Ticks or unticks a habit from the Habits widget (W-02). Runs in the widget extension: it updates
/// the App Group snapshot and records the tap for the app to sync (never CloudKit, Platform Rule 6).
struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick off habit"
    static let description = IntentDescription("Marks a habit done (or not done) for today.")
    static let isDiscoverable = false

    @Parameter(title: "Habit ID") var habitID: String

    init() {}

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { return .result() }
        try WellnessWidgetActions.toggleHabit(id: id)
        // The Streak widget reads the same snapshot.
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.streak.kindIdentifier)
        return .result()
    }
}

/// Logs today's mood from the Mood widget (W-03).
struct LogMoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log mood"
    static let description = IntentDescription("Logs how today went.")
    static let isDiscoverable = false

    @Parameter(title: "Mood", default: 3) var mood: Int

    init() {}

    init(mood: Mood) {
        self.mood = mood.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let value = Mood(rawValue: mood) else { return .result() }
        try WellnessWidgetActions.logMood(value)
        return .result()
    }
}

/// Quote categories for the Daily Quote widget's configuration.
enum QuoteCategoryOption: String, AppEnum {
    case all, calm, focus, courage, growth, kindness, nature

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let caseDisplayRepresentations: [QuoteCategoryOption: DisplayRepresentation] = [
        .all: "All", .calm: "Calm", .focus: "Focus", .courage: "Courage",
        .growth: "Growth", .kindness: "Kindness", .nature: "Nature",
    ]

    var category: ContentCategory? { ContentCategory(rawValue: rawValue) }
}

/// Daily Quote widget configuration: pick a category (W-01 "category filter").
struct QuoteWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Daily Quote"
    static let description = IntentDescription("A public-domain quote each day.")

    @Parameter(title: "Category", default: .all) var category: QuoteCategoryOption
}
