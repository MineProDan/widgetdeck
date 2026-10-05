import SwiftUI

/// "Never a blank screen": an icon, a message and one clear action.
public struct EmptyState: View {
    private let title: String
    private let message: String
    private let systemImage: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(_ title: String, message: String, systemImage: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .dsForeground(.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .dsForeground(.primary)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .dsForeground(.secondary)
            if let actionTitle, let action {
                PrimaryButton(actionTitle, action: action)
                    .padding(.top, Space.xs)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: 420)
        .accessibilityElement(children: .contain)
    }
}

/// Filled accent button used for the one primary action on a screen.
public struct PrimaryButton: View {
    private let title: String
    private let action: () -> Void
    @Environment(\.dsTheme) private var theme
    @SemanticColors private var colors

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: ComponentTokens.Chip.minHeight)
                .padding(.horizontal, Space.md)
                .foregroundStyle(colors.onAccent.color)
                .background(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                    .fill(colors.accentPrimary.color))
        }
        .buttonStyle(.plain)
    }
}

/// Explains the *benefit* of a permission before the system prompt appears (docs/plan/06).
/// Call `onContinue` → `PermissionManager.request(_:)`. `onNotNow` must leave the feature usable.
public struct PermissionPrimer: View {
    private let title: String
    private let message: String
    private let systemImage: String
    private let bullets: [String]
    private let continueTitle: String
    private let onContinue: () -> Void
    private let onNotNow: () -> Void

    public init(title: String, message: String, systemImage: String, bullets: [String] = [],
                continueTitle: String = "Continue", onContinue: @escaping () -> Void, onNotNow: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.bullets = bullets
        self.continueTitle = continueTitle
        self.onContinue = onContinue
        self.onNotNow = onNotNow
    }

    public var body: some View {
        // Paint Chip styling (DESIGN.md): ink stroke icon, Bricolage headline, SF body, ink button, on paper.
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(WXColor.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).wxGrotesk(28)
                Text(message).wxBody(16)
            }
            if !bullets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(bullets, id: \.self) { bullet in
                        Label {
                            Text(bullet).wxBody(15, color: WXColor.ink)
                        } icon: {
                            Image(systemName: "checkmark").foregroundStyle(WXColor.mossPositive)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                WXPrimaryButton(continueTitle, action: onContinue)
                Button(action: onNotNow) {
                    Text("Not now").wxBody(15, color: WXColor.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(WXColor.paperIvory.ignoresSafeArea())
    }
}

/// Placeholder shimmer while content loads in-app. Static with Reduce Motion.
/// Widgets never show loaders: they render the last snapshot or a placeholder.
public struct ShimmerLoader: View {
    private let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SemanticColors private var colors
    @State private var phase: CGFloat = -1

    public init(cornerRadius: CGFloat = Radius.sm) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(colors.textSecondary.color.opacity(0.15))
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, colors.surfaceElevated.color.opacity(0.6), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.6)
                            .offset(x: phase * proxy.size.width)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
            .accessibilityLabel("Loading")
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            EmptyState("No classes yet", message: "Connect your calendar to see your schedule.",
                       systemImage: "calendar", actionTitle: "Connect calendar") {}
            PermissionPrimer(title: "See your classes", message: "We read your calendar on-device to find your classes.",
                             systemImage: "calendar.badge.clock", bullets: ["We never change your events", "Nothing is uploaded"],
                             onContinue: {}, onNotNow: {})
            ShimmerLoader().frame(height: 60)
        }
        .padding()
    }
}
