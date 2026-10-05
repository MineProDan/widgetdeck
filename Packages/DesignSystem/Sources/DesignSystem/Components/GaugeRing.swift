import SwiftUI

/// Circular progress ring (Tech CPU/battery, goals, study timer).
///
/// Animates value changes in-app; with Reduce Motion the change is instant. In widgets it renders
/// statically (widgets don't animate); for live countdowns use `ProgressView(timerInterval:)`.
public struct GaugeRing<Label: View>: View {
    private let value: Double?
    private let lineWidth: CGFloat
    private let role: ForegroundRole
    private let label: Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SemanticColors private var colors

    /// - Parameters:
    ///   - value: fraction 0...1, or `nil` when unavailable (renders an empty track and "—").
    ///   - role: color role of the progress arc.
    public init(value: Double?, lineWidth: CGFloat = ComponentTokens.Gauge.trackWidth, role: ForegroundRole = .accent,
                @ViewBuilder label: () -> Label) {
        self.value = value.map { min(max($0, 0), 1) }
        self.lineWidth = lineWidth
        self.role = role
        self.label = label()
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(colors.textSecondary.color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value ?? 0)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .dsForeground(role)
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .snappy, value: value)
            label
                .padding(lineWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(value.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "Unavailable")
    }
}

extension GaugeRing where Label == GaugeRingPercentLabel {
    /// Ring with a centered percentage ("—" when unavailable).
    public init(value: Double?, lineWidth: CGFloat = ComponentTokens.Gauge.trackWidth, role: ForegroundRole = .accent) {
        self.init(value: value, lineWidth: lineWidth, role: role) { GaugeRingPercentLabel(value: value) }
    }
}

/// Default centered label for `GaugeRing`.
public struct GaugeRingPercentLabel: View {
    let value: Double?

    public var body: some View {
        Text(value.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
            .font(.title2.weight(.semibold))
            .monospacedDigit()
            .contentTransition(.numericText())
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .dsForeground(.primary)
    }
}

#Preview {
    HStack(spacing: 24) {
        GaugeRing(value: 0.72).frame(width: 100, height: 100)
        GaugeRing(value: nil).frame(width: 100, height: 100)
    }
    .padding()
}
