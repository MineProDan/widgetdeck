import CoreKit
import DesignSystem
import SwiftUI
import WidgetKit

// Paint Chip widgets for the Tech section. Home-screen families are Deep Tide chips (mockup
// HomeScreen.png, Battery widget); Lock Screen accessories keep system styling.

private let bandPadding = EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13)

// MARK: - Battery

public struct BatteryWidgetView: View {
    let entry: BatteryEntry
    @Environment(\.widgetFamily) private var family

    public init(entry: BatteryEntry) { self.entry = entry }

    public var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.battery.level ?? 0) {
                Image(systemName: entry.battery.state.isPluggedIn ? "bolt.fill" : "battery.100")
            } currentValueLabel: {
                Text(TechFormat.percentNumber(entry.battery.level)).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel(accessibilityText)
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryInline:
            Label {
                Text(inlineText)
            } icon: {
                Image(systemName: entry.battery.state.isPluggedIn ? "bolt.fill" : "battery.100")
            }
            .containerBackground(for: .widget) { Color.clear }
        default:
            PaintChipWidget(color: WXSection.tech.color, field: .fixed(76)) {
                ZStack(alignment: .topTrailing) {
                    if entry.battery.state == .charging {
                        BoltGlyph().padding(.top, 8).padding(.trailing, 12)
                    }
                    FillBar(value: entry.battery.level, color: WXColor.beachSand, height: 14, trackOpacity: 0.18)
                        .fieldBottomBar()
                }
            } label: {
                ChipLabelBand(caption: BatteryCopy.widgetCaption(entry.battery),
                              value: TechFormat.percent(entry.battery.level),
                              trend: BatteryCopy.widgetTrend(entry.battery, isLive: entry.isLive,
                                                             generatedAt: entry.generatedAt, now: entry.date),
                              tabular: true, padding: bandPadding, spacing: 3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    private var inlineText: String {
        let level = TechFormat.percent(entry.battery.level)
        switch entry.battery.state {
        case .charging:
            if let fullAt = entry.battery.estimatedFullAt, fullAt > entry.date {
                return "\(level) · est. \(TechFormat.duration(fullAt.timeIntervalSince(entry.date)))"
            }
            return "\(level) · charging"
        case .full: return "\(level) · full"
        default: return level
        }
    }

    private var accessibilityText: String {
        "Battery \(TechFormat.percent(entry.battery.level)). "
            + BatteryCopy.widgetTrend(entry.battery, isLive: entry.isLive, generatedAt: entry.generatedAt, now: entry.date)
    }
}

// MARK: - Storage

public struct StorageWidgetView: View {
    let entry: StorageEntry
    @Environment(\.widgetFamily) private var family

    public init(entry: StorageEntry) { self.entry = entry }

    public var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Storage free").font(.caption2.weight(.semibold)).textCase(.uppercase)
                Text(TechFormat.storage(entry.storage?.freeBytes)).font(.headline).monospacedDigit()
                Gauge(value: entry.storage?.usedFraction ?? 0) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .widgetAccentable()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .containerBackground(for: .widget) { Color.clear }
        default:
            PaintChipWidget(color: WXSection.tech.color, field: .fixed(76)) {
                FillBar(value: entry.storage?.usedFraction, color: WXColor.coralHour, height: 14, trackOpacity: 0.18)
                    .fieldBottomBar()
            } label: {
                ChipLabelBand(caption: "Storage free", value: TechFormat.storage(entry.storage?.freeBytes),
                              trend: trend, trendColor: trendColor, tabular: true, padding: bandPadding, spacing: 3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    private var trend: String {
        guard let storage = entry.storage else { return "Open Widgetdeck to update" }
        return "Of \(TechFormat.storageTotalNumber(storage.totalBytes)) GB"
    }

    private var trendColor: Color { WXColor.inkSecondary }

    private var accessibilityText: String {
        guard let storage = entry.storage else { return "Storage free not available" }
        return "Storage free \(TechFormat.storage(storage.freeBytes)) of \(TechFormat.storageTotalNumber(storage.totalBytes)) GB"
    }
}

// MARK: - System Overview

public struct SystemOverviewWidgetView: View {
    let entry: SystemOverviewEntry
    @Environment(\.widgetFamily) private var family

    public init(entry: SystemOverviewEntry) { self.entry = entry }

    public var body: some View {
        // Both sizes carry the battery fill bar so the colour field is never an empty slab.
        PaintChipWidget(color: WXSection.tech.color, field: .fixed(family == .systemLarge ? 128 : 58)) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                FillBar(value: snapshot?.battery.level, color: WXColor.beachSand,
                        height: family == .systemLarge ? 14 : 10, trackOpacity: 0.18)
                    .fieldBottomBar()
            }
        } label: {
            band
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var snapshot: SystemOverviewSnapshot? { entry.snapshot }

    private var metrics: [(caption: String, value: String)] {
        [("Battery", TechFormat.percent(snapshot?.battery.level)),
         ("Free", TechFormat.storage(snapshot?.storage?.freeBytes)),
         ("CPU", TechFormat.percent(snapshot?.processor?.cpuLoad)),
         ("Memory", TechFormat.memory(snapshot?.processor?.memoryUsedBytes))]
    }

    private var footer: String {
        guard let snapshot else { return "Open Widgetdeck to update" }
        let time = TechFormat.asOf(snapshot.processor?.sampledAt ?? snapshot.generatedAt)
        return "\(time) · thermal \(snapshot.thermal.title)"
    }

    @ViewBuilder private var band: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
            if family == .systemLarge {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 18) {
                    GridRow { cell(metrics[0], valueSize: 32); cell(metrics[1], valueSize: 32) }
                    GridRow { cell(metrics[2], valueSize: 32); cell(metrics[3], valueSize: 32) }
                }
                if let snapshot {
                    // Same thermal strip as the Tech screen; fills the band instead of blank space.
                    ThermalStrip(state: ThermalStrip.Level(rawValue: snapshot.thermal.rawValue) ?? .nominal)
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(metrics, id: \.caption) { cell($0, valueSize: 20) }
                }
            }
            Text(footer).wxLabel(10).lineLimit(1)
        }
        .padding(bandPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: family == .systemLarge ? .topLeading : .leading)
    }

    private func cell(_ metric: (caption: String, value: String), valueSize: CGFloat = 26) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.caption).wxLabel(10)
            Text(wxValue: metric.value, size: valueSize).wxGrotesk(valueSize, tabular: true).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityText: String {
        metrics.map { "\($0.caption) \($0.value)" }.joined(separator: ", ") + ". " + footer
    }
}
