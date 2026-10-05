import SwiftUI

/// Multi- or single-select chips (onboarding, categories, reminder offsets). 44 pt hit targets.
public struct ChipPicker<Item: Hashable & Identifiable>: View {
    private let items: [Item]
    @Binding private var selection: Set<Item.ID>
    private let allowsMultiple: Bool
    private let title: (Item) -> String
    private let systemImage: ((Item) -> String?)?

    @SemanticColors private var colors

    public init(_ items: [Item], selection: Binding<Set<Item.ID>>, allowsMultiple: Bool = true,
                title: @escaping (Item) -> String, systemImage: ((Item) -> String?)? = nil) {
        self.items = items
        self._selection = selection
        self.allowsMultiple = allowsMultiple
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        FlowLayout(spacing: Space.xs) {
            ForEach(items) { item in
                chip(for: item)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func chip(for item: Item) -> some View {
        let isSelected = selection.contains(item.id)
        return Button {
            toggle(item.id)
        } label: {
            HStack(spacing: Space.xxs) {
                if let icon = systemImage?(item) { Image(systemName: icon) }
                Text(title(item))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, ComponentTokens.Chip.horizontalPadding)
            .frame(minHeight: ComponentTokens.Chip.minHeight)
            .foregroundStyle(isSelected ? colors.onAccent.color : colors.textPrimary.color)
            .background(Capsule().fill(isSelected ? colors.accentPrimary.color : colors.surfaceElevated.color))
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : colors.border.color))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func toggle(_ id: Item.ID) {
        if selection.contains(id) {
            selection.remove(id)
        } else if allowsMultiple {
            selection.insert(id)
        } else {
            selection = [id]
        }
    }
}

/// Wrapping horizontal layout used by `ChipPicker`.
public struct FlowLayout: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = Space.xs) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let proposedWidth = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if proposedWidth > width, !row.indices.isEmpty {
                let nextY = row.y + row.height + spacing
                rows.append(Row(indices: [index], y: nextY, width: size.width, height: size.height))
                continue
            }
            row.indices.append(index)
            row.width = proposedWidth
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Toggle tinted with the theme accent; light haptic on change.
public struct ThemedToggle: View {
    private let title: String
    private let subtitle: String?
    @Binding private var isOn: Bool
    @SemanticColors private var colors

    public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsForeground(.primary)
                if let subtitle { Text(subtitle).font(.footnote).dsForeground(.secondary) }
            }
        }
        .tint(colors.accentPrimary.color)
        .sensoryFeedback(.impact(weight: .light), trigger: isOn)
    }
}

/// Slider tinted with the theme accent, with a spoken/visible value.
public struct ThemedSlider: View {
    private let title: String
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double?
    private let format: (Double) -> String
    @SemanticColors private var colors

    public init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil,
                format: @escaping (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack {
                Text(title).dsForeground(.primary)
                Spacer()
                Text(format(value)).monospacedDigit().dsForeground(.secondary)
            }
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
            }
            .tint(colors.accentPrimary.color)
            .accessibilityLabel(title)
            .accessibilityValue(format(value))
        }
        .sensoryFeedback(.selection, trigger: step == nil ? 0 : value)
    }
}

/// Section title with an optional trailing action (e.g. "Add widget").
public struct SectionHeader: View {
    private let title: String
    private let subtitle: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(_ title: String, subtitle: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.bold)).dsForeground(.primary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.subheadline).dsForeground(.secondary) }
            }
            Spacer(minLength: Space.xs)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .dsForeground(.accent)
                    .frame(minHeight: ComponentTokens.Chip.minHeight)
            }
        }
    }
}

#Preview {
    struct Demo: View {
        struct Item: Identifiable, Hashable { let id: String }
        @State var selection: Set<String> = ["15 min"]
        @State var on = true
        @State var blur = 8.0
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader("Reminders", subtitle: "Before each class", actionTitle: "Add widget") {}
                ChipPicker(["15 min", "30 min", "1 hr", "1 day"].map(Item.init), selection: $selection, title: \.id)
                ThemedToggle("Travel alerts", subtitle: "Leave-now nudges", isOn: $on)
                ThemedSlider("Blur", value: $blur, in: 0...20, step: 1)
            }
            .padding()
        }
    }
    return Demo()
}
