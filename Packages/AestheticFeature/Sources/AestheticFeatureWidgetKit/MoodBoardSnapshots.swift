import CoreGraphics
import CoreKit
import Foundation

// MARK: - Mood board (A-06)

/// Grid layouts of the Mood board widget. Each photo is cached once per layout, at the exact
/// pixel size of one tile on this device (Platform Reality Rule 7: never resize at render time).
public enum MoodBoardLayout: String, Codable, CaseIterable, Sendable {
    /// systemMedium: 2 × 2.
    case medium
    /// systemLarge with fewer than 8 photos: 3 columns × 2 rows.
    case large6
    /// systemLarge with 8 or more photos: 4 columns × 2 rows.
    case large8

    /// Points between tiles (the Label Ivory ground shows through).
    public static let gap: CGFloat = 3

    public var columns: Int {
        switch self {
        case .medium: 2
        case .large6: 3
        case .large8: 4
        }
    }

    public var rows: Int { 2 }
    public var tileCount: Int { columns * rows }

    /// The widget slot this layout fills.
    public var slot: PhotoSlot { self == .medium ? .medium : .large }

    /// The layout a widget family shows for a board of `photoCount` photos.
    public static func forSlot(_ slot: PhotoSlot, photoCount: Int) -> MoodBoardLayout {
        switch slot {
        case .small, .medium: .medium
        case .large: photoCount >= MoodBoardLayout.large8.tileCount ? .large8 : .large6
        }
    }

    /// Size of one tile, in points, inside a widget of `container` points.
    public func tileSize(in container: CGSize) -> CGSize {
        let gap = Self.gap
        return CGSize(width: max(0, (container.width - gap * CGFloat(columns - 1)) / CGFloat(columns)),
                      height: max(0, (container.height - gap * CGFloat(rows - 1)) / CGFloat(rows)))
    }

    /// Tile frames, row by row, top-left first.
    public func tileFrames(in container: CGSize) -> [CGRect] {
        let tile = tileSize(in: container)
        return (0..<tileCount).map { index in
            let column = index % columns, row = index / columns
            return CGRect(x: CGFloat(column) * (tile.width + Self.gap), y: CGFloat(row) * (tile.height + Self.gap),
                          width: tile.width, height: tile.height)
        }
    }

    /// Exact tile pixel size on a screen of `screen` points at `scale` (rounded up: never upscaled).
    public func tilePixels(screen: CGSize, scale: CGFloat) -> PixelSize {
        PixelSize(points: tileSize(in: PhotoWidgetSize.points(for: slot, screen: screen)), scale: scale)
    }
}

/// A photo on the mood board, already downsampled once per layout.
public struct MoodBoardItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var addedAt: Date
    /// File name per layout, relative to `AestheticFiles.moodBoardDirectory`.
    public var files: [MoodBoardLayout: String]

    public init(id: UUID = UUID(), addedAt: Date, files: [MoodBoardLayout: String]) {
        self.id = id
        self.addedAt = addedAt
        self.files = files
    }
}

/// Everything the Mood board widget needs. Written by the app after every edit.
public struct MoodBoardSnapshot: WidgetSnapshot, Hashable {
    public static let kind: WidgetKind = .moodBoard

    /// Photos in the order the user arranged them.
    public var photos: [MoodBoardItem]
    /// Show a different arrangement each day (precomputed timeline entries).
    public var shuffleDaily: Bool
    public var generatedAt: Date

    public init(photos: [MoodBoardItem], shuffleDaily: Bool, generatedAt: Date) {
        self.photos = photos
        self.shuffleDaily = shuffleDaily
        self.generatedAt = generatedAt
    }
}

// MARK: - Borders and effects (A-07)

/// Border colours: Paint Chip tokens, or the active theme's two colours.
public enum WidgetBorderColor: String, Codable, CaseIterable, Sendable {
    case labelIvory, paperIvory, ink, coralHour, sageNoon, beachSand, deepTide, plumDusk
    case themeAccent, themePrimary

    public var title: String {
        switch self {
        case .labelIvory: "Label Ivory"
        case .paperIvory: "Paper Ivory"
        case .ink: "Ink"
        case .coralHour: "Coral Hour"
        case .sageNoon: "Sage Noon"
        case .beachSand: "Beach Sand"
        case .deepTide: "Deep Tide"
        case .plumDusk: "Plum Dusk"
        case .themeAccent: "Theme accent"
        case .themePrimary: "Theme primary"
        }
    }
}

public enum WidgetBorderWidth: String, Codable, CaseIterable, Sendable {
    case thin, regular, thick

    public var points: CGFloat {
        switch self {
        case .thin: 4
        case .regular: 8
        case .thick: 12
        }
    }

    public var title: String {
        switch self {
        case .thin: "Thin"
        case .regular: "Regular"
        case .thick: "Thick"
        }
    }
}

/// Corners of the photos inside the widget (the widget's outer corners belong to the system).
public enum WidgetCornerStyle: String, Codable, CaseIterable, Sendable {
    case rounded, square

    public var radius: CGFloat { self == .rounded ? 8 : 0 }   // WXRadius.swatch
    public var title: String { self == .rounded ? "Rounded" : "Square" }
}

/// A flat Ink veil over photos, so a busy photo sits quieter on the Home Screen.
public enum WidgetDim: String, Codable, CaseIterable, Sendable {
    case none, light, medium

    public var opacity: Double {
        switch self {
        case .none: 0
        case .light: 0.15
        case .medium: 0.3
        }
    }

    public var title: String {
        switch self {
        case .none: "None"
        case .light: "Light"
        case .medium: "Medium"
        }
    }
}

/// The user's border and effect choices for one Aesthetic widget. Flat paint only:
/// no gradients, glass or blur (DESIGN.md).
public struct WidgetStyle: Codable, Hashable, Sendable {
    public var border: Bool
    public var borderColor: WidgetBorderColor
    public var borderWidth: WidgetBorderWidth
    public var corners: WidgetCornerStyle
    /// Photo widgets only.
    public var dim: WidgetDim

    public static let `default` = WidgetStyle()

    public init(border: Bool = false, borderColor: WidgetBorderColor = .labelIvory,
                borderWidth: WidgetBorderWidth = .regular, corners: WidgetCornerStyle = .rounded, dim: WidgetDim = .none) {
        self.border = border
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.corners = corners
        self.dim = dim
    }

    private enum CodingKeys: String, CodingKey { case border, borderColor, borderWidth, corners, dim }

    /// Missing or unknown values fall back to the default, so older/newer files never break a widget.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WidgetStyle.default
        border = (try? c.decodeIfPresent(Bool.self, forKey: .border)) ?? d.border
        borderColor = (try? c.decodeIfPresent(WidgetBorderColor.self, forKey: .borderColor)) ?? d.borderColor
        borderWidth = (try? c.decodeIfPresent(WidgetBorderWidth.self, forKey: .borderWidth)) ?? d.borderWidth
        corners = (try? c.decodeIfPresent(WidgetCornerStyle.self, forKey: .corners)) ?? d.corners
        dim = (try? c.decodeIfPresent(WidgetDim.self, forKey: .dim)) ?? d.dim
    }
}

/// Which Aesthetic widget a style belongs to.
public enum AestheticStyleTarget: String, Codable, CaseIterable, Sendable {
    case photo, moodBoard, palette

    public var title: String {
        switch self {
        case .photo: "Photo"
        case .moodBoard: "Mood board"
        case .palette: "Palette"
        }
    }

    public var kind: WidgetKind {
        switch self {
        case .photo: .photo
        case .moodBoard: .moodBoard
        case .palette: .palette
        }
    }

    /// Dim only makes sense over photos.
    public var supportsDim: Bool { self != .palette }
}

/// Border and effect settings for every Aesthetic widget, in one small App Group file
/// (`Snapshots/aesthetic-styles.json`). Written by the app, read by the widgets.
public struct AestheticStyleSnapshot: WidgetSnapshot, Hashable {
    public static let kind: WidgetKind = .photo
    public static let fileName = "aesthetic-styles"

    public var photo: WidgetStyle
    public var moodBoard: WidgetStyle
    public var palette: WidgetStyle
    public var generatedAt: Date

    public init(photo: WidgetStyle = .default, moodBoard: WidgetStyle = .default, palette: WidgetStyle = .default,
                generatedAt: Date = Date(timeIntervalSinceReferenceDate: 0)) {
        self.photo = photo
        self.moodBoard = moodBoard
        self.palette = palette
        self.generatedAt = generatedAt
    }

    public subscript(target: AestheticStyleTarget) -> WidgetStyle {
        get {
            switch target {
            case .photo: photo
            case .moodBoard: moodBoard
            case .palette: palette
            }
        }
        set {
            switch target {
            case .photo: photo = newValue
            case .moodBoard: moodBoard = newValue
            case .palette: palette = newValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey { case photo, moodBoard, palette, generatedAt }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        photo = (try? c.decodeIfPresent(WidgetStyle.self, forKey: .photo)) ?? .default
        moodBoard = (try? c.decodeIfPresent(WidgetStyle.self, forKey: .moodBoard)) ?? .default
        palette = (try? c.decodeIfPresent(WidgetStyle.self, forKey: .palette)) ?? .default
        generatedAt = (try? c.decodeIfPresent(Date.self, forKey: .generatedAt)) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    /// Reads the file, or all defaults when there is none.
    public static func load(store: SnapshotStore = SnapshotStore()) -> AestheticStyleSnapshot {
        store.read(AestheticStyleSnapshot.self) ?? AestheticStyleSnapshot()
    }
}
