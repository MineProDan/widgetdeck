import SwiftUI
import WidgetKit

/// Semantic foreground roles that adapt to widget rendering modes.
public enum ForegroundRole: Sendable {
    case primary, secondary, accent, success, warning, error
}

/// How widget content must be drawn for the system's rendering mode.
///
/// - `fullColor`: Home Screen default; use theme colors.
/// - `accented` (iOS 18 tinted / iOS 26 clear): the system tints content. Use `.primary` /
///   `.secondary` hierarchy and mark the accent group with `widgetAccentable()`.
/// - `vibrant` (Lock Screen, StandBy night): monochrome; only opacity hierarchy survives.
public enum DSRenderingMode: Sendable, Equatable {
    case fullColor, accented, vibrant

    public init(_ mode: WidgetRenderingMode) {
        switch mode {
        case .accented: self = .accented
        case .vibrant: self = .vibrant
        default: self = .fullColor
        }
    }

    /// Whether theme colors (and custom backgrounds) should be drawn.
    public var usesThemeColors: Bool { self == .fullColor }
}

/// Applies a semantic foreground that respects the rendering mode.
struct AdaptiveForeground: ViewModifier {
    let role: ForegroundRole
    @Environment(\.widgetRenderingMode) private var renderingMode
    @SemanticColors private var colors

    func body(content: Content) -> some View {
        switch DSRenderingMode(renderingMode) {
        case .fullColor:
            content.foregroundStyle(color)
        case .accented:
            if role == .accent {
                content.foregroundStyle(.primary).widgetAccentable()
            } else {
                content.foregroundStyle(role == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
        case .vibrant:
            content.foregroundStyle(role == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }

    private var color: Color {
        switch role {
        case .primary: colors.textPrimary.color
        case .secondary: colors.textSecondary.color
        case .accent: colors.accentPrimary.color
        case .success: colors.stateSuccess.color
        case .warning: colors.stateWarning.color
        case .error: colors.stateError.color
        }
    }
}

extension View {
    /// Semantic, rendering-mode-aware foreground. Use this instead of hard-coded colors, in the
    /// app as well as in widgets (outside widgets the mode is always full color).
    public func dsForeground(_ role: ForegroundRole) -> some View {
        modifier(AdaptiveForeground(role: role))
    }
}
