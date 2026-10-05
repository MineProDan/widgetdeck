import SwiftUI

/// The five app tabs, in mockup order.
public enum WXTab: String, CaseIterable, Identifiable, Sendable {
    case home, student, aesthetic, wellness, tech

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "Home"
        case .student: "Student"
        case .aesthetic: "Aesthetic"
        case .wellness: "Wellness"
        case .tech: "Tech"
        }
    }
}

/// Paper Ivory tab bar: 1 pt Rule top border, 24 pt stroke icons (1.9 pt) over 10 pt condensed
/// caps; active tab Ink, others Ink Inactive. 49 pt of content plus the bottom safe area (83 pt
/// total on a Face ID iPhone). Attach with `.safeAreaInset(edge: .bottom) { WXTabBar(...) }`.
public struct WXTabBar: View {
    @Binding private var selection: WXTab

    public init(selection: Binding<WXTab>) {
        _selection = selection
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(WXTab.allCases) { tab in
                let active = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        TabIcon(tab: tab)
                            .stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                            .frame(width: 24, height: 24)
                        Text(tab.title)
                            .wxLabel(10, color: active ? WXColor.ink : WXColor.inkInactive)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(active ? WXColor.ink : WXColor.inkInactive)
                    .frame(width: 66)
                    .frame(minHeight: 44, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(active ? .isSelected : [])
                .accessibilityShowsLargeContentViewer()
            }
        }
        .padding(.top, 7)
        .frame(height: 49, alignment: .top)
        .frame(maxWidth: .infinity)
        .background {
            WXColor.paperIvory
                .overlay(alignment: .top) { WXColor.rule.frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
        // Like the system tab bar: fixed-size labels; long-press shows the Large Content Viewer.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

/// Stroke icons from the mockup's tab bar (24-unit SVG paths).
struct TabIcon: Shape {
    let tab: WXTab

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        switch tab {
        case .home:
            // M4 11l8-7 8 7v9h-5v-6h-6v6H4z
            path.move(to: p(4, 11)); path.addLine(to: p(12, 4)); path.addLine(to: p(20, 11))
            path.addLine(to: p(20, 20)); path.addLine(to: p(15, 20)); path.addLine(to: p(15, 14))
            path.addLine(to: p(9, 14)); path.addLine(to: p(9, 20)); path.addLine(to: p(4, 20)); path.closeSubpath()
        case .student:
            // M3 9l9-4 9 4-9 4-9-4z  M7 11v5c0 1.4 2.2 3 5 3s5-1.6 5-3v-5
            path.move(to: p(3, 9)); path.addLine(to: p(12, 5)); path.addLine(to: p(21, 9))
            path.addLine(to: p(12, 13)); path.closeSubpath()
            path.move(to: p(7, 11)); path.addLine(to: p(7, 16))
            path.addCurve(to: p(12, 19), control1: p(7, 17.4), control2: p(9.2, 19))
            path.addCurve(to: p(17, 16), control1: p(14.8, 19), control2: p(17, 17.4))
            path.addLine(to: p(17, 11))
        case .aesthetic:
            // rect 4,3 6×17 rx1.5  M10 8l5-3 4.5 7.5L10 18
            path.addRoundedRect(in: CGRect(origin: p(4, 3), size: CGSize(width: 6 * s, height: 17 * s)),
                                cornerSize: CGSize(width: 1.5 * s, height: 1.5 * s))
            path.move(to: p(10, 8)); path.addLine(to: p(15, 5)); path.addLine(to: p(19.5, 12.5)); path.addLine(to: p(10, 18))
        case .wellness:
            // M5 19c0-8 5-14 14-14 0 9-6 14-14 14z  M5 19l8-8
            path.move(to: p(5, 19))
            path.addCurve(to: p(19, 5), control1: p(5, 11), control2: p(10, 5))
            path.addCurve(to: p(5, 19), control1: p(19, 14), control2: p(13, 19))
            path.closeSubpath()
            path.move(to: p(5, 19)); path.addLine(to: p(13, 11))
        case .tech:
            // M4 16a8 8 0 1 1 16 0  M12 16l4-5
            path.move(to: p(4, 16))
            path.addArc(center: p(12, 16), radius: 8 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            path.move(to: p(12, 16)); path.addLine(to: p(16, 11))
        }
        return path
    }
}

/// Screen title block: 40 pt Bricolage title with a plain 15 pt body subtitle below.
/// No caps eyebrow above the title (DESIGN.md "The Plain Subtitle Rule").
public struct WXPageHeader: View {
    private let title: String
    private let subtitle: String?
    private let titleSize: CGFloat

    /// - Parameter titleSize: 40 by default; 36 for long titles ("Match my wallpaper").
    public init(title: String, subtitle: String? = nil, titleSize: CGFloat = 40) {
        self.title = title
        self.subtitle = subtitle
        self.titleSize = titleSize
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: WXSpace.xs) {
            Text(title)
                .wxGrotesk(titleSize)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .wxBody(15)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Group header: a caps label on the left with an optional caps link on the right (Clay Link).
public struct WXSectionHeader: View {
    private let title: String
    private let accessory: String?
    private let accessoryColor: Color
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - accessory: right-hand text ("See it", "All 7", "Mostly good").
    ///   - action: when set, the accessory is a link-styled button.
    public init(_ title: String, accessory: String? = nil, accessoryColor: Color = WXColor.clayLink, action: (() -> Void)? = nil) {
        self.title = title
        self.accessory = accessory
        self.accessoryColor = accessoryColor
        self.action = action
    }

    public var body: some View {
        HStack {
            Text(title).wxLabel().accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let accessory {
                if let action {
                    Button(action: action) {
                        Text(accessory).wxLabel(color: accessoryColor)
                            .padding(.vertical, 12)
                            .padding(.leading, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(accessory).wxLabel(color: accessoryColor)
                }
            }
        }
    }
}

/// Segmented control: #ECE6DA track (radius 10, 36 pt), selected segment Label Ivory with a
/// light shadow, 13 pt labels.
public struct WXSegmentedControl<Value: Hashable>: View {
    @Binding private var selection: Value
    private let options: [(value: Value, title: String)]

    public init(selection: Binding<Value>, options: [(value: Value, title: String)]) {
        _selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(WXFont.body(13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(WXColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(WXColor.labelIvory)
                                    .wxShadow(.segment, cornerRadius: 8)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(minHeight: 36)
        .background(WXColor.segmentTrack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Onboarding page dots: an 18 × 6 Ink bar for the current step, 6 pt dots for the rest.
public struct WXPageDots: View {
    private let count: Int
    private let current: Int

    public init(count: Int, current: Int) {
        self.count = count
        self.current = current
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? WXColor.ink : WXColor.pageDotInactive)
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
