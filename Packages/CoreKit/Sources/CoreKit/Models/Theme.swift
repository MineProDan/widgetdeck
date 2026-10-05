import Foundation

/// An sRGB color with components in 0...1. Codable as a `#RRGGBB` / `#RRGGBBAA` hex string.
public struct RGBAColor: Hashable, Sendable, Codable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clamped01
        self.green = green.clamped01
        self.blue = blue.clamped01
        self.alpha = alpha.clamped01
    }

    /// Parses `#RGB`, `#RRGGBB` or `#RRGGBBAA` (the `#` is optional).
    public init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        if string.count == 3 { string = string.map { "\($0)\($0)" }.joined() }
        guard string.count == 6 || string.count == 8, let value = UInt64(string, radix: 16) else { return nil }
        let hasAlpha = string.count == 8
        let r = hasAlpha ? (value >> 24) & 0xFF : (value >> 16) & 0xFF
        let g = hasAlpha ? (value >> 16) & 0xFF : (value >> 8) & 0xFF
        let b = hasAlpha ? (value >> 8) & 0xFF : value & 0xFF
        let a = hasAlpha ? value & 0xFF : 0xFF
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: Double(a) / 255)
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when not fully opaque.
    public var hexString: String {
        func byte(_ v: Double) -> String { String(format: "%02X", Int((v * 255).rounded())) }
        let base = "#" + byte(red) + byte(green) + byte(blue)
        return alpha < 1 ? base + byte(alpha) : base
    }

    public var description: String { hexString }

    /// WCAG 2.x relative luminance (0 = black, 1 = white). Alpha is ignored.
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = RGBAColor(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid hex color '\(string)'")
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

extension Double {
    var clamped01: Double { Swift.min(Swift.max(self, 0), 1) }
}

/// The role a palette color plays. DesignSystem maps roles onto its semantic tokens.
public enum ColorRole: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case background
    case surface
    case primary
    case accent
    case textOnBackground
    case textOnAccent
}

/// A user-facing theme: palette + style. Themes only ever swap the **semantic** design layer.
public struct Theme: Identifiable, Hashable, Codable, Sendable {
    public enum Source: String, Codable, Sendable {
        case preset, wallpaper, pack, community, shared
    }

    public enum CornerStyle: String, Codable, Sendable {
        case sharp, rounded, pill
    }

    public enum FontStyle: String, Codable, Sendable {
        case system, rounded, serif, monospaced
    }

    public struct Gradient: Hashable, Codable, Sendable {
        public var colors: [RGBAColor]
        /// Angle in degrees, 0 = leading→trailing, 90 = top→bottom.
        public var angle: Double
        public init(colors: [RGBAColor], angle: Double = 90) {
            self.colors = colors
            self.angle = angle
        }
    }

    public var id: UUID
    public var name: String
    public var source: Source
    /// Colors keyed by role. Missing roles fall back to the default theme in DesignSystem.
    public var palette: [ColorRole: RGBAColor]
    public var gradient: Gradient?
    public var font: FontStyle
    public var cornerStyle: CornerStyle
    /// Background blur radius in points (0 = none).
    public var blur: Double
    /// Background opacity, 0...1.
    public var opacity: Double
    public var borderWidth: Double
    public var borderColor: RGBAColor?
    /// Content pack the theme came from, used for premium gating.
    public var packID: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        source: Source = .preset,
        palette: [ColorRole: RGBAColor],
        gradient: Gradient? = nil,
        font: FontStyle = .system,
        cornerStyle: CornerStyle = .rounded,
        blur: Double = 0,
        opacity: Double = 1,
        borderWidth: Double = 0,
        borderColor: RGBAColor? = nil,
        packID: String? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.palette = palette
        self.gradient = gradient
        self.font = font
        self.cornerStyle = cornerStyle
        self.blur = max(0, blur)
        self.opacity = opacity.clamped01
        self.borderWidth = max(0, borderWidth)
        self.borderColor = borderColor
        self.packID = packID
        self.updatedAt = updatedAt
    }

    public subscript(role: ColorRole) -> RGBAColor? { palette[role] }

    /// The built-in default theme ("Sand"). Its semantic colors are defined in DesignSystem;
    /// an empty palette means "use the design-system defaults for light and dark mode".
    public static let system = Theme(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "System",
        palette: [:]
    )
}
