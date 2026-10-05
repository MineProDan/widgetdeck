import CoreKit
import DesignSystem
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Borders and effects (A-07)

extension WidgetBorderColor {
    /// The paint for this border. Theme colours come from the applied theme; with no theme they
    /// fall back to the Paint Chip defaults the theme would replace (Coral Hour / Deep Tide).
    public func color(theme: ActiveThemeSnapshot?) -> Color {
        switch self {
        case .labelIvory: WXColor.labelIvory
        case .paperIvory: WXColor.paperIvory
        case .ink: WXColor.ink
        case .coralHour: WXColor.coralHour
        case .sageNoon: WXColor.sageNoon
        case .beachSand: WXColor.beachSand
        case .deepTide: WXColor.deepTide
        case .plumDusk: WXColor.plumDusk
        case .themeAccent: theme.map { $0.accent.swiftUIColor } ?? WXColor.coralHour
        case .themePrimary: theme.map { $0.primary.swiftUIColor } ?? WXColor.deepTide
        }
    }
}

/// Wraps widget content in the user's border (a flat mat of paint, concentric with the system
/// corner). Tinted/clear/vibrant modes can't show paint: the border becomes an accentable band
/// of the system tint, so the frame still reads.
struct WidgetBorder: ViewModifier {
    let style: WidgetStyle
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        if style.border {
            let inset = style.borderWidth.points
            content
                .clipShape(InnerCornerShape(style: style.corners))
                .padding(inset)
                .background {
                    if renderingMode == .fullColor {
                        style.borderColor.color(theme: ActiveThemeStore().read())
                    } else {
                        Color.primary.opacity(0.5).widgetAccentable()
                    }
                }
        } else {
            content
        }
    }
}

/// Inside a border: concentric with the system corner (rounded) or square-cut.
struct InnerCornerShape: Shape {
    let style: WidgetCornerStyle

    func path(in rect: CGRect) -> Path {
        style == .rounded ? ContainerRelativeShape().path(in: rect) : Rectangle().path(in: rect)
    }
}

/// Flat Ink veil over a photo (full colour only; tinted modes already flatten the image).
struct PhotoDim: ViewModifier {
    let dim: WidgetDim
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content.overlay {
            if dim != .none, renderingMode == .fullColor {
                WXColor.ink.opacity(dim.opacity).allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Applies the user's A-07 border to a whole widget.
    public func aestheticWidgetBorder(_ style: WidgetStyle) -> some View {
        modifier(WidgetBorder(style: style))
    }

    /// Applies the user's A-07 dim to a photo.
    public func aestheticPhotoDim(_ dim: WidgetDim) -> some View {
        modifier(PhotoDim(dim: dim))
    }
}

// MARK: - Mood board widget (A-06)

/// Mood board widget: the user's photos as a flat grid (2 × 2 medium; 3 × 2 or 4 × 2 large) on
/// Label Ivory, with the Paint Chip punch hole. Tiles are pre-sized files; nothing is resized here.
public struct MoodBoardWidgetView: View {
    public let entry: MoodBoardEntry
    private let files: AestheticFiles
    @Environment(\.widgetFamily) private var family

    public init(entry: MoodBoardEntry, files: AestheticFiles = AestheticFiles()) {
        self.entry = entry
        self.files = files
    }

    private var layout: MoodBoardLayout {
        MoodBoardLayout.forSlot(family == .systemMedium ? .medium : .large,
                                photoCount: entry.isSample ? MoodBoardLayout.large6.tileCount : entry.photos.count)
    }

    public var body: some View {
        if entry.isSample || !entry.photos.isEmpty {
            board
                .paintChipPunchHole(family == .systemMedium ? .medium : .large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aestheticWidgetBorder(entry.style)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(entry.isSample ? "Sample mood board" : "Your mood board, \(min(entry.photos.count, layout.tileCount)) photos")
                .paintChipWidgetBackground()
        } else {
            PaintChipWidget(axis: .horizontal, color: WXSection.aesthetic.color, field: .ratio(0.42)) {
                EmptyView()
            } label: {
                ChipLabelBand(caption: "Mood board", value: "Add photos", trend: "Pick them in Widgetdeck", valueSize: 22,
                              padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            .aestheticWidgetBorder(entry.style)
        }
    }

    private var board: some View {
        GeometryReader { proxy in
            let frames = layout.tileFrames(in: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    tile(at: index)
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(RoundedRectangle(cornerRadius: entry.style.corners.radius, style: .continuous))
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
    }

    @ViewBuilder
    private func tile(at index: Int) -> some View {
        if entry.isSample {
            SampleTile(index: index)
        } else if index < entry.photos.count, let image = loadImage(entry.photos[index]) {
            Color.clear.overlay {
                Image(uiImage: image).resizable().photoAccentedRendering().scaledToFill()
            }
            .clipped()
            .aestheticPhotoDim(entry.style.dim)
        } else {
            // Fewer photos than tiles: flat Paint Chip paints fill the rest, never a blank hole.
            SampleTile(index: index)
        }
    }

    private func loadImage(_ item: MoodBoardItem) -> UIImage? {
        guard let name = item.files[layout] ?? item.files[.medium] else { return nil }
        return UIImage(contentsOfFile: files.moodBoardURL(for: name).path(percentEncoded: false))
    }
}

/// A flat paint tile: gallery preview and filler for boards with fewer photos than tiles.
struct SampleTile: View {
    let index: Int
    private static let paints = [WXColor.beachSand, WXColor.coralHour, WXColor.deepTide,
                                 WXColor.sageNoon, WXColor.shell, WXColor.plumDusk]

    var body: some View {
        Self.paints[index % Self.paints.count].widgetAccentable()
    }
}

#Preview("Mood board", as: .systemMedium) {
    MoodBoardWidgetShim()
} timeline: {
    MoodBoardEntry.sample(at: Date(timeIntervalSinceReferenceDate: 0))
    MoodBoardEntry(date: Date(timeIntervalSinceReferenceDate: 1), photos: [],
                   style: WidgetStyle(border: true, borderColor: .ink, borderWidth: .regular))
}

private struct MoodBoardWidgetShim: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "preview.moodBoard", provider: MoodBoardTimelineProvider(read: { nil }, readStyle: { .default })) {
            MoodBoardWidgetView(entry: $0)
        }
        .contentMarginsDisabled()
    }
}
