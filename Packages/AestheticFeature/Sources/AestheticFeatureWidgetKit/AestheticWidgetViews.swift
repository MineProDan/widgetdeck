import CoreKit
import DesignSystem
import SwiftUI
import UIKit
import WidgetKit

extension RGBAColor {
    /// SwiftUI colour in sRGB.
    public var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Palette widget

/// The five palette colours side by side (Palette widget field, accessory widget, app rows).
///
/// Full colour shows the real paints. Tinted/clear and vibrant modes can't show colour, so each
/// stripe becomes a step of the system tint ordered light → dark, and the palette still reads.
public struct PaletteStripes: View {
    private let colors: [RGBAColor]
    private let spacing: CGFloat
    private let cornerRadius: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode

    public init(colors: [RGBAColor], spacing: CGFloat = 0, cornerRadius: CGFloat = 0) {
        self.colors = colors
        self.spacing = spacing
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill(color, index: index))
            }
        }
        .accessibilityHidden(true)
    }

    private func fill(_ color: RGBAColor, index: Int) -> Color {
        if renderingMode == .fullColor { return color.swiftUIColor }
        // Opacity follows the colour's darkness so the tinted strip keeps the palette's value ramp.
        let darkness = 1 - color.relativeLuminance
        return Color.primary.opacity(0.15 + 0.75 * darkness)
    }
}

/// Palette widget (A-02): small = Paint Chip with the five paints as the field;
/// accessoryRectangular = swatch strip + theme name.
public struct PaletteWidgetView: View {
    public let entry: PaletteEntry
    private let style: WidgetStyle
    @Environment(\.widgetFamily) private var family

    /// - Parameter style: A-07 border; nil reads the user's setting from the App Group.
    public init(entry: PaletteEntry, style: WidgetStyle? = nil) {
        self.entry = entry
        self.style = style ?? AestheticStyleSnapshot.load().palette
    }

    public var body: some View {
        switch family {
        case .accessoryRectangular:
            accessory
        default:
            small.aestheticWidgetBorder(style)
        }
    }

    @ViewBuilder
    private var small: some View {
        if let palette = entry.palette {
            PaintChipWidget(color: WXSection.aesthetic.color, field: .ratio(0.6)) {
                PaletteStripes(colors: palette.swatches.map(\.color))
            } label: {
                ChipLabelBand(caption: "From your wallpaper", value: palette.name, valueSize: 20,
                              padding: EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Theme \(palette.name), from your wallpaper")
            .accessibilityValue(palette.swatches.map(\.name).joined(separator: ", "))
        } else {
            PaintChipWidget(color: WXSection.aesthetic.color, field: .ratio(0.6)) {
                EmptyView()
            } label: {
                ChipLabelBand(caption: "Theme Sync", value: "Pick a wallpaper", valueSize: 18,
                              padding: EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13))
            }
        }
    }

    private var accessory: some View {
        let palette = entry.palette
        return VStack(alignment: .leading, spacing: 4) {
            Text(palette == nil ? "Theme Sync" : "From your wallpaper")
                .font(WXFont.label(10))
                .textCase(.uppercase)
                .tracking(0.8)
                .lineLimit(1)
            if let palette {
                PaletteStripes(colors: palette.swatches.map(\.color), spacing: 3, cornerRadius: 3)
                    .frame(height: 16)
                Text(palette.name)
                    .font(WXFont.title(15))
                    .lineLimit(1)
            } else {
                Text("Pick a wallpaper")
                    .font(WXFont.title(15))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .paintChipWidgetTypeLimits()
        .accessibilityElement(children: .combine)
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Photo widget

/// Photo widget (A-01): the picked photo fills the widget, with the Paint Chip punch hole.
/// Images on disk are already the widget's exact pixel size, so decoding here is cheap.
public struct PhotoWidgetView: View {
    public let entry: PhotoEntry
    private let files: AestheticFiles
    private let style: WidgetStyle
    @Environment(\.widgetFamily) private var family

    /// - Parameter style: A-07 border and dim; nil reads the user's setting from the App Group.
    public init(entry: PhotoEntry, files: AestheticFiles = AestheticFiles(), style: WidgetStyle? = nil) {
        self.entry = entry
        self.files = files
        self.style = style ?? AestheticStyleSnapshot.load().photo
    }

    public var body: some View {
        if entry.isSample {
            photoChip { SampleBeachArt() }
                .accessibilityLabel("Sample photo")
        } else if let image = loadImage() {
            photoChip {
                Image(uiImage: image)
                    .resizable()
                    .photoAccentedRendering()
                    .scaledToFill()
                    .aestheticPhotoDim(style.dim)
            }
            .accessibilityLabel("Your photo, \(entry.position) of \(entry.count)")
        } else {
            PaintChipWidget(color: WXSection.aesthetic.color, field: .ratio(0.6)) {
                EmptyView()
            } label: {
                ChipLabelBand(caption: "Photo widget", value: entry.photo == nil ? "Add photos" : "Open Widgetdeck",
                              valueSize: 18, padding: EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13))
            }
            .aestheticWidgetBorder(style)
        }
    }

    private var slot: PhotoSlot {
        switch family {
        case .systemMedium: .medium
        case .systemLarge, .systemExtraLarge: .large
        default: .small
        }
    }

    private var punchHole: PunchHole {
        family == .systemSmall ? .regular : .medium
    }

    private func loadImage() -> UIImage? {
        guard let photo = entry.photo, let name = photo.files[slot] ?? photo.files[.small] else { return nil }
        return UIImage(contentsOfFile: files.url(for: name).path(percentEncoded: false))
    }

    private func photoChip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Color.clear.overlay { content() }.clipped()
            .paintChipPunchHole(punchHole)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aestheticWidgetBorder(style)
            .accessibilityElement(children: .ignore)
            .paintChipWidgetBackground()
    }
}

extension Image {
    /// Tinted/clear Home Screen (iOS 18+): show the photo desaturated rather than as a flat tint.
    @ViewBuilder
    func photoAccentedRendering() -> some View {
        if #available(iOS 18, *) {
            widgetAccentedRenderingMode(.desaturated)
        } else {
            self
        }
    }
}

/// The mockup's flat beach sunset, drawn: gallery previews and the Theme Sync sample.
/// Colours are the ThemeSync artboard's wallpaper paints.
public struct SampleBeachArt: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func rect(_ y0: CGFloat, _ y1: CGFloat) -> Path { Path(CGRect(x: 0, y: h * y0, width: w, height: h * (y1 - y0))) }
            context.fill(rect(0, 0.36), with: .color(WXColor.shell))
            context.fill(rect(0.36, 0.7), with: .color(WXColor.beachSand))
            let sun = min(w, h) * 0.34
            context.fill(Path(ellipseIn: CGRect(x: w * 0.76 - sun, y: h * 0.69 - sun, width: sun * 2, height: sun * 2)),
                         with: .color(WXColor.coralHour))
            context.fill(rect(0.69, 1), with: .color(WXColor.deepTide))
            context.fill(rect(0.735, 0.755), with: .color(ThemeSyncPaint.eveningSea))
            var dune = Path()
            dune.move(to: CGPoint(x: 0, y: h * 0.92))
            dune.addQuadCurve(to: CGPoint(x: w, y: h * 0.92), control: CGPoint(x: w * 0.5, y: h * 0.84))
            dune.addLine(to: CGPoint(x: w, y: h))
            dune.addLine(to: CGPoint(x: 0, y: h))
            context.fill(dune, with: .color(ThemeSyncPaint.wallpaperSand))
        }
        .accessibilityHidden(true)
    }
}

/// Mockup paints used only by Theme Sync (ThemeSync / HomeScreen artboards): the sample
/// wallpaper and the generic, un-themed "before" widget look that Theme Sync replaces.

#Preview("Palette", as: .systemSmall) {
    PaletteWidgetShim()
} timeline: {
    PaletteEntry(date: Date(timeIntervalSinceReferenceDate: 0), palette: .sample)
    PaletteEntry(date: Date(timeIntervalSinceReferenceDate: 1), palette: nil)
}

#Preview("Photo", as: .systemSmall) {
    PhotoWidgetShim()
} timeline: {
    PhotoEntry.sample(at: Date(timeIntervalSinceReferenceDate: 0))
}

/// Preview-only widget declarations (the real ones live in the widget extension).
private struct PaletteWidgetShim: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "preview.palette", provider: PaletteTimelineProvider(read: { .sample })) {
            PaletteWidgetView(entry: $0)
        }
        .contentMarginsDisabled()
    }
}

private struct PhotoWidgetShim: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "preview.photo", provider: PhotoTimelineProvider(read: { nil })) {
            PhotoWidgetView(entry: $0)
        }
        .contentMarginsDisabled()
    }
}
