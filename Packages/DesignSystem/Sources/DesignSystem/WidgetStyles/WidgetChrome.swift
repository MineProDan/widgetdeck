import CoreKit
import SwiftUI
import WidgetKit

extension WidgetFamilyKind {
    /// Maps WidgetKit's family to the Codable CoreKit mirror.
    public init(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: self = .systemSmall
        case .systemMedium: self = .systemMedium
        case .systemLarge: self = .systemLarge
        case .systemExtraLarge, .systemExtraLargePortrait: self = .systemExtraLarge
        case .accessoryCircular: self = .accessoryCircular
        case .accessoryRectangular: self = .accessoryRectangular
        case .accessoryInline: self = .accessoryInline
        @unknown default: self = .systemSmall
        }
    }
}

/// Shared chrome for every widget family: theme background via `containerBackground`, standard
/// insets, and rendering-mode handling. Accessory families get no custom background (the system
/// draws the Lock Screen material).
public struct WidgetChrome: ViewModifier {
    let theme: DSTheme
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
            .environment(\.dsTheme, theme)
            .fontDesign(theme.fontDesign)
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var background: some View {
        let palette = theme.palette(for: colorScheme)
        if WidgetFamilyKind(family).isAccessory {
            AccessoryWidgetBackground()
        } else if let gradient = theme.gradient, DSRenderingMode(renderingMode).usesThemeColors {
            ThemeBackground.gradient(gradient).opacity(theme.opacity)
        } else {
            palette.surfaceBase.color.opacity(theme.opacity)
        }
    }
}

extension View {
    /// Applies the shared widget background and theme. Use on the root of every widget view.
    public func widgetChrome(_ theme: DSTheme = .standard) -> some View {
        modifier(WidgetChrome(theme: theme))
    }
}

/// "updated 12m ago": shown only when a snapshot is older than 2 h (docs/plan/06 §2.1).
public struct WidgetStaleLabel: View {
    private let generatedAt: Date
    private let now: Date

    public init(generatedAt: Date, now: Date) {
        self.generatedAt = generatedAt
        self.now = now
    }

    public var body: some View {
        if now.timeIntervalSince(generatedAt) > 2 * 60 * 60 {
            Text("updated \(generatedAt, style: .relative) ago")
                .font(.caption2)
                .lineLimit(1)
                .dsForeground(.secondary)
        }
    }
}

/// Graceful absence: "—" plus a hint ("Open app to connect calendar"). Never a blank widget.
public struct WidgetUnavailableView: View {
    private let title: String
    private let hint: String
    private let systemImage: String
    @Environment(\.widgetFamily) private var family

    public init(_ title: String, hint: String, systemImage: String) {
        self.title = title
        self.hint = hint
        self.systemImage = systemImage
    }

    public var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(title) —", systemImage: systemImage)
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: systemImage)
                Text("—").font(.headline)
            }
            .accessibilityLabel("\(title) unavailable. \(hint)")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label(title, systemImage: systemImage).font(.headline)
                Text(hint).font(.caption).lineLimit(2)
            }
        default:
            VStack(alignment: .leading, spacing: Space.xxs) {
                Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold)).dsForeground(.secondary)
                Spacer(minLength: 0)
                Text("—").font(.largeTitle.weight(.semibold)).dsForeground(.primary)
                Text(hint).font(.caption).lineLimit(3).dsForeground(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
