import SwiftUI

/// Big number + label + optional delta (Tech stats, GPA, streaks). Shows "—" when unavailable.
public struct StatTile: View {
    public struct Delta: Sendable, Equatable {
        public enum Trend: Sendable { case up, down, flat }
        public var text: String
        public var trend: Trend
        /// Whether "up" is good (battery) or bad (temperature); drives success/error color.
        public var upIsGood: Bool

        public init(_ text: String, trend: Trend, upIsGood: Bool = true) {
            self.text = text
            self.trend = trend
            self.upIsGood = upIsGood
        }
    }

    private let title: String
    private let value: String?
    private let unit: String?
    private let systemImage: String?
    private let delta: Delta?

    /// - Parameter value: formatted value, or `nil` to show "—".
    public init(_ title: String, value: String?, unit: String? = nil, systemImage: String? = nil, delta: Delta? = nil) {
        self.title = title
        self.value = value
        self.unit = unit
        self.systemImage = systemImage
        self.delta = delta
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.xxs) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small) }
                Text(title)
            }
            .font(.subheadline)
            .dsForeground(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                Text(value ?? "—")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .dsForeground(.primary)
                if let unit, value != nil {
                    Text(unit).font(.subheadline).dsForeground(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            if let delta {
                Label(delta.text, systemImage: icon(for: delta.trend))
                    .font(.caption.weight(.medium))
                    .dsForeground(role(for: delta))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let value else { return "Unavailable" }
        return [value, unit, delta?.text].compactMap { $0 }.joined(separator: " ")
    }

    private func icon(for trend: Delta.Trend) -> String {
        switch trend {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "arrow.right"
        }
    }

    private func role(for delta: Delta) -> ForegroundRole {
        switch delta.trend {
        case .flat: .secondary
        case .up: delta.upIsGood ? .success : .error
        case .down: delta.upIsGood ? .error : .success
        }
    }
}

#Preview {
    HStack {
        StatTile("Battery", value: "82", unit: "%", systemImage: "battery.75", delta: .init("+4% / h", trend: .up))
        StatTile("Uptime", value: nil)
    }
    .padding()
}
