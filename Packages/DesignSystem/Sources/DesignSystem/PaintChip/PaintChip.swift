import SwiftUI
import WidgetKit

/// The punch hole: a Paper Ivory mark near the top-left of every colour field. A circle in the
/// Paint Chip deck; other theme decks die-cut their own shape (`WXDeck.PunchShape`).
public struct PunchHole: Hashable, Sendable {
    public var diameter: CGFloat
    /// Distance from the field's top and leading edges.
    public var inset: CGFloat
    /// Centre the hole horizontally (paint strips in the onboarding fan).
    public var centered: Bool

    public init(diameter: CGFloat, inset: CGFloat, centered: Bool = false) {
        self.diameter = diameter
        self.inset = inset
        self.centered = centered
    }

    /// 8 pt, 8 in: list rows and thermal cells.
    public static let small = PunchHole(diameter: 8, inset: 8)
    /// 9 pt, 9 in: deck chips and suggestion rows.
    public static let deck = PunchHole(diameter: 9, inset: 9)
    /// 9 pt, 10 in: small widgets and metric cards (the default).
    public static let regular = PunchHole(diameter: 9, inset: 10)
    /// 11 pt, 13 in: medium widgets.
    public static let medium = PunchHole(diameter: 11, inset: 13)
    /// 12 pt, 14 in: the Home hero card.
    public static let large = PunchHole(diameter: 12, inset: 14)
    /// 10 pt centred, 10 in: paint strips.
    public static let strip = PunchHole(diameter: 10, inset: 10, centered: true)
}

/// How long the colour field is along the chip's axis.
public enum ChipFieldSize: Hashable, Sendable {
    /// A fixed length in points (mockup values, e.g. 78 for a metric card).
    case fixed(CGFloat)
    /// A share of the chip's length (e.g. 0.54 for a 158 pt small widget with an 86 pt field).
    case ratio(CGFloat)
}

/// The signature component: a flat colour field (top or leading) over/next to an ivory label band.
///
/// ```swift
/// PaintChip(axis: .vertical, color: WXSection.tech.color, field: .fixed(78)) {
///     FillBar(value: 0.82, color: WXColor.beachSand)
/// } label: {
///     ChipLabelBand(caption: "Battery", value: "82%", trend: "Charging · est. 1h 10m", trendColor: WXColor.mossPositive)
/// }
/// ```
///
/// Rules (DESIGN.md): text never sits on the field; the band holds all words. With larger
/// Dynamic Type the band grows: the chip grows when its height is free; when the height is fixed
/// (a widget) the field shrinks first, then text scales down (see `paintChipWidgetTypeLimits`). In widget accented/vibrant rendering the field turns into a
/// tinted/translucent block so the chip still reads as a chip.
public struct PaintChip<Field: View, Label: View>: View {
    private let axis: Axis
    private let color: Color
    private let field: ChipFieldSize
    private let punchHole: PunchHole?
    private let cornerRadius: CGFloat
    private let shadow: WXShadow?
    private let fieldContent: Field
    private let label: Label

    @Environment(\.widgetRenderingMode) private var renderingMode

    /// - Parameters:
    ///   - axis: `.vertical` = field on top (small widget, deck chip); `.horizontal` = field leading
    ///     (medium widget, list row, Live Activity).
    ///   - field: the field's length along `axis`.
    ///   - punchHole: `nil` for fields that hold a glyph instead (device chip).
    ///   - cornerRadius: `WXRadius.card` (default), `.chip`, `.widget`, `.deckChip`.
    ///   - shadow: `nil` inside widgets (the system draws the widget).
    public init(
        axis: Axis = .vertical,
        color: Color,
        field: ChipFieldSize = .ratio(0.5),
        punchHole: PunchHole? = .regular,
        cornerRadius: CGFloat = WXRadius.card,
        shadow: WXShadow? = .chipRest,
        @ViewBuilder field fieldContent: () -> Field,
        @ViewBuilder label: () -> Label
    ) {
        self.axis = axis
        self.color = color
        self.field = field
        self.punchHole = punchHole
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.fieldContent = fieldContent()
        self.label = label()
    }

    /// Spec-style initialiser: `fieldRatio` is the field's share of the chip's length.
    public init(
        axis: Axis = .vertical,
        color: Color,
        fieldRatio: CGFloat,
        punchHole: Bool = true,
        @ViewBuilder field fieldContent: () -> Field,
        @ViewBuilder label: () -> Label
    ) {
        self.init(axis: axis, color: color, field: .ratio(fieldRatio), punchHole: punchHole ? .regular : nil,
                  field: fieldContent, label: label)
    }

    public var body: some View {
        ChipLayout(axis: axis, field: field) {
            fieldView
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
            label
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .leading)
                // In a fixed-size chip, overflowing text is cut at the band's edge; it must never
                // spill onto the colour field (the Pure Field Rule).
                .clipped()
        }
        .background(isFullColor ? WXColor.labelIvory : Color.clear)
        .wxRounded(cornerRadius)
        .modifier(OptionalShadow(shadow: isFullColor ? shadow : nil, cornerRadius: cornerRadius))
    }

    private var isFullColor: Bool {
        DSRenderingMode(renderingMode) == .fullColor
    }

    private var fieldView: some View {
        ZStack(alignment: .topLeading) {
            fieldFill
            fieldContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let punchHole {
                PunchHoleMark(punchHole: punchHole)
            }
        }
    }

    @ViewBuilder
    private var fieldFill: some View {
        switch DSRenderingMode(renderingMode) {
        case .fullColor:
            color
        case .accented:
            // Tinted/clear Home Screen: the field becomes an accent block.
            Color.primary.opacity(0.22).widgetAccentable()
        case .vibrant:
            Color.primary.opacity(0.18)
        }
    }
}

extension PaintChip where Field == EmptyView {
    /// A chip whose field holds only the punch hole.
    public init(
        axis: Axis = .vertical,
        color: Color,
        field: ChipFieldSize = .ratio(0.5),
        punchHole: PunchHole? = .regular,
        cornerRadius: CGFloat = WXRadius.card,
        shadow: WXShadow? = .chipRest,
        @ViewBuilder label: () -> Label
    ) {
        self.init(axis: axis, color: color, field: field, punchHole: punchHole, cornerRadius: cornerRadius,
                  shadow: shadow, field: { EmptyView() }, label: label)
    }
}

private struct OptionalShadow: ViewModifier {
    let shadow: WXShadow?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if let shadow {
            content.wxShadow(shadow, cornerRadius: cornerRadius)
        } else {
            content
        }
    }
}

/// Lays out [field, band] along an axis. The band always gets at least its ideal length so text
/// is never clipped: with a free length the chip grows; with a fixed length the field shrinks.
struct ChipLayout: Layout {
    let axis: Axis
    let field: ChipFieldSize
    /// The field never shrinks below this (keeps the punch hole and bars visible).
    var minimumField: CGFloat = 24

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (fieldLength, bandLength, cross) = measure(proposal: proposal, subviews: subviews)
        let length = fieldLength + bandLength
        return axis == .vertical ? CGSize(width: cross, height: length) : CGSize(width: length, height: cross)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let proposed = ProposedViewSize(width: bounds.width, height: bounds.height)
        let (fieldLength, _, _) = measure(proposal: proposed, subviews: subviews)
        if axis == .vertical {
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: fieldLength))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + fieldLength),
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height - fieldLength))
        } else {
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: fieldLength, height: bounds.height))
            subviews[1].place(at: CGPoint(x: bounds.minX + fieldLength, y: bounds.minY),
                              proposal: ProposedViewSize(width: bounds.width - fieldLength, height: bounds.height))
        }
    }

    /// Returns (field length, band length, cross size).
    private func measure(proposal: ProposedViewSize, subviews: Subviews) -> (CGFloat, CGFloat, CGFloat) {
        guard subviews.count == 2 else { return (0, 0, 0) }
        let band = subviews[1]
        if axis == .vertical {
            let width = proposal.width ?? band.sizeThatFits(.unspecified).width
            let bandIdeal = band.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            var fieldLength: CGFloat
            switch field {
            case .fixed(let value): fieldLength = value
            case .ratio(let ratio):
                if let height = proposal.height {
                    fieldLength = height * ratio
                } else {
                    fieldLength = ratio < 1 ? bandIdeal * ratio / (1 - ratio) : bandIdeal
                }
            }
            if let height = proposal.height {
                // Fixed height: give the band what it needs, the field takes the rest.
                fieldLength = max(min(fieldLength, height - bandIdeal), min(minimumField, height))
                return (fieldLength, max(height - fieldLength, 0), width)
            }
            return (fieldLength, bandIdeal, width)
        } else {
            let width = proposal.width ?? 320
            let fieldLength: CGFloat
            switch field {
            case .fixed(let value): fieldLength = value
            case .ratio(let ratio): fieldLength = width * ratio
            }
            let bandIdeal = band.sizeThatFits(ProposedViewSize(width: max(width - fieldLength, 0), height: nil)).height
            // A fixed height (widget) is respected; free height (list rows) grows with the band.
            let height = proposal.height ?? bandIdeal
            return (fieldLength, max(width - fieldLength, 0), height)
        }
    }
}

// MARK: - Label band

/// The caps / display / caps stack on a chip's ivory band. Two type sizes at most: one caps size
/// and one display size (DESIGN.md "The Two Sizes Rule"); rank comes from weight, case and colour.
public struct ChipLabelBand: View {
    private let caption: String?
    private let value: String
    private let trailingValue: String?
    private let trend: String?
    private let trendColor: Color
    private let captionSize: CGFloat
    private let valueSize: CGFloat
    private let tabular: Bool
    private let padding: EdgeInsets
    private let spacing: CGFloat
    private let alignment: Alignment

    /// - Parameters:
    ///   - caption: caps line above the value (paint name, context or code).
    ///   - value: the display value or name.
    ///   - trailingValue: a second value on the same baseline, right-aligned (Home hero "14 min").
    ///   - trend: caps line below (trend, estimate or urgency).
    ///   - trendColor: `WXColor.mossPositive` (good), `.clayLink` (urgent), `.inkSecondary` (neutral).
    ///   - captionSize: 9–11 pt.
    ///   - valueSize: 15–28 pt.
    ///   - alignment: `.leading` fills the band top-to-bottom centred vertically (mockup default).
    public init(
        caption: String? = nil,
        value: String,
        trailingValue: String? = nil,
        trend: String? = nil,
        trendColor: Color = WXColor.inkSecondary,
        captionSize: CGFloat = 11,
        valueSize: CGFloat = 22,
        tabular: Bool = false,
        padding: EdgeInsets = EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13),
        spacing: CGFloat = 4,
        alignment: Alignment = .leading
    ) {
        self.caption = caption
        self.value = value
        self.trailingValue = trailingValue
        self.trend = trend
        self.trendColor = trendColor
        self.captionSize = captionSize
        self.valueSize = valueSize
        self.tabular = tabular
        self.padding = padding
        self.spacing = spacing
        self.alignment = alignment
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let caption {
                Text(caption).wxLabel(captionSize).lineLimit(3)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(wxValue: value, size: valueSize).wxGrotesk(valueSize, tabular: tabular)
                if let trailingValue {
                    Spacer(minLength: 8)
                    Text(wxValue: trailingValue, size: valueSize).wxGrotesk(valueSize, tabular: true)
                }
            }
            if let trend {
                Text(trend).wxLabel(captionSize, color: trendColor)
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .accessibilityElement(children: .combine)
    }
}

#Preview("PaintChip") {
    VStack(spacing: 20) {
        HStack(spacing: 10) {
            PaintChip(color: WXColor.deepTide, field: .fixed(78)) {
                FillBar(value: 0.82, color: WXColor.beachSand)
            } label: {
                ChipLabelBand(caption: "Battery", value: "82%", trend: "Charging · est. 1h 10m",
                              trendColor: WXColor.mossPositive, valueSize: 24, tabular: true)
            }
            .frame(height: 176)
            PaintChip(color: WXColor.coralHour, field: .ratio(0.54), cornerRadius: WXRadius.widget, shadow: .widgetOnWallpaper) {
                ChipLabelBand(caption: "Coral Hour · BIO 201", value: "in 14 min")
            }
            .frame(width: 158, height: 158)
        }
        PaintChip(axis: .horizontal, color: WXColor.sageNoon, field: .fixed(68), punchHole: nil, cornerRadius: WXRadius.chip, shadow: .rowChip) {
            CheckKey(isOn: true)
        } label: {
            ChipLabelBand(value: "Read 20 min", trend: "23-day streak · +1 today", trendColor: WXColor.mossPositive,
                          valueSize: 18, padding: EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14), spacing: 5)
        }
        .frame(minHeight: 76)
    }
    .padding(24)
    .background(WXColor.paperIvory)
}

/// The Paper Ivory punch hole of a Paint Chip. Adapts to widget rendering modes like the chip.
struct PunchHoleMark: View {
    let punchHole: PunchHole
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let shape = WXDeck.current.punch
        // Larger marks grow around the same centre, so the inset to the hole's centre is unchanged.
        let size = punchHole.diameter * shape.sizeMultiplier
        let shift = (size - punchHole.diameter) / 2
        PunchHoleShape(shape)
            .fill(DSRenderingMode(renderingMode) == .fullColor ? WXColor.paperIvory : Color.primary.opacity(0.6))
            .frame(width: size, height: size)
            .padding(.top, max(punchHole.inset - shift, 0))
            .padding(.leading, punchHole.centered ? 0 : max(punchHole.inset - shift, 0))
            .frame(maxWidth: punchHole.centered ? .infinity : nil, alignment: .top)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Adds a Paint Chip punch hole on top of any full-bleed content (e.g. the Photo widget), so
    /// chip-less surfaces keep the same mark as `PaintChip`.
    public func paintChipPunchHole(_ punchHole: PunchHole = .regular) -> some View {
        overlay(alignment: .topLeading) { PunchHoleMark(punchHole: punchHole) }
    }
}
