import DesignSystem
import SwiftUI
import TechFeatureWidgetKit

/// One Tech metric as a Paint Chip (mockup Tech.png): Deep Tide field with a flat fill bar,
/// Label Ivory band with caption / value / trend. `fill == nil` draws an empty track.
public struct MetricCard: View {
    let caption: String
    let value: String
    let fill: Double?
    let fillColor: Color
    let trend: String
    let tone: TechCopy.Tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(caption: String, value: String, fill: Double?, fillColor: Color, trend: String, tone: TechCopy.Tone) {
        self.caption = caption
        self.value = value
        self.fill = fill
        self.fillColor = fillColor
        self.trend = trend
        self.tone = tone
    }

    public var body: some View {
        PaintChip(color: WXSection.tech.color, field: .fixed(78), shadow: .metricCard) {
            FillBar(value: fill, color: fillColor).fieldBottomBar()
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: fill)
        } label: {
            ChipLabelBand(caption: caption, value: value, trend: trend, trendColor: tone.color, valueSize: 24, tabular: true)
        }
        .frame(minHeight: 176)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption), \(value == TechFormat.unavailable ? "not available" : value)")
        .accessibilityValue(trend)
    }
}

/// CPU load card (T-03/T-05). The mockup draws load as a flat Sage fill bar that animates between
/// 5-second samples (DESIGN.md: progress is a flat bar, never a ring, outside Lock Screen gauges).
public struct CPUGaugeView: View {
    let load: Double?
    let minuteAgo: Double?

    public init(load: Double?, minuteAgo: Double?) {
        self.load = load
        self.minuteAgo = minuteAgo
    }

    public var body: some View {
        let (trend, tone) = TechCopy.cpu(current: load, minuteAgo: minuteAgo)
        MetricCard(caption: "CPU load", value: TechFormat.percent(load), fill: load, fillColor: WXColor.sageNoon,
                   trend: trend, tone: tone)
    }
}

/// Storage card (T-02): free space on the whole volume; the bar shows the used share.
public struct StorageView: View {
    let storage: StorageStatus?

    public init(storage: StorageStatus?) {
        self.storage = storage
    }

    public var body: some View {
        let (trend, tone) = TechCopy.storage(storage)
        MetricCard(caption: "Storage free", value: TechFormat.storage(storage?.freeBytes), fill: storage?.usedFraction,
                   fillColor: WXColor.coralHour, trend: trend, tone: tone)
    }
}

/// Thermal state (T-04): the four-step strip with the current step marked.
public struct ThermalIndicator: View {
    let level: ThermalLevel

    public init(level: ThermalLevel) {
        self.level = level
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Thermal state").wxLabel()
                .accessibilityHidden(true)
            ThermalStrip(state: ThermalStrip.Level(ProcessInfo.ThermalState(rawValue: level.rawValue) ?? .nominal))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thermal state, \(level.title)")
    }
}

/// Device chip (T-04): horizontal Paint Chip with the chip glyph, no punch hole.
public struct DeviceChipView: View {
    let device: DeviceInfo

    public init(device: DeviceInfo) {
        self.device = device
    }

    public var body: some View {
        PaintChip(axis: .horizontal, color: WXSection.tech.color, field: .fixed(64), punchHole: nil,
                  cornerRadius: WXRadius.chip, shadow: .contact) {
            ChipGlyph()
        } label: {
            ChipLabelBand(value: device.title, trend: device.detail, valueSize: 17,
                          padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        }
        .frame(minHeight: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.title). \(device.detail)")
    }
}
