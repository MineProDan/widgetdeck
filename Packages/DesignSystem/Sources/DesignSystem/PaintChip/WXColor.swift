import CoreKit
import SwiftUI

/// Paint Chip colours (DESIGN.md frontmatter + the tints used in the approved mockup).
///
/// Colours are paint, not UI chrome: they do not change with light/dark mode. Use the section
/// mapping (`WXSection.color`) instead of picking a hue by hand, so "The Colour Is Law" holds.
public enum WXColor {
    // MARK: Section and evening colours
    /// Student and "next up" moments.
    public static let coralHour = Color(wxHex: 0xE07A5F)
    /// Wellness habits, midday Flow, positive completion fields.
    public static let sageNoon = Color(wxHex: 0x81B29A)
    /// Aesthetic and theme surfaces, the battery fill on ink.
    public static let beachSand = Color(wxHex: 0xF2CC8F)
    /// Tech chips, afternoon focus, heavier academic blocks.
    public static let deepTide = Color(wxHex: 0x3D405B)
    /// Evening and mood only.
    public static let plumDusk = Color(wxHex: 0x6D597A)

    // MARK: Neutrals
    /// App ground and punch-hole fill.
    public static let paperIvory = Color(wxHex: 0xF7F3EA)
    /// Chip label bands and card surfaces.
    public static let labelIvory = Color(wxHex: 0xFFFDF8)
    /// Quiet data fills on ink (memory bar), palette surfaces.
    public static let shell = Color(wxHex: 0xF6DDB2)
    /// Primary text, primary buttons, active tab.
    public static let ink = Color(wxHex: 0x22232E)
    /// Caps labels.
    public static let inkSecondary = Color(wxHex: 0x5B5D6B)
    /// Subtitles and body.
    public static let inkBody = Color(wxHex: 0x4A4C59)
    /// Inactive tabs, axis labels.
    public static let inkInactive = Color(wxHex: 0x6B6D7A)
    /// Hairlines, tab-bar top border, grid lines.
    public static let rule = Color(wxHex: 0xE4DED1)
    /// Links, urgent caps, the "now" line.
    public static let clayLink = Color(wxHex: 0xB2492F)
    /// Streaks and positive trends.
    public static let mossPositive = Color(wxHex: 0x4C7A62)

    // MARK: Control surfaces used in the mockup
    /// Segmented-control track (DESIGN.md `segmented-control`).
    public static let segmentTrack = Color(wxHex: 0xECE6DA)
    /// Inactive onboarding page dots (Main).
    public static let pageDotInactive = Color(wxHex: 0xCFC8BA)
    /// Unchecked "mark done" ring on list rows (Student · Due soon).
    public static let checkRing = Color(wxHex: 0x9A9CA8)
    /// Ground of the before/after compare well (ThemeSync).
    public static let compareGround = Color(wxHex: 0xEFEAE0)

    // MARK: Tint ramps
    /// Mood scale on paper, rough → great (Wellness history bars and mood keys).
    public static let moodTints: [Color] = [0xA99BB3, 0xBCAFC5, 0x9C88AA, 0x7E6A8C, 0x6D597A].map { Color(wxHex: $0) }
    /// Mood keys drawn on a Plum Dusk field (Mood widget), rough → great.
    public static let moodTintsOnPlum: [Color] = [0xA99BB3, 0xBCAFC5, 0xCFC4D6, 0xE2D9E7, 0xF4EFF6].map { Color(wxHex: $0) }

    /// Thermal-state paints, nominal → critical (Tech thermal strip).
    public static let thermal: [Color] = [sageNoon, beachSand, coralHour, clayLink]
}

/// Which colour a piece of UI belongs to. The colour means that section everywhere.
public enum WXSection: String, CaseIterable, Sendable, Identifiable {
    case student, wellness, aesthetic, tech, evening

    public var id: String { rawValue }

    /// Field colour for chips of this section.
    public var color: Color {
        switch self {
        case .student: WXColor.coralHour
        case .wellness: WXColor.sageNoon
        case .aesthetic: WXColor.beachSand
        case .tech: WXColor.deepTide
        case .evening: WXColor.plumDusk
        }
    }

    /// The paint name printed on a chip's label band ("Coral Hour · BIO 201").
    public var paintName: String {
        switch self {
        case .student: "Coral Hour"
        case .wellness: "Sage Noon"
        case .aesthetic: "Beach Sand"
        case .tech: "Deep Tide"
        case .evening: "Plum Dusk"
        }
    }

    public init(_ section: AppSection) {
        switch section {
        case .student: self = .student
        case .wellness: self = .wellness
        case .aesthetic: self = .aesthetic
        case .tech: self = .tech
        }
    }
}

/// A theme paint strip as shown in onboarding (Main) and theme pickers. These hues are
/// user-theme colours: "The Theme Stays in the Theme", so never use them in system chrome.
public struct WXThemePaint: Hashable, Sendable, Identifiable {
    public let name: String
    public let code: String
    public let mood: String
    /// Four steps, lightest first.
    public let steps: [UInt32]

    public var id: String { code }
    public var colors: [Color] { steps.map { Color(wxHex: $0) } }

    public init(name: String, code: String, mood: String, steps: [UInt32]) {
        self.name = name
        self.code = code
        self.mood = mood
        self.steps = steps
    }

    /// The six launch themes, in fan order (Main artboard).
    public static let launchThemes: [WXThemePaint] = [
        WXThemePaint(name: "Clean Slate", code: "WG 0101", mood: "Quiet, neutral, sharp", steps: [0xF1EEE8, 0xD9D5CC, 0xA9A49A, 0x2E2F36]),
        WXThemePaint(name: "Soft Coral", code: "WG 0914", mood: "Warm, calm, easy to read", steps: [0xFBE3DC, 0xF4C1B4, 0xE8947F, 0xC8604A]),
        WXThemePaint(name: "Library Oak", code: "WG 1776", mood: "Dark academia, bookish", steps: [0xD8C3A5, 0xA47E5B, 0x6B4A36, 0x3A2A22]),
        WXThemePaint(name: "Chrome Lilac", code: "WG 2000", mood: "Y2K, glossy, playful", steps: [0xE3E9FF, 0xB9C6FF, 0x8E9BFF, 0x5B5BD6]),
        WXThemePaint(name: "Night Ink", code: "WG 0404", mood: "Minimal tech, low light", steps: [0xD5D7E0, 0x9A9DB3, 0x5E6180, 0x2F3148]),
        WXThemePaint(name: "Moss Field", code: "WG 0521", mood: "Nature, grounded, soft", steps: [0xE1EEDF, 0xB5D3B2, 0x81B29A, 0x4C7A62])
    ]
}

extension Color {
    /// sRGB colour from a 0xRRGGBB literal.
    public init(wxHex hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
