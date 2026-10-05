import CoreKit
import SwiftUI
import WidgetKit

/// Widget chrome for Paint Chip widgets.
///
/// Usage (in the widget extension):
/// ```swift
/// StaticConfiguration(kind: …, provider: …) { entry in
///     PaintChipWidget(axis: .vertical, color: WXSection.tech.color, field: .fixed(76)) {
///         FillBar(value: entry.level, color: WXColor.beachSand, height: 14, trackOpacity: 0.18).fieldBottomBar()
///     } label: {
///         ChipLabelBand(caption: "Battery · charging", value: "82%", trend: "Est. 1h 10m to full", tabular: true)
///     }
/// }
/// .contentMarginsDisabled()   // the chip runs edge to edge; the band supplies its own padding
/// ```
///
/// - fullColor: Label Ivory container background, the field in its paint, no shadow (the system
///   draws the widget and its corner radius).
/// - accented (iOS 18 tinted, iOS 26 clear) / vibrant (Lock Screen, StandBy): the system removes
///   the background; the field becomes a tinted/translucent block (`widgetAccentable`) and the
///   punch hole stays, so the chip anatomy still reads.
public struct PaintChipWidget<Field: View, Label: View>: View {
    private let axis: Axis
    private let color: Color
    private let field: ChipFieldSize
    private let punchHole: PunchHole?
    private let fieldContent: Field
    private let label: Label

    public init(
        axis: Axis = .vertical,
        color: Color,
        field: ChipFieldSize,
        punchHole: PunchHole? = .regular,
        @ViewBuilder field fieldContent: () -> Field,
        @ViewBuilder label: () -> Label
    ) {
        self.axis = axis
        // Widgets follow the user's applied theme (read from the App Group; the app writes it).
        self.color = WidgetThemePaint.resolve(color, theme: ActiveThemeStore().read())
        self.field = field
        self.punchHole = punchHole
        self.fieldContent = fieldContent()
        self.label = label()
    }

    public var body: some View {
        PaintChip(axis: axis, color: color, field: field, punchHole: punchHole, cornerRadius: 0, shadow: nil) {
            fieldContent
        } label: {
            label
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paintChipWidgetTypeLimits()
        .paintChipWidgetBackground()
    }
}

extension View {
    /// Widgets have a fixed size, so their chips cannot grow. Caps Dynamic Type at xxLarge and
    /// lets text shrink to 75 % before truncating, so the largest sizes stay inside the chip.
    public func paintChipWidgetTypeLimits() -> some View {
        dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .minimumScaleFactor(0.75)
    }

    /// `containerBackground` for Paint Chip widgets: Label Ivory, so the band colour reaches the
    /// widget's rounded edge. Registers the bundled fonts for the widget process.
    public func paintChipWidgetBackground() -> some View {
        _ = WXFonts.registerIfNeeded()
        return containerBackground(for: .widget) { WXColor.labelIvory }
    }
}
