import CoreKit
import DesignSystem
import SwiftUI
import WidgetKit

/// Shell widget that is always available: invites the user to open the app and pick widgets.
/// It needs no data, so its timeline never refreshes.
struct WelcomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.welcome.kindIdentifier, provider: Provider()) { _ in
            WelcomeWidgetView()
                .widgetURL(URL(string: "\(AppIdentifiers.urlScheme)://section/\(AppSection.student.rawValue)"))
        }
        .configurationDisplayName("Widgetdeck")
        .description("A shortcut into Widgetdeck.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }

    struct Entry: TimelineEntry {
        let date: Date
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: .now)], policy: .never))
        }
    }
}

/// A Paint Chip in the app's own colours: a Coral Hour field over a "Widgetdeck · Set up" band.
/// Lock Screen families keep the system look (no custom background there).
struct WelcomeWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Widgetdeck", systemImage: "square.grid.2x2")
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Widgetdeck").font(WXFont.title(15))
                Text("Tap to set up widgets").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        default:
            PaintChipWidget(color: WXSection.student.color, field: .fixed(86)) {
                EmptyView()
            } label: {
                ChipLabelBand(caption: "Widgetdeck", value: "Set up widgets")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Widgetdeck. Tap to set up your widgets.")
        }
    }
}

#Preview(as: .systemSmall) {
    WelcomeWidget()
} timeline: {
    WelcomeWidget.Entry(date: .now)
}
