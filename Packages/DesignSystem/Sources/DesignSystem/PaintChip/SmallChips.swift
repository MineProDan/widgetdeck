import SwiftUI

/// A class block for week grids (Student): a mini vertical chip with a 20 pt caps band,
/// radius 8, no punch hole (too small), block shadow. Size it with `.frame` from the grid.
public struct ClassBlock: View {
    private let code: String
    private let color: Color

    public init(code: String, color: Color) {
        self.code = code
        self.color = color
    }

    public var body: some View {
        VStack(spacing: 0) {
            color.frame(maxHeight: .infinity)
            Text(code)
                .wxLabel(9, color: WXColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .background(WXColor.labelIvory)
        }
        .wxRounded(WXRadius.swatch)
        .wxShadow(.block, cornerRadius: WXRadius.swatch)
        .accessibilityElement()
        .accessibilityLabel(code)
    }
}

/// A list row chip (Student "Due soon"): a colour block with a small punch hole, a title and a
/// caps meta line, and an optional trailing control (e.g. `CheckRing`).
public struct ListRowChip<Trailing: View>: View {
    private let color: Color
    private let title: String
    private let meta: String
    private let metaColor: Color
    private let trailing: Trailing

    public init(color: Color, title: String, meta: String, metaColor: Color = WXColor.inkSecondary,
                @ViewBuilder trailing: () -> Trailing) {
        self.color = color
        self.title = title
        self.meta = meta
        self.metaColor = metaColor
        self.trailing = trailing()
    }

    public var body: some View {
        PaintChip(axis: .horizontal, color: color, field: .fixed(52), punchHole: .small, cornerRadius: 12, shadow: .hairline) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).wxGrotesk(16)
                    Text(meta).wxLabel(color: metaColor)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                trailing
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
        }
        .frame(minHeight: 56)
    }
}

/// The unchecked "mark done" ring used on list rows: 22 pt, 2 pt #9A9CA8, in a 44 pt target.
public struct CheckRing: View {
    private let isOn: Bool

    public init(isOn: Bool = false) {
        self.isOn = isOn
    }

    public var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? WXColor.mossPositive : WXColor.checkRing, lineWidth: 2)
            if isOn {
                CheckGlyph()
                    .stroke(WXColor.mossPositive, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(4)
            }
        }
        .frame(width: 22, height: 22)
        .frame(width: 44, height: 44)
    }
}

/// A palette swatch row (ThemeSync): 40 × 36 swatch (radius 8, hairline inset), caps role and
/// a 15 pt name.
public struct SwatchRow: View {
    private let color: Color
    private let role: String
    private let name: String

    public init(color: Color, role: String, name: String) {
        self.color = color
        self.role = role
        self.name = name
    }

    public var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: WXRadius.swatch, style: .continuous)
                .fill(color)
                .overlay {
                    RoundedRectangle(cornerRadius: WXRadius.swatch, style: .continuous)
                        .strokeBorder(WXColor.ink.opacity(0.08), lineWidth: 1)
                }
                .frame(width: 40, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(role).wxLabel(10)
                Text(name).wxGrotesk(15)
            }
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }
}

/// Ink slider (ThemeSync "Drag to compare"): 8 pt capsule track, Ink fill, 15 pt Ink thumb.
public struct WXSlider: View {
    @Binding private var value: Double
    private let label: String

    public init(value: Binding<Double>, label: String) {
        _value = value
        self.label = label
    }

    public var body: some View {
        GeometryReader { proxy in
            let thumb: CGFloat = 15
            let width = proxy.size.width
            let x = CGFloat(min(max(value, 0), 1)) * (width - thumb)
            ZStack(alignment: .leading) {
                Capsule().fill(WXColor.labelIvory)
                    .overlay(Capsule().strokeBorder(WXColor.checkRing, lineWidth: 1))
                    .frame(height: 8)
                Capsule().fill(WXColor.ink)
                    .frame(width: x + thumb / 2, height: 8)
                Circle().fill(WXColor.ink)
                    .frame(width: thumb, height: thumb)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = Double(min(max((drag.location.x - thumb / 2) / (width - thumb), 0), 1))
            })
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
        }
    }
}
