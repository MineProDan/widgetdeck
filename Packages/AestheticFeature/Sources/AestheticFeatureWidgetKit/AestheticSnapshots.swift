import CoreGraphics
import CoreKit
import Foundation

/// Widget-safe entry point for the Aesthetic section: snapshot types, timelines and widget views
/// live in this module so the widget extension doesn't link the services it never uses.
public enum AestheticWidgetModule {
    public static let section: AppSection = .aesthetic
}

// MARK: - Palette (A-02)

/// One named colour of a Theme Sync palette, in display order.
public struct PaletteSwatch: Codable, Hashable, Sendable {
    /// Role caption shown on the swatch row ("Surface", "Background", "Accent", "Primary", "Text").
    public var role: String
    /// Paint name ("Coral Hour").
    public var name: String
    public var color: RGBAColor

    public init(role: String, name: String, color: RGBAColor) {
        self.role = role
        self.name = name
        self.color = color
    }
}

/// The palette the user last applied with Theme Sync. Written by the app, read by the Palette widget.
public struct PaletteSnapshot: WidgetSnapshot, Hashable {
    public static let kind: WidgetKind = .palette

    /// Theme name ("Beach Hour").
    public var name: String
    /// Five swatches, lightest to darkest as shown in the widget field.
    public var swatches: [PaletteSwatch]
    /// Every text/background pair of the theme meets WCAG AA.
    public var contrastChecked: Bool
    public var generatedAt: Date

    public init(name: String, swatches: [PaletteSwatch], contrastChecked: Bool, generatedAt: Date) {
        self.name = name
        self.swatches = swatches
        self.contrastChecked = contrastChecked
        self.generatedAt = generatedAt
    }

    /// The mockup's "Beach Hour" palette (HomeScreen / ThemeSync artboards). Used for widget
    /// gallery previews only; it carries a fixed date and no time-relative text.
    public static let sample = PaletteSnapshot(
        name: "Beach Hour",
        swatches: [
            PaletteSwatch(role: "Surface", name: "Shell", color: RGBAColor(hex: "#F6DDB2")!),
            PaletteSwatch(role: "Background", name: "Dune", color: RGBAColor(hex: "#F2CC8F")!),
            PaletteSwatch(role: "Accent", name: "Coral Hour", color: RGBAColor(hex: "#E07A5F")!),
            PaletteSwatch(role: "Primary", name: "Evening Sea", color: RGBAColor(hex: "#5B6C8F")!),
            PaletteSwatch(role: "Text", name: "Deep Tide", color: RGBAColor(hex: "#3D405B")!)
        ],
        contrastChecked: true,
        generatedAt: Date(timeIntervalSinceReferenceDate: 0)
    )
}

// MARK: - Photos (A-01)

/// How often the Photo widget moves to the next photo.
public enum PhotoRotation: String, Codable, CaseIterable, Sendable {
    case daily, hourly

    public var title: String {
        switch self {
        case .daily: "Daily"
        case .hourly: "Hourly"
        }
    }
}

/// Widget families the Photo widget supports; each photo is cached once per family.
public enum PhotoSlot: String, Codable, CaseIterable, Sendable {
    case small, medium, large
}

/// A picked photo. Its files are already downsampled to the exact widget pixel size per slot.
public struct PhotoItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var addedAt: Date
    /// File name per slot, relative to `AestheticFiles.photosDirectory`.
    public var files: [PhotoSlot: String]

    public init(id: UUID = UUID(), addedAt: Date, files: [PhotoSlot: String]) {
        self.id = id
        self.addedAt = addedAt
        self.files = files
    }
}

/// Everything the Photo widget needs. Written by the app after every import, delete or setting change.
public struct PhotoSnapshot: WidgetSnapshot, Hashable {
    public static let kind: WidgetKind = .photo

    public var photos: [PhotoItem]
    public var rotation: PhotoRotation
    public var generatedAt: Date

    public init(photos: [PhotoItem], rotation: PhotoRotation, generatedAt: Date) {
        self.photos = photos
        self.rotation = rotation
        self.generatedAt = generatedAt
    }
}

/// App Group file locations shared by the app (writer) and the widget extension (reader).
public struct AestheticFiles: Sendable {
    public let root: URL

    public init(appGroup: AppGroupContainer = .shared) {
        root = appGroup.applicationSupportURL.appending(path: "Aesthetic", directoryHint: .isDirectory)
    }

    public init(root: URL) {
        self.root = root
    }

    /// Downsampled photo-widget images (not in Caches: the user picked them, the OS must not purge them).
    public var photosDirectory: URL { root.appending(path: "Photos", directoryHint: .isDirectory) }
    /// The wallpaper thumbnail shown on the Theme Sync screen.
    public var wallpaperThumbnailURL: URL { root.appending(path: "wallpaper.jpg") }

    public func url(for fileName: String) -> URL { photosDirectory.appending(path: fileName) }

    /// Downsampled mood-board tiles (A-06), one file per photo per layout.
    public var moodBoardDirectory: URL { root.appending(path: "MoodBoard", directoryHint: .isDirectory) }

    public func moodBoardURL(for fileName: String) -> URL { moodBoardDirectory.appending(path: fileName) }
}

/// Widget sizes in points, from Apple's Human Interface Guidelines widget size table (portrait).
/// Photos are downsampled to these × screen scale at import, so the widget never resizes an image.
public enum PhotoWidgetSize {
    struct Row {
        let screen: CGSize
        let small: CGSize
        let medium: CGSize
        let large: CGSize
    }

    static let table: [Row] = [
        Row(screen: CGSize(width: 440, height: 956), small: CGSize(width: 170, height: 170),
            medium: CGSize(width: 364, height: 170), large: CGSize(width: 364, height: 382)),
        Row(screen: CGSize(width: 430, height: 932), small: CGSize(width: 170, height: 170),
            medium: CGSize(width: 364, height: 170), large: CGSize(width: 364, height: 382)),
        Row(screen: CGSize(width: 428, height: 926), small: CGSize(width: 170, height: 170),
            medium: CGSize(width: 364, height: 170), large: CGSize(width: 364, height: 382)),
        Row(screen: CGSize(width: 414, height: 896), small: CGSize(width: 169, height: 169),
            medium: CGSize(width: 360, height: 169), large: CGSize(width: 360, height: 379)),
        Row(screen: CGSize(width: 414, height: 736), small: CGSize(width: 159, height: 159),
            medium: CGSize(width: 348, height: 157), large: CGSize(width: 348, height: 357)),
        Row(screen: CGSize(width: 393, height: 852), small: CGSize(width: 158, height: 158),
            medium: CGSize(width: 338, height: 158), large: CGSize(width: 338, height: 354)),
        Row(screen: CGSize(width: 390, height: 844), small: CGSize(width: 158, height: 158),
            medium: CGSize(width: 338, height: 158), large: CGSize(width: 338, height: 354)),
        Row(screen: CGSize(width: 375, height: 812), small: CGSize(width: 155, height: 155),
            medium: CGSize(width: 329, height: 155), large: CGSize(width: 329, height: 345)),
        Row(screen: CGSize(width: 360, height: 780), small: CGSize(width: 155, height: 155),
            medium: CGSize(width: 329, height: 155), large: CGSize(width: 329, height: 345)),
        Row(screen: CGSize(width: 375, height: 667), small: CGSize(width: 148, height: 148),
            medium: CGSize(width: 321, height: 148), large: CGSize(width: 321, height: 324)),
        Row(screen: CGSize(width: 320, height: 568), small: CGSize(width: 141, height: 141),
            medium: CGSize(width: 292, height: 141), large: CGSize(width: 292, height: 311))
    ]

    /// Point size of the widget slot on a screen of `screen` points (portrait or landscape).
    ///
    /// Unknown screens (new models, iPad) use the smallest listed screen at least as large in both
    /// directions, or the largest row: a slightly larger image is cropped by `scaledToFill`, never upscaled.
    public static func points(for slot: PhotoSlot, screen: CGSize) -> CGSize {
        let portrait = CGSize(width: min(screen.width, screen.height), height: max(screen.width, screen.height))
        let row = table.first { $0.screen == portrait }
            ?? table.filter { $0.screen.width >= portrait.width && $0.screen.height >= portrait.height }
                .min { $0.screen.width * $0.screen.height < $1.screen.width * $1.screen.height }
            ?? table[0]
        switch slot {
        case .small: return row.small
        case .medium: return row.medium
        case .large: return row.large
        }
    }

    public static func pixels(for slot: PhotoSlot, screen: CGSize, scale: CGFloat) -> PixelSize {
        PixelSize(points: points(for: slot, screen: screen), scale: scale)
    }
}
