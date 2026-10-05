import CoreKit
import SwiftUI
import TechFeatureWidgetKit
import WidgetKit

/// Tech section widgets (T-06). Views, entries and timeline providers live in the
/// `TechFeatureWidgetKit` package product; this file only declares the widgets.
/// Every timeline is built from app-written snapshots (Battery also tries a direct UIDevice read).
struct TechWidgets: WidgetBundle {
    var body: some Widget {
        BatteryWidget()
        SystemOverviewWidget()
        StorageWidget()
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.battery.kindIdentifier, provider: BatteryTimelineProvider()) { entry in
            BatteryWidgetView(entry: entry)
                .widgetURL(AppSection.tech.deepLink)
        }
        .configurationDisplayName("Battery")
        .description("Battery level and charging state, with an estimated time to full.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct SystemOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.systemOverview.kindIdentifier, provider: SystemOverviewTimelineProvider()) { entry in
            SystemOverviewWidgetView(entry: entry)
                .widgetURL(AppSection.tech.deepLink)
        }
        .configurationDisplayName("System Overview")
        .description("Battery, storage and thermal state, plus CPU and memory as of your last visit to the Tech tab.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct StorageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.storage.kindIdentifier, provider: StorageTimelineProvider()) { entry in
            StorageWidgetView(entry: entry)
                .widgetURL(AppSection.tech.deepLink)
        }
        .configurationDisplayName("Storage")
        .description("Free space on this iPhone.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}
