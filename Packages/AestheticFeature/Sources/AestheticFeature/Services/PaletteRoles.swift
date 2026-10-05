import AestheticFeatureWidgetKit
import CoreKit
import DesignSystem
import Foundation

/// Hue (0…360), saturation and brightness (0…1) of an sRGB colour.
public struct HSB: Hashable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var brightness: Double

    public init(_ color: RGBAColor) {
        let maxC = max(color.red, color.green, color.blue)
        let minC = min(color.red, color.green, color.blue)
        let delta = maxC - minC
        brightness = maxC
        saturation = maxC == 0 ? 0 : delta / maxC
        guard delta > 0 else { hue = 0; return }
        var h: Double
        if maxC == color.red {
            h = (color.green - color.blue) / delta
        } else if maxC == color.green {
            h = (color.blue - color.red) / delta + 2
        } else {
            h = (color.red - color.green) / delta + 4
        }
        h *= 60
        hue = h < 0 ? h + 360 : h
    }
}

/// A named colour with its Theme Sync role.
public struct NamedColor: Hashable, Sendable {
    public var name: String
    public var color: RGBAColor
}

/// Theme Sync step 2: the wallpaper's five colours in their roles, contrast-fixed and named.
public struct ExtractedPalette: Hashable, Sendable {
    public var surface: NamedColor
    public var background: NamedColor
    public var accent: NamedColor
    public var primary: NamedColor
    /// The darkest paint, used for text.
    public var text: NamedColor
    /// Text colour after WCAG fix-up against background and surface (4.5:1).
    public var textOnBackground: RGBAColor
    /// Text colour on the accent after fix-up (4.5:1).
    public var textOnAccent: RGBAColor
    /// Theme name ("Beach Hour").
    public var name: String

    /// Rows in the mockup's order: Surface, Background, Accent, Primary, Text.
    public var rows: [(role: String, color: NamedColor)] {
        [("Surface", surface), ("Background", background), ("Accent", accent), ("Primary", primary), ("Text", text)]
    }

    /// True when every text pair meets WCAG AA after fix-up (it always should; shown as "Contrast checked · AA").
    public var contrastChecked: Bool {
        ContrastChecker.meets(textOnBackground, on: background.color)
            && ContrastChecker.meets(textOnBackground, on: surface.color)
            && ContrastChecker.meets(textOnAccent, on: accent.color)
    }

    /// CoreKit theme (source `.wallpaper`). `id` lets re-syncs replace the previous wallpaper theme.
    public func theme(id: UUID, now: Date) -> Theme {
        Theme(id: id, name: name, source: .wallpaper, palette: [
            .background: background.color,
            .surface: surface.color,
            .primary: primary.color,
            .accent: accent.color,
            .textOnBackground: textOnBackground,
            .textOnAccent: textOnAccent
        ], updatedAt: now)
    }

    public func snapshot(now: Date) -> PaletteSnapshot {
        PaletteSnapshot(name: name,
                        swatches: rows.map { PaletteSwatch(role: $0.role, name: $0.color.name, color: $0.color.color) },
                        contrastChecked: contrastChecked, generatedAt: now)
    }

    /// Rebuilds the palette from a stored snapshot (so the screen shows the applied theme on launch).
    public init?(snapshot: PaletteSnapshot) {
        guard snapshot.swatches.count == 5 else { return nil }
        // Hex-round like a decoded snapshot, so a palette restored on launch equals the applied one.
        let named = snapshot.swatches.map { NamedColor(name: $0.name, color: RGBAColor(hex: $0.color.hexString) ?? $0.color) }
        self.init(surface: named[0], background: named[1], accent: named[2], primary: named[3], text: named[4],
                  name: snapshot.name)
    }

    init(surface: NamedColor, background: NamedColor, accent: NamedColor, primary: NamedColor, text: NamedColor, name: String) {
        self.surface = surface
        self.background = background
        self.accent = accent
        self.primary = primary
        self.text = text
        self.name = name
        let onBackground = ContrastChecker.ensureContrast(text.color, on: background.color)
        textOnBackground = ContrastChecker.ensureContrast(onBackground, on: surface.color)
        textOnAccent = ContrastChecker.ensureContrast(surface.color, on: accent.color)
    }
}

/// Assigns roles from brightness and saturation (HSB), then names each paint and the theme.
public enum RoleAssigner {
    /// - Text: the darkest colour.
    /// - Accent: the most vivid of the rest (saturation × brightness), so a sun or a flower wins.
    /// - Surface / Background / Primary: the remaining three, lightest to darkest.
    public static func assign(_ clusters: [ColorCluster]) -> ExtractedPalette? {
        guard clusters.count == 5 else { return nil }
        var rest = clusters.map(\.color)
        let text = rest.remove(at: rest.indices.min { rest[$0].relativeLuminance < rest[$1].relativeLuminance }!)
        let accent = rest.remove(at: rest.indices.max { vividness(rest[$0]) < vividness(rest[$1]) }!)
        let lightest = rest.sorted { $0.relativeLuminance > $1.relativeLuminance }
        let named = PaintNamer.names(for: [lightest[0], lightest[1], accent, lightest[2], text])
        return ExtractedPalette(
            surface: NamedColor(name: named[0], color: lightest[0]),
            background: NamedColor(name: named[1], color: lightest[1]),
            accent: NamedColor(name: named[2], color: accent),
            primary: NamedColor(name: named[3], color: lightest[2]),
            text: NamedColor(name: named[4], color: text),
            name: ThemeNamer.name(accent: accent, background: lightest[1])
        )
    }

    static func vividness(_ color: RGBAColor) -> Double {
        let hsb = HSB(color)
        return hsb.saturation * hsb.brightness
    }
}

/// Nearest-paint names (CIE Lab distance) from a fixed list that includes the mockup's paints.
public enum PaintNamer {
    static let paints: [(String, String)] = [
        ("Shell", "#F6DDB2"), ("Dune", "#F2CC8F"), ("Coral Hour", "#E07A5F"), ("Evening Sea", "#5B6C8F"),
        ("Deep Tide", "#3D405B"), ("Sage Noon", "#81B29A"), ("Plum Dusk", "#6D597A"), ("Paper", "#F7F3EA"),
        ("Chalk", "#FFFFFF"), ("Ink", "#22232E"), ("Night", "#101218"), ("Moss", "#4C7A62"), ("Clay", "#B2492F"),
        ("Blush", "#FBE3DC"), ("Rose", "#F4C1B4"), ("Lilac", "#B9C6FF"), ("Periwinkle", "#8E9BFF"),
        ("Oak", "#A47E5B"), ("Walnut", "#6B4A36"), ("Fog", "#D9D5CC"), ("Stone", "#A9A49A"), ("Slate", "#5E6180"),
        ("Pine", "#2F4A3A"), ("Sky", "#9CC3E6"), ("Harbour", "#2E5E8C"), ("Lemon", "#F4E27A"), ("Mustard", "#D9A93B"),
        ("Tangerine", "#F29A4A"), ("Berry", "#8E3B5B"), ("Olive", "#7A7A3A"), ("Mint", "#CDEBD8"), ("Lavender", "#E2D9E7")
    ].map { ($0.0, $0.1) }

    static let paintColors: [(name: String, lab: SIMD3<Double>)] = paints.map { ($0.0, lab(RGBAColor(hex: $0.1)!)) }

    public static func name(for color: RGBAColor) -> String {
        let target = lab(color)
        return paintColors.min { distance($0.lab, target) < distance($1.lab, target) }!.name
    }

    /// Names in order, never repeating one: a later colour takes its next-nearest paint.
    public static func names(for colors: [RGBAColor]) -> [String] {
        var used = Set<String>()
        return colors.map { color in
            let target = lab(color)
            let ranked = paintColors.sorted { distance($0.lab, target) < distance($1.lab, target) }
            let pick = ranked.first { !used.contains($0.name) }?.name ?? ranked[0].name
            used.insert(pick)
            return pick
        }
    }

    static func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return (d * d).sum()
    }

    /// sRGB → CIE Lab (D65).
    static func lab(_ color: RGBAColor) -> SIMD3<Double> {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = linear(color.red), g = linear(color.green), b = linear(color.blue)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0 }
        return SIMD3(116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }
}

/// Theme names from the accent's hue family and whether the background is light or dark.
public enum ThemeNamer {
    public static func name(accent: RGBAColor, background: RGBAColor) -> String {
        let hsb = HSB(accent)
        let light = !background.isDark
        if hsb.saturation < 0.15 { return light ? "Clean Slate" : "Night Ink" }
        switch hsb.hue {
        case 8..<50: return light ? "Beach Hour" : "Campfire"
        case 50..<70: return light ? "Lemon Day" : "Lantern"
        case 70..<170: return light ? "Moss Field" : "Forest Night"
        case 170..<250: return light ? "Harbour Blue" : "Deep Water"
        case 250..<320: return light ? "Lilac Hour" : "Plum Dusk"
        default: return light ? "Rose Garden" : "Ember"
        }
    }
}
