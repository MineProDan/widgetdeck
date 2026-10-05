import CoreKit
import SwiftUI

/// A resolved, render-ready theme: semantic palettes for light and dark plus style values.
public struct DSTheme: Hashable, Sendable {
    public var light: SemanticPalette
    public var dark: SemanticPalette
    public var cornerStyle: Theme.CornerStyle
    public var font: Theme.FontStyle
    public var gradient: Theme.Gradient?
    public var blur: Double
    public var opacity: Double
    public var borderWidth: Double
    public var borderColor: RGBAColor?
    /// Human-readable notes about contrast fix-ups, shown in the theme editor.
    public var contrastWarnings: [String]

    public init(light: SemanticPalette = .light, dark: SemanticPalette = .dark, cornerStyle: Theme.CornerStyle = .rounded,
                font: Theme.FontStyle = .system, gradient: Theme.Gradient? = nil, blur: Double = 0, opacity: Double = 1,
                borderWidth: Double = 0, borderColor: RGBAColor? = nil, contrastWarnings: [String] = []) {
        self.light = light
        self.dark = dark
        self.cornerStyle = cornerStyle
        self.font = font
        self.gradient = gradient
        self.blur = blur
        self.opacity = opacity
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.contrastWarnings = contrastWarnings
    }

    /// The default "Sand" theme.
    public static let standard = DSTheme()

    /// Semantic palette for the current appearance. Increased Contrast collapses secondary text
    /// into primary and strengthens borders.
    public func palette(for scheme: ColorScheme, increasedContrast: Bool = false) -> SemanticPalette {
        var palette = scheme == .dark ? dark : light
        if increasedContrast {
            palette.textSecondary = palette.textPrimary
            palette.border = palette.textSecondary
        }
        return palette
    }

    /// Corner radius for cards and widgets.
    public var cornerRadius: CGFloat {
        switch cornerStyle {
        case .sharp: Radius.sm / 2
        case .rounded: ComponentTokens.Card.cornerRadius
        case .pill: Radius.lg
        }
    }

    /// Font design matching the theme's font style.
    public var fontDesign: Font.Design {
        switch font {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}

extension EnvironmentValues {
    /// The active design-system theme. Set it once at the root (`.environment(\.dsTheme, …)`).
    @Entry public var dsTheme: DSTheme = .standard
}

/// Reads the semantic palette for the current theme, color scheme and contrast setting.
///
/// ```swift
/// @SemanticColors private var colors
/// Text("Hi").foregroundStyle(colors.textPrimary.color)
/// ```
@propertyWrapper
public struct SemanticColors: DynamicProperty {
    @Environment(\.dsTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    public init() {}

    public var wrappedValue: SemanticPalette {
        theme.palette(for: colorScheme, increasedContrast: contrast == .increased)
    }
}

extension RGBAColor {
    /// SwiftUI color in the sRGB space.
    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
