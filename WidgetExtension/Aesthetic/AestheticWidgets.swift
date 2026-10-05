import AestheticFeatureWidgetKit
import CoreKit
import SwiftUI
import WidgetKit

/// Aesthetic section widgets (A-01, A-02, A-06; A-07 borders/effects are applied inside each view). Views, entries and providers live in the
/// `AestheticFeatureWidgetKit` package product. Timelines come only from App Group snapshots, and
/// photos are read pre-downsampled to the widget's exact pixel size (no network, no CloudKit).
struct AestheticWidgets: WidgetBundle {
    var body: some Widget {
        PaletteWidget()
        PhotoWidget()
        MoodBoardWidget()
    }
}

/// The Theme Sync palette taken from the user's wallpaper photo.
struct PaletteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.palette.kindIdentifier, provider: PaletteTimelineProvider()) { entry in
            PaletteWidgetView(entry: entry)
                .widgetURL(AppSection.aesthetic.deepLink)
        }
        .configurationDisplayName("Palette")
        .description("The five colours Theme Sync found in your wallpaper photo.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

/// Photos the user picked in Widgetdeck, one at a time, changing daily or hourly.
struct PhotoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.photo.kindIdentifier, provider: PhotoTimelineProvider()) { entry in
            PhotoWidgetView(entry: entry)
                .widgetURL(AppSection.aesthetic.deepLink)
        }
        .configurationDisplayName("Photo")
        .description("Your photos, one at a time. Pick them in Widgetdeck.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

/// A grid of photos the user picked in Widgetdeck (A-06), optionally shuffled each day.
struct MoodBoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.moodBoard.kindIdentifier, provider: MoodBoardTimelineProvider()) { entry in
            MoodBoardWidgetView(entry: entry)
                .widgetURL(AppSection.aesthetic.deepLink)
        }
        .configurationDisplayName("Mood board")
        .description("Your photos in a grid. Pick them in Widgetdeck.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
