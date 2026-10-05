import Charts
import SwiftUI

/// A small line/area chart (mood, habits, battery history). Static and widget-safe.
public struct TrendLine: View {
    public struct Point: Identifiable, Hashable, Sendable {
        public var date: Date
        public var value: Double
        public var id: Date { date }
        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    private let points: [Point]
    private let range: ClosedRange<Double>?
    private let showsArea: Bool
    private let accessibilityTitle: String

    @SemanticColors private var colors
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// - Parameters:
    ///   - range: fixed Y range (e.g. 0...1); `nil` fits the data.
    ///   - accessibilityTitle: spoken summary title, e.g. "Battery, last 24 hours".
    public init(_ points: [Point], range: ClosedRange<Double>? = nil, showsArea: Bool = true, accessibilityTitle: String) {
        self.points = points.sorted { $0.date < $1.date }
        self.range = range
        self.showsArea = showsArea
        self.accessibilityTitle = accessibilityTitle
    }

    public var body: some View {
        if points.count < 2 {
            Text("Not enough data yet")
                .font(.caption)
                .dsForeground(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            chart
                .accessibilityElement()
                .accessibilityLabel(accessibilityTitle)
                .accessibilityValue(summary)
        }
    }

    private var lineColor: Color {
        DSRenderingMode(renderingMode).usesThemeColors ? colors.accentPrimary.color : .primary
    }

    @ViewBuilder
    private var chart: some View {
        let base = Chart(points) { point in
            if showsArea {
                AreaMark(x: .value("Time", point.date), y: .value("Value", point.value))
                    .foregroundStyle(lineColor.opacity(0.18))
                    .interpolationMethod(.monotone)
            }
            LineMark(x: .value("Time", point.date), y: .value("Value", point.value))
                .foregroundStyle(lineColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)

        if let range {
            base.chartYScale(domain: range)
        } else {
            base
        }
    }

    private var summary: String {
        guard let first = points.first?.value, let last = points.last?.value,
              let low = points.map(\.value).min(), let high = points.map(\.value).max() else { return "" }
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
        return "From \(first.formatted(format)) to \(last.formatted(format)); low \(low.formatted(format)), high \(high.formatted(format))"
    }
}

#Preview {
    let now = Date.now
    TrendLine((0..<12).map { .init(date: now.addingTimeInterval(Double($0) * 3600), value: Double.random(in: 0.3...0.9)) },
              range: 0...1, accessibilityTitle: "Battery")
        .frame(height: 80)
        .padding()
}
