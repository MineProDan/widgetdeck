import SwiftUI

/// Full-width primary action: Ink fill, 17 pt semibold Label Ivory text, 54 pt, radius 14.
/// Focus ring: 2 pt Ink outline offset 3 pt.
public struct WXPrimaryButtonStyle: ButtonStyle {
    private let height: CGFloat

    public init(height: CGFloat = 54) {
        self.height = height
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WXFont.body(17, weight: .semibold))
            .foregroundStyle(WXColor.labelIvory)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(WXColor.ink, in: RoundedRectangle(cornerRadius: WXRadius.chip, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(RoundedRectangle(cornerRadius: WXRadius.chip, style: .continuous))
    }
}

/// Inline pill action: Ink fill, 15 pt semibold, 44 pt tall, radius 22, 16–18 pt side padding.
public struct WXPillButtonStyle: ButtonStyle {
    private let horizontalPadding: CGFloat

    public init(horizontalPadding: CGFloat = 16) {
        self.horizontalPadding = horizontalPadding
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WXFont.body(15, weight: .semibold))
            .foregroundStyle(WXColor.labelIvory)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: 44)
            .background(WXColor.ink, in: Capsule(style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule(style: .continuous))
    }
}

/// `Button("Use Soft Coral") { … }.buttonStyle(.wxPrimary)`
public struct WXPrimaryButton: View {
    private let title: String
    private let height: CGFloat
    private let action: () -> Void

    public init(_ title: String, height: CGFloat = 54, action: @escaping () -> Void) {
        self.title = title
        self.height = height
        self.action = action
    }

    public var body: some View {
        Button(title, action: action).buttonStyle(WXPrimaryButtonStyle(height: height))
    }
}

/// `WXPillButton("Add") { … }`
public struct WXPillButton: View {
    private let title: String
    private let horizontalPadding: CGFloat
    private let action: () -> Void

    public init(_ title: String, horizontalPadding: CGFloat = 16, action: @escaping () -> Void) {
        self.title = title
        self.horizontalPadding = horizontalPadding
        self.action = action
    }

    public var body: some View {
        Button(title, action: action).buttonStyle(WXPillButtonStyle(horizontalPadding: horizontalPadding))
    }
}

extension ButtonStyle where Self == WXPrimaryButtonStyle {
    public static var wxPrimary: WXPrimaryButtonStyle { WXPrimaryButtonStyle() }
}

extension ButtonStyle where Self == WXPillButtonStyle {
    public static var wxPill: WXPillButtonStyle { WXPillButtonStyle() }
}

#Preview("Buttons") {
    VStack(spacing: 16) {
        WXPrimaryButton("Use Soft Coral") {}
        HStack { WXPillButton("Add") {}; WXPillButton("Start", horizontalPadding: 18) {} }
    }
    .padding(24)
    .background(WXColor.paperIvory)
}
