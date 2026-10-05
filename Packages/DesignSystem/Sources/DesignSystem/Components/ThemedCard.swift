import CoreKit
import SwiftUI

/// The base surface for every card in the app. Background follows the theme (solid or gradient),
/// with an optional border. Respects Reduce Transparency and Increase Contrast.
public struct ThemedCard<Content: View>: View {
    public enum Style: Sendable {
        /// Elevated surface color.
        case elevated
        /// Theme gradient if the theme has one, otherwise elevated.
        case gradient
        /// Translucent material (falls back to elevated with Reduce Transparency).
        case material
    }

    private let style: Style
    private let padding: CGFloat
    private let content: Content

    @Environment(\.dsTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @SemanticColors private var colors

    public init(style: Style = .elevated, padding: CGFloat = ComponentTokens.Card.padding, @ViewBuilder content: () -> Content) {
        self.style = style
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { background(shape) }
            .overlay {
                if borderWidth > 0 {
                    shape.strokeBorder((theme.borderColor ?? colors.border).color, lineWidth: borderWidth)
                }
            }
            .contentShape(shape)
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? max(ComponentTokens.Card.borderWidth, theme.borderWidth) : theme.borderWidth
    }

    @ViewBuilder
    private func background(_ shape: RoundedRectangle) -> some View {
        switch style {
        case .gradient:
            if let gradient = theme.gradient {
                shape.fill(ThemeBackground.gradient(gradient))
            } else {
                shape.fill(colors.surfaceElevated.color)
            }
        case .material where !reduceTransparency:
            shape.fill(.regularMaterial)
        default:
            shape.fill(colors.surfaceElevated.color)
        }
    }
}

/// Theme background helpers shared by cards and widget chrome.
public enum ThemeBackground {
    public static func gradient(_ gradient: Theme.Gradient) -> LinearGradient {
        let radians = gradient.angle * .pi / 180
        let dx = cos(radians) / 2
        let dy = sin(radians) / 2
        return LinearGradient(colors: gradient.colors.map(\.color),
                              startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                              endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

#Preview {
    VStack {
        ThemedCard { Text("Elevated card").dsForeground(.primary) }
        ThemedCard(style: .material) { Text("Material card").dsForeground(.secondary) }
    }
    .padding()
}
