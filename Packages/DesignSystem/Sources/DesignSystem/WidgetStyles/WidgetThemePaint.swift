import CoreKit
import SwiftUI

/// Maps a Paint Chip section paint to the user's active theme for widgets. Dark paints (Deep Tide,
/// Plum Dusk) take the theme's primary colour; warm/light paints (Coral Hour, Sage Noon, Beach Sand)
/// take its accent. Any other colour, and every colour when no theme is active, is unchanged.
/// Only colour *fields* are recoloured: text never sits on a field (DESIGN.md), so contrast holds.
public enum WidgetThemePaint {
    public static func resolve(_ color: Color, theme: ActiveThemeSnapshot?) -> Color {
        guard let theme else { return color }
        switch color {
        case WXColor.deepTide, WXColor.plumDusk: return Color(rgba: theme.primary)
        case WXColor.coralHour, WXColor.sageNoon, WXColor.beachSand: return Color(rgba: theme.accent)
        default: return color
        }
    }
}

extension Color {
    init(rgba: RGBAColor) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
