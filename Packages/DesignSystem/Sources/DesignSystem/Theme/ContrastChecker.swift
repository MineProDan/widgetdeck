import CoreKit
import Foundation

/// WCAG 2.x contrast math. Used to keep user palettes (Theme Sync) legible.
public enum ContrastChecker {
    /// Required ratio by text size.
    public enum TextSize: Sendable {
        /// Body text: 4.5:1 (WCAG AA).
        case body
        /// Large text (≥ 18 pt, or ≥ 14 pt bold) and large numerals/graphics: 3:1.
        case large

        public var minimumRatio: Double {
            switch self {
            case .body: 4.5
            case .large: 3.0
            }
        }
    }

    /// Contrast ratio between two colors, 1...21. Translucent foregrounds are composited over the background.
    public static func ratio(_ foreground: RGBAColor, _ background: RGBAColor) -> Double {
        let opaqueBackground = background.composited(over: .white)
        let first = foreground.composited(over: opaqueBackground).relativeLuminance
        let second = opaqueBackground.relativeLuminance
        let (lighter, darker) = first > second ? (first, second) : (second, first)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func meets(_ foreground: RGBAColor, on background: RGBAColor, size: TextSize = .body) -> Bool {
        ratio(foreground, background) >= size.minimumRatio
    }

    /// Black or white, whichever contrasts more with `background`.
    public static func bestTextColor(on background: RGBAColor) -> RGBAColor {
        ratio(.black, background) >= ratio(.white, background) ? .black : .white
    }

    /// Returns `foreground` if it already meets `size`; otherwise nudges it toward black or white
    /// (keeping its hue as long as possible) until it does. Falls back to pure black/white.
    public static func ensureContrast(_ foreground: RGBAColor, on background: RGBAColor, size: TextSize = .body) -> RGBAColor {
        if meets(foreground, on: background, size: size) { return foreground }
        let target = bestTextColor(on: background)
        for step in 1...20 {
            let candidate = foreground.mixed(with: target, amount: Double(step) * 0.05)
            if meets(candidate, on: background, size: size) { return candidate }
        }
        return target
    }
}

extension RGBAColor {
    /// Linear interpolation in sRGB; `amount` 0 = self, 1 = other.
    public func mixed(with other: RGBAColor, amount: Double) -> RGBAColor {
        let t = min(max(amount, 0), 1)
        return RGBAColor(red: red + (other.red - red) * t, green: green + (other.green - green) * t,
                         blue: blue + (other.blue - blue) * t, alpha: alpha + (other.alpha - alpha) * t)
    }

    /// Alpha-composites this color over an opaque `background`.
    public func composited(over background: RGBAColor) -> RGBAColor {
        guard alpha < 1 else { return self }
        return RGBAColor(red: red * alpha + background.red * (1 - alpha),
                         green: green * alpha + background.green * (1 - alpha),
                         blue: blue * alpha + background.blue * (1 - alpha))
    }

    /// Whether the color reads as dark (drives light-vs-dark defaults for custom themes).
    public var isDark: Bool { relativeLuminance < 0.18 }
}
