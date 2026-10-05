import SwiftUI

// Things that may sit ON a colour field: geometry and controls only, never words
// (DESIGN.md "The Pure Field Rule").

/// Flat rounded progress bar on a colour field (6–14 pt tall). Not a ring.
public struct FillBar: View {
    private let value: Double?
    private let color: Color
    private let height: CGFloat
    private let trackOpacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - value: 0...1, or `nil` for "unknown" (track only).
    ///   - color: the fill paint (e.g. Beach Sand on Deep Tide for battery).
    ///   - height: 12 (metric cards), 14 (widgets), 6 (hero progress).
    ///   - trackOpacity: Label Ivory track alpha: 0.16 (cards), 0.18 (widgets), 0.32 (hero).
    public init(value: Double?, color: Color, height: CGFloat = 12, trackOpacity: Double = 0.16) {
        self.value = value
        self.color = color
        self.height = height
        self.trackOpacity = trackOpacity
    }

    public var body: some View {
        let clamped = min(max(value ?? 0, 0), 1)
        Capsule(style: .continuous)
            .fill(WXColor.labelIvory.opacity(trackOpacity))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: proxy.size.width * clamped)
                        .widgetAccentable()
                }
            }
            .frame(height: height)
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8), value: clamped)
            .accessibilityElement()
            .accessibilityValue(value.map { "\(Int(($0 * 100).rounded())) percent" } ?? "unknown")
    }
}

extension View {
    /// Pins a fill bar to the bottom of its field with the mockup's insets (12 side, 14 bottom).
    public func fieldBottomBar(horizontal: CGFloat = 12, bottom: CGFloat = 14) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, horizontal)
            .padding(.bottom, bottom)
    }
}

/// `ProcessInfo.ThermalState` as four paint cells (Tech).
public struct ThermalStrip: View {
    public enum Level: Int, CaseIterable, Sendable {
        case nominal, fair, serious, critical

        public var title: String {
            switch self {
            case .nominal: "Nominal"
            case .fair: "Fair"
            case .serious: "Serious"
            case .critical: "Critical"
            }
        }

        public init(_ state: ProcessInfo.ThermalState) {
            switch state {
            case .nominal: self = .nominal
            case .fair: self = .fair
            case .serious: self = .serious
            case .critical: self = .critical
            @unknown default: self = .nominal
            }
        }
    }

    private let state: Level

    public init(state: Level) {
        self.state = state
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Level.allCases, id: \.self) { level in
                let active = level == state
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: WXRadius.swatch, style: .continuous)
                        .fill(WXColor.thermal[level.rawValue])
                        .overlay(alignment: .topLeading) {
                            if active {
                                Circle().fill(WXColor.paperIvory).frame(width: 8, height: 8).padding(8)
                            }
                        }
                        .frame(height: 40)
                        .opacity(active ? 1 : 0.45)
                        .offset(y: active ? -4 : 0)
                    Text(level.title)
                        .wxLabel(10, color: active ? WXColor.ink : WXColor.inkInactive)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thermal state: \(state.title)")
    }
}

/// Ivory ring check on a colour field (habits). 44 pt in the app, 38 pt in widgets.
public struct CheckKey: View {
    private let isOn: Bool
    private let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isOn: Bool, size: CGFloat = 44) {
        self.isOn = isOn
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle().fill(isOn ? WXColor.labelIvory : Color.clear)
            Circle().strokeBorder(WXColor.labelIvory, lineWidth: 2.5)
            CheckGlyph()
                .stroke(isOn ? WXColor.mossPositive : WXColor.labelIvory.opacity(0.55),
                        style: StrokeStyle(lineWidth: 3 * (size >= 44 ? 20 : 18) / 24, lineCap: .round, lineJoin: .round))
                .frame(width: size >= 44 ? 20 : 18, height: size >= 44 ? 20 : 18)
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isOn)
        .accessibilityHidden(true)
    }
}

/// The tick from the mockup (`M5 12.5l4.5 4.5L19 7.5` in a 24 box).
struct CheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: 5 * s, y: 12.5 * s))
        path.addLine(to: CGPoint(x: 9.5 * s, y: 17 * s))
        path.addLine(to: CGPoint(x: 19 * s, y: 7.5 * s))
        return path
    }
}

/// The five-step mood scale, rough → great.
public enum MoodScale {
    public static let words = ["Rough", "Low", "Okay", "Good", "Great"]
}

/// Five tinted mood keys.
///
/// - `.keys`: in-app keys on paper (Wellness): a tint cap over a caps word, ink ring when picked.
/// - `.capsules`: widget keys on a Plum Dusk field (Mood widget): rising capsules, ivory ring.
public struct MoodKeys: View {
    public enum Style: Sendable { case keys, capsules }

    private let selection: Int?
    private let style: Style
    private let onSelect: ((Int) -> Void)?

    public init(selection: Int?, style: Style = .keys, onSelect: ((Int) -> Void)? = nil) {
        self.selection = selection
        self.style = style
        self.onSelect = onSelect
    }

    public var body: some View {
        switch style {
        case .keys:
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    key(index) { keyFace(index) }
                }
            }
        case .capsules:
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<5, id: \.self) { index in
                    key(index) {
                        Capsule(style: .continuous)
                            .fill(WXColor.moodTintsOnPlum[index])
                            .frame(width: 24, height: CGFloat(28 + index * 8))
                            .overlay {
                                if selection == index {
                                    Capsule(style: .continuous).strokeBorder(WXColor.labelIvory, lineWidth: 3).padding(-3)
                                }
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func key(_ index: Int, @ViewBuilder face: () -> some View) -> some View {
        if let onSelect {
            Button { onSelect(index) } label: { face() }
                .buttonStyle(.plain)
                .accessibilityLabel("Log mood: \(MoodScale.words[index])")
                .accessibilityAddTraits(selection == index ? .isSelected : [])
        } else {
            face()
                .accessibilityElement()
                .accessibilityLabel(MoodScale.words[index])
                .accessibilityAddTraits(selection == index ? .isSelected : [])
        }
    }

    private func keyFace(_ index: Int) -> some View {
        VStack(spacing: 0) {
            WXColor.moodTints[index].frame(height: 14)
            Text(MoodScale.words[index])
                .wxLabel(10, color: WXColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 48)
        .background(WXColor.labelIvory)
        .wxRounded(12)
        .overlay {
            if selection == index {
                RoundedRectangle(cornerRadius: 12 + 2, style: .continuous).strokeBorder(WXColor.ink, lineWidth: 2).padding(-2)
            }
        }
        .wxShadow(.contact, cornerRadius: 12)
    }
}

/// Mood history bars on paper (Wellness "Mood · last 14 days"). Values are 0 (rough) … 4 (great).
public struct MoodHistoryBars: View {
    private let values: [Int]

    public init(values: [Int]) {
        self.values = values
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                let v = min(max(value, 0), 4)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(WXColor.moodTints[v])
                    .frame(height: CGFloat(12 + (v + 1) * 10))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 64, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Field glyphs (stroke drawings from the mockup, drawn on fields in Label Ivory)

/// Clock glyph (Flow): circle r22 + hands, in a 54 box.
public struct ClockGlyph: View {
    private let size: CGFloat
    private let lineWidth: CGFloat
    private let color: Color

    public init(size: CGFloat = 54, lineWidth: CGFloat = 2.4, color: Color = WXColor.labelIvory) {
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 54
            var path = Path(ellipseIn: CGRect(x: 5 * s, y: 5 * s, width: 44 * s, height: 44 * s))
            path.move(to: CGPoint(x: 27 * s, y: 14 * s))
            path.addLine(to: CGPoint(x: 27 * s, y: 27 * s))
            path.addLine(to: CGPoint(x: 36 * s, y: 33 * s))
            // The mockup strokes in its own 54-unit space, so the line scales with the glyph.
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth * s, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Charging bolt (Battery widget), filled.
public struct BoltGlyph: View {
    private let size: CGFloat
    private let color: Color

    public init(size: CGFloat = 16, color: Color = WXColor.beachSand) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 24
            var path = Path()
            path.move(to: CGPoint(x: 13 * s, y: 2 * s))
            path.addLine(to: CGPoint(x: 4 * s, y: 14 * s))
            path.addLine(to: CGPoint(x: 11 * s, y: 14 * s))
            path.addLine(to: CGPoint(x: 10 * s, y: 22 * s))
            path.addLine(to: CGPoint(x: 19 * s, y: 10 * s))
            path.addLine(to: CGPoint(x: 12 * s, y: 10 * s))
            path.closeSubpath()
            context.fill(path, with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Processor glyph (Tech device chip), stroked.
public struct ChipGlyph: View {
    private let size: CGFloat
    private let color: Color

    public init(size: CGFloat = 28, color: Color = WXColor.beachSand) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 24
            var path = Path(roundedRect: CGRect(x: 6 * s, y: 6 * s, width: 12 * s, height: 12 * s), cornerRadius: 2 * s)
            for x in [9.0, 15.0] {
                path.move(to: CGPoint(x: x * s, y: 2 * s)); path.addLine(to: CGPoint(x: x * s, y: 5 * s))
                path.move(to: CGPoint(x: x * s, y: 19 * s)); path.addLine(to: CGPoint(x: x * s, y: 22 * s))
            }
            for y in [9.0, 15.0] {
                path.move(to: CGPoint(x: 2 * s, y: y * s)); path.addLine(to: CGPoint(x: 5 * s, y: y * s))
                path.move(to: CGPoint(x: 19 * s, y: y * s)); path.addLine(to: CGPoint(x: 22 * s, y: y * s))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Box-breathing glyph (Breathe chip): a faint square with the traced edge and a dot.
public struct BoxBreathGlyph: View {
    private let size: CGFloat

    public init(size: CGFloat = 54) {
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 54
            let square = Path(roundedRect: CGRect(x: 5 * s, y: 5 * s, width: 44 * s, height: 44 * s), cornerRadius: 6 * s)
            context.stroke(square, with: .color(WXColor.labelIvory.opacity(0.35)), lineWidth: 3 * s)
            var trace = Path()
            trace.move(to: CGPoint(x: 11 * s, y: 5 * s))
            trace.addLine(to: CGPoint(x: 43 * s, y: 5 * s))
            trace.addArc(tangent1End: CGPoint(x: 49 * s, y: 5 * s), tangent2End: CGPoint(x: 49 * s, y: 11 * s), radius: 6 * s)
            trace.addLine(to: CGPoint(x: 49 * s, y: 31 * s))
            context.stroke(trace, with: .color(WXColor.labelIvory), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: 45 * s, y: 27 * s, width: 8 * s, height: 8 * s)), with: .color(WXColor.labelIvory))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
