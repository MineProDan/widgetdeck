import CoreKit
import SwiftUI
import WellnessFeatureWidgetKit
import WidgetKit

/// Wellness section widgets (W-01…W-04). Views, snapshot types and timeline providers live in the
/// `WellnessFeatureWidgetKit` package product; the App Intents live in `Intents/WellnessIntents.swift`.
struct WellnessWidgets: WidgetBundle {
    var body: some Widget {
        HabitsWidget()
        MoodWidget()
        StreakWidget()
        DailyQuoteWidget()
        AffirmationWidget()
        BreatheWidget()
        BreathingLiveActivity()
    }
}

/// Interactive habit ticks (the mockup's Sage Noon chip).
struct HabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.habits.kindIdentifier, provider: HabitsProvider()) { entry in
            HabitsWidgetView(entry: entry) { ToggleHabitIntent(habitID: $0) }
        }
        .configurationDisplayName("Habits")
        .description("Tick off today's habits right from your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// One-tap mood check-in (the mockup's Plum Dusk chip).
struct MoodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.mood.kindIdentifier, provider: MoodProvider()) { entry in
            MoodWidgetView(entry: entry) { LogMoodIntent(mood: $0) }
        }
        .configurationDisplayName("Mood")
        .description("Log how today went with one tap.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

/// Lock Screen streak ("23" under the leaf, or "Read 20 min · 23-day streak").
struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.streak.kindIdentifier, provider: HabitsProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("Your longest current habit streak.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

/// A public-domain quote each day, optionally from one category.
struct DailyQuoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.quote.kindIdentifier, intent: QuoteWidgetConfigurationIntent.self,
                               provider: QuoteProvider()) { entry in
            QuoteWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Quote")
        .description("A public-domain quote each day.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct QuoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DailyContentEntry { DailyContentTimeline.sample }

    func snapshot(for configuration: QuoteWidgetConfigurationIntent, in context: Context) async -> DailyContentEntry {
        context.isPreview ? DailyContentTimeline.sample
            : DailyContentTimeline.entries(now: .now, category: configuration.category.category, days: 1)[0]
    }

    func timeline(for configuration: QuoteWidgetConfigurationIntent, in context: Context) async -> Timeline<DailyContentEntry> {
        Timeline(entries: DailyContentTimeline.entries(now: .now, category: configuration.category.category), policy: .atEnd)
    }
}

/// A short in-house affirmation each day.
struct AffirmationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.affirmation.kindIdentifier, provider: AffirmationProvider()) { entry in
            AffirmationWidgetView(entry: entry)
        }
        .configurationDisplayName("Affirmation")
        .description("A kind word for today.")
        .supportedFamilies([.systemSmall, .accessoryInline])
        .contentMarginsDisabled()
    }
}

/// Shortcut to a box-breathing session.
struct BreatheWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.breathe.kindIdentifier, provider: BreatheProvider()) { _ in
            BreatheWidgetView()
        }
        .configurationDisplayName("Breathe")
        .description("Start a few minutes of box breathing.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

/// Breathing session Live Activity: Lock Screen chip + Dynamic Island (LockScreen.png).
struct BreathingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BreathingActivityAttributes.self) { context in
            BreathingLockScreenView(context: context)
        } dynamicIsland: { context in
            BreathingIsland.make(context: context)
        }
    }
}
