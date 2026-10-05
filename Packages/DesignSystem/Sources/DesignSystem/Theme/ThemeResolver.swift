import CoreKit
import Foundation

/// Turns a user `Theme` (CoreKit model, possibly from Theme Sync) into a legible `DSTheme`.
///
/// Only the **semantic** layer changes. Missing roles fall back to the defaults, and text colors
/// are nudged until they meet WCAG (4.5:1 body, 3:1 large). Each fix-up is reported in
/// `DSTheme.contrastWarnings` so the editor can tell the user.
public enum ThemeResolver {
    public static func resolve(_ theme: Theme) -> DSTheme {
        var resolved = DSTheme(cornerStyle: theme.cornerStyle, font: theme.font, gradient: theme.gradient, blur: theme.blur,
                               opacity: theme.opacity, borderWidth: theme.borderWidth, borderColor: theme.borderColor)
        guard !theme.palette.isEmpty else { return resolved }

        var warnings: [String] = []
        // A custom palette has a fixed look, so it is used for both light and dark appearance,
        // with defaults for missing roles taken from whichever base matches its background.
        let background = theme[.background] ?? theme[.surface] ?? SemanticPalette.light.surfaceBase
        let base: SemanticPalette = background.isDark ? .dark : .light
        let surface = theme[.surface] ?? background.mixed(with: base.textPrimary, amount: 0.06)
        let accent = theme[.accent] ?? theme[.primary] ?? base.accentPrimary

        let requestedText = theme[.textOnBackground] ?? base.textPrimary
        // Text must be readable on both the background and elevated surfaces.
        var textPrimary = ContrastChecker.ensureContrast(requestedText, on: background)
        textPrimary = ContrastChecker.ensureContrast(textPrimary, on: surface)
        if textPrimary != requestedText, theme[.textOnBackground] != nil {
            warnings.append("Text color adjusted for readability (WCAG 4.5:1).")
        }

        let textSecondary = ContrastChecker.ensureContrast(textPrimary.mixed(with: background, amount: 0.3), on: surface)

        let requestedOnAccent = theme[.textOnAccent] ?? ContrastChecker.bestTextColor(on: accent)
        let onAccent = ContrastChecker.ensureContrast(requestedOnAccent, on: accent)
        if onAccent != requestedOnAccent { warnings.append("Button text color adjusted for readability.") }

        // Accent used as a large graphic (gauges, icons) needs 3:1 against the background.
        let accentOnBackground = ContrastChecker.ensureContrast(accent, on: background, size: .large)
        if accentOnBackground != accent { warnings.append("Accent color darkened/lightened to stand out from the background.") }

        let palette = SemanticPalette(
            surfaceBase: background, surfaceElevated: surface, textPrimary: textPrimary, textSecondary: textSecondary,
            accentPrimary: accentOnBackground, onAccent: onAccent,
            border: theme.borderColor ?? background.mixed(with: textPrimary, amount: 0.2),
            stateSuccess: ContrastChecker.ensureContrast(base.stateSuccess, on: background, size: .large),
            stateWarning: ContrastChecker.ensureContrast(base.stateWarning, on: background, size: .large),
            stateError: ContrastChecker.ensureContrast(base.stateError, on: background, size: .large)
        )
        resolved.light = palette
        resolved.dark = palette
        resolved.contrastWarnings = warnings
        return resolved
    }
}
