import CoreKit
import CoreGraphics
import Foundation

/// A theme deck: one complete look for the app and every widget.
///
/// A deck keeps the Paint Chip anatomy (colour field, ivory band, punch hole, fan deck) and swaps
/// only the things a person feels first: the five section paints, the paper and band colours,
/// the display typeface, how round the corners are and the shape of the punch hole.
///
/// Rules every deck follows, so the rest of the system keeps working (and tests enforce them):
/// - Student, Wellness and Aesthetic paints are mid/light; Tech and Evening paints are dark, so
///   fill bars and mood keys drawn on them keep their contrast.
/// - Paper and band are light enough that ink text passes WCAG AA on them.
/// - Text still never sits on a colour field ("The Pure Field Rule").
///
/// The active deck is stored in the App Group defaults so the widget extension reads the same
/// one the app shows. `WXColor`, `WXFont`, `wxRounded` and `PaintChip` all resolve through
/// `WXDeck.current`, so feature code keeps using the section tokens it already uses.
public struct WXDeck: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// Paint-chip style code printed on the band ("WG 0606").
    public let code: String
    /// One line on how it feels, shown under the name in pickers.
    public let mood: String
    /// What it riffs on, shown in the Settings picker.
    public let inspiration: String

    /// Section paints as 0xRRGGBB.
    public let student: UInt32
    public let wellness: UInt32
    public let aesthetic: UInt32
    public let tech: UInt32
    public let evening: UInt32
    /// Paint names, in `WXSection` order: student, wellness, aesthetic, tech, evening.
    public let paintNames: [String]
    /// App ground and punch-hole fill.
    public let paper: UInt32
    /// Label bands and cards.
    public let band: UInt32

    /// PostScript name of the display face (bundled, see `WXFonts.fileNames`).
    public let displayFont: String
    /// Optional small-size optical instance (Bricolage only), used below 21 pt.
    public let displayFontSmall: String?
    /// Multiplier that evens out each face's apparent size (wide faces run smaller). Set so the
    /// app's real strings run at most ~15 % wider than in Bricolage (`DeckTests` checks this),
    /// because layouts and fixed-size widgets were built for Bricolage.
    public let displayScale: CGFloat
    /// Letter-spacing for display text, in em.
    public let displayTracking: CGFloat
    /// Draw "%" in the condensed label face instead of the display face. For faces whose own
    /// percent sign misreads at widget size (Silkscreen's reads as a "Z": "100Z").
    public let percentFromLabelFace: Bool

    public let punch: PunchShape
    /// Corner radii are multiplied by this, then capped at `cornerCap`.
    public let cornerScale: CGFloat
    public let cornerCap: CGFloat

    public init(id: String, name: String, code: String, mood: String, inspiration: String,
                student: UInt32, wellness: UInt32, aesthetic: UInt32, tech: UInt32, evening: UInt32,
                paintNames: [String], paper: UInt32, band: UInt32,
                displayFont: String, displayFontSmall: String? = nil, displayScale: CGFloat = 1,
                displayTracking: CGFloat = -0.02, percentFromLabelFace: Bool = false, punch: PunchShape,
                cornerScale: CGFloat = 1, cornerCap: CGFloat = 40) {
        self.id = id
        self.name = name
        self.code = code
        self.mood = mood
        self.inspiration = inspiration
        self.student = student
        self.wellness = wellness
        self.aesthetic = aesthetic
        self.tech = tech
        self.evening = evening
        self.paintNames = paintNames
        self.paper = paper
        self.band = band
        self.displayFont = displayFont
        self.displayFontSmall = displayFontSmall
        self.displayScale = displayScale
        self.displayTracking = displayTracking
        self.percentFromLabelFace = percentFromLabelFace
        self.punch = punch
        self.cornerScale = cornerScale
        self.cornerCap = cornerCap
    }

    /// Section paints in `WXSection` order.
    public var sectionPaints: [UInt32] { [student, wellness, aesthetic, tech, evening] }

    /// Four steps for a paint strip in a picker (Student, Wellness, Aesthetic, Tech).
    public var stripPaints: [UInt32] { [aesthetic, wellness, student, tech] }

    /// The PostScript name to use at `size` (pre-scale).
    public func displayFontName(for size: CGFloat) -> String {
        if let displayFontSmall, size < 21 { return displayFontSmall }
        return displayFont
    }

    /// A corner radius from `WXRadius` turned into this deck's radius. Zero stays zero.
    public func corner(_ radius: CGFloat) -> CGFloat {
        guard radius > 0 else { return 0 }
        return min(radius * cornerScale, cornerCap)
    }
}

// MARK: - Punch hole shapes

extension WXDeck {
    /// The die-cut mark at the top-left of every colour field.
    public enum PunchShape: String, Sendable, CaseIterable {
        case circle, star, drop, keyhole, flower, pixel, sparkle, diamond, moon, heart

        /// Non-circular marks are drawn a little larger so their silhouette reads at 9–12 pt.
        public var sizeMultiplier: CGFloat { self == .circle ? 1 : 1.4 }

        /// Spoken name for the Settings picker.
        public var displayName: String {
            switch self {
            case .circle: "Circle"
            case .star: "Star"
            case .drop: "Water drop"
            case .keyhole: "Keyhole"
            case .flower: "Flower"
            case .pixel: "Pixel"
            case .sparkle: "Sparkle"
            case .diamond: "Diamond"
            case .moon: "Moon"
            case .heart: "Heart"
            }
        }
    }
}

// MARK: - Catalogue

extension WXDeck {
    /// The original Paint Chip deck (DESIGN.md frontmatter). The default.
    public static let paintChip = WXDeck(
        id: "paint-chip", name: "Paint Chip", code: "WG 0914", mood: "The original: warm, matte, calm",
        inspiration: "Hardware-store paint swatches",
        student: 0xE07A5F, wellness: 0x81B29A, aesthetic: 0xF2CC8F, tech: 0x3D405B, evening: 0x6D597A,
        paintNames: ["Coral Hour", "Sage Noon", "Beach Sand", "Deep Tide", "Plum Dusk"],
        paper: 0xF7F3EA, band: 0xFFFDF8,
        displayFont: "BricolageGrotesqueDisplay-Bold", displayFontSmall: "BricolageGrotesque-Bold",
        punch: .circle)

    public static let saturdayCartoons = WXDeck(
        id: "saturday-cartoons", name: "Saturday Cartoons", code: "WG 0606", mood: "Bold, bouncy, loud in a good way",
        inspiration: "Saturday-morning cartoons and sticker sheets",
        student: 0xFF6B4A, wellness: 0x3FC380, aesthetic: 0xFFD23F, tech: 0x2B59C3, evening: 0x7B3FB8,
        paintNames: ["Hot Sauce", "Slime Time", "Cheese Puff", "Cobalt Cape", "Grape Soda"],
        paper: 0xFFF6E0, band: 0xFFFFFF,
        displayFont: "Fredoka-Bold", displayTracking: -0.01,
        punch: .star, cornerScale: 1.35, cornerCap: 28)

    public static let tidePool = WXDeck(
        id: "tide-pool", name: "Tide Pool", code: "WG 0808", mood: "Cool, salty, a little dreamy",
        inspiration: "Rock pools, surf wax and aquarium blues",
        student: 0xFF8C7A, wellness: 0x3FB8AF, aesthetic: 0xF3E3C3, tech: 0x0E3B5C, evening: 0x4A4E8C,
        paintNames: ["Reef Coral", "Lagoon", "Sand Dollar", "Deep Sea", "Jellyfish"],
        paper: 0xEEF6F5, band: 0xFBFEFD,
        displayFont: "Quicksand-Bold", displayTracking: -0.01,
        punch: .drop, cornerScale: 1.2, cornerCap: 26)

    public static let oldLibrary = WXDeck(
        id: "old-library", name: "Old Library", code: "WG 1891", mood: "Dark academia, candlelit, bookish",
        inspiration: "Leather spines, ink blots and late-night essays",
        student: 0x9E3B2F, wellness: 0x5E7052, aesthetic: 0xD9C3A0, tech: 0x2F2A26, evening: 0x4A3550,
        paintNames: ["Oxblood", "Ivy", "Parchment", "Walnut Ink", "Aubergine"],
        paper: 0xF2EBDD, band: 0xFBF7EE,
        displayFont: "PlayfairDisplay-Bold", displayTracking: -0.01,
        punch: .keyhole, cornerScale: 0.5, cornerCap: 8)

    public static let matchaCafe = WXDeck(
        id: "matcha-cafe", name: "Matcha Café", code: "WG 0730", mood: "Soft, sweet, slow mornings",
        inspiration: "Café menus, matcha lattes and strawberry milk",
        student: 0xE8A0A6, wellness: 0x8DB36A, aesthetic: 0xEADBC4, tech: 0x5B4636, evening: 0x7D5A6E,
        paintNames: ["Strawberry Milk", "Matcha", "Oat Latte", "Hojicha", "Red Bean"],
        paper: 0xF6F1E7, band: 0xFFFDF9,
        displayFont: "YoungSerif-Regular", displayScale: 0.94,
        punch: .flower, cornerScale: 1.15, cornerCap: 24)

    public static let pocketArcade = WXDeck(
        id: "pocket-arcade", name: "Pocket Arcade", code: "WG 0089", mood: "Pixel-sharp, high-score energy",
        inspiration: "Handheld consoles, 8-bit sprites and arcade cabinets",
        student: 0xE2504B, wellness: 0x6BAA3C, aesthetic: 0xC4CF8A, tech: 0x2A2D4F, evening: 0x6A3C8E,
        paintNames: ["Power-Up", "Extra Life", "Pea Screen", "Cartridge", "Boss Level"],
        paper: 0xECEDE4, band: 0xF8F8F2,
        displayFont: "Silkscreen-Bold", displayScale: 0.66, displayTracking: 0, percentFromLabelFace: true,
        punch: .pixel, cornerScale: 0.3, cornerCap: 4)

    public static let butterflyClip = WXDeck(
        id: "butterfly-clip", name: "Butterfly Clip", code: "WG 2001", mood: "Y2K, gel-pen bright, playful",
        inspiration: "Butterfly clips, gel pens and flip phones",
        student: 0xFF7EB6, wellness: 0x7FD8BE, aesthetic: 0xC9DBFF, tech: 0x4A40A0, evening: 0x8E4FB5,
        paintNames: ["Bubblegum", "Gel Pen Mint", "Baby Blue", "Flip Phone", "Glitter Grape"],
        paper: 0xFBF2FA, band: 0xFFFFFF,
        displayFont: "Unbounded-Bold", displayScale: 0.76, displayTracking: 0,
        punch: .sparkle, cornerScale: 1.25, cornerCap: 26)

    public static let gameDay = WXDeck(
        id: "game-day", name: "Game Day", code: "WG 1023", mood: "Varsity, loud, team spirit",
        inspiration: "Varsity jackets, pennants and Friday-night lights",
        student: 0xB8322F, wellness: 0x2F7D4F, aesthetic: 0xE9C46A, tech: 0x1F2F4E, evening: 0x4B2E5C,
        paintNames: ["Varsity Red", "Turf", "Trophy Gold", "Navy Stripe", "Night Game"],
        paper: 0xF4F1E8, band: 0xFFFEFA,
        displayFont: "Graduate-Regular", displayScale: 0.82, displayTracking: 0,
        punch: .diamond, cornerScale: 0.45, cornerCap: 7)

    public static let cosmicSleepover = WXDeck(
        id: "cosmic-sleepover", name: "Cosmic Sleepover", code: "WG 1111", mood: "Starry, cozy, a bit witchy",
        inspiration: "Glow-in-the-dark ceiling stars and astrology apps",
        student: 0xF28C6B, wellness: 0x6CC5B0, aesthetic: 0xF6E7A8, tech: 0x1E1B4B, evening: 0x4B2B6F,
        paintNames: ["Mars Glow", "Aurora", "Starlight", "Deep Space", "Nebula"],
        paper: 0xF1EEF8, band: 0xFDFCFF,
        displayFont: "SpaceGrotesk-Bold",
        punch: .moon)

    public static let lofiStudy = WXDeck(
        id: "lofi-study", name: "Lo-fi Study", code: "WG 0230", mood: "Rainy window, lamp on, beats playing",
        inspiration: "Lo-fi study streams and rainy desk setups",
        student: 0xE39B6C, wellness: 0x8FA89B, aesthetic: 0xE8D9C8, tech: 0x34364F, evening: 0x6B5B8C,
        paintNames: ["Desk Lamp", "Rainy Sage", "Knit Sweater", "Night Window", "Lo-fi Violet"],
        paper: 0xF3EFEA, band: 0xFFFDFA,
        displayFont: "Caveat-Bold", displayScale: 1.15, displayTracking: 0,
        punch: .heart)

    /// Every deck, in picker order. The first is the default.
    public static let all: [WXDeck] = [
        paintChip, saturdayCartoons, tidePool, oldLibrary, matchaCafe,
        pocketArcade, butterflyClip, gameDay, cosmicSleepover, lofiStudy,
    ]

    private static let byID: [String: WXDeck] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// The deck with `id`, or the default when the id is unknown (e.g. a deck removed in an update).
    public static func deck(id: String?) -> WXDeck {
        id.flatMap { byID[$0] } ?? paintChip
    }
}

// MARK: - Active deck

extension WXDeck {
    /// App Group defaults key that holds the active deck's `id`.
    public static let storageKey = "wx.deck"

    /// The App Group suite, so the widget extension reads the deck the app picked.
    private static let store = DeckDefaults(UserDefaults(suiteName: AppIdentifiers.appGroup))

    /// The deck the app and widgets draw with right now.
    public static var current: WXDeck { current(in: store.defaults) }

    /// The deck stored in `defaults` (the default deck when none is stored).
    public static func current(in defaults: UserDefaults?) -> WXDeck {
        deck(id: defaults?.string(forKey: storageKey))
    }

    /// Makes `deck` the active deck. The app redraws its chrome and reloads widgets afterwards
    /// (see `AppEnvironment.applyDeck`).
    public static func select(_ deck: WXDeck) {
        select(deck, in: store.defaults)
    }

    /// Stores `deck` in `defaults` (tests pass their own suite).
    public static func select(_ deck: WXDeck, in defaults: UserDefaults?) {
        defaults?.set(deck.id, forKey: storageKey)
    }
}

/// Holds the shared suite for a static. `UserDefaults` is thread-safe.
private final class DeckDefaults: @unchecked Sendable {
    let defaults: UserDefaults?

    init(_ defaults: UserDefaults?) {
        self.defaults = defaults
    }
}
