import SwiftUI

/// Corner radii (DESIGN.md `rounded`). Always draw with `.continuous` corners.
public enum WXRadius {
    /// Palette swatches, class blocks, thermal cells.
    public static let swatch: CGFloat = 8
    /// Chips in lists, primary buttons.
    public static let chip: CGFloat = 14
    /// Large cards (metric cards, hero chip).
    public static let card: CGFloat = 16
    /// Home-screen widgets (matches iOS).
    public static let widget: CGFloat = 22
    /// Pill buttons (44 pt tall).
    public static let pill: CGFloat = 22
    /// Deck chips and paint strips in a fan.
    public static let deckChip: CGFloat = 12
}

/// Spacing (DESIGN.md `spacing`).
public enum WXSpace {
    /// 6 pt: title → subtitle, tight stacks.
    public static let xs: CGFloat = 6
    /// 10 pt: gap between chips in a group.
    public static let sm: CGFloat = 10
    /// 14 pt: band padding, gaps in larger groups.
    public static let md: CGFloat = 14
    /// 24 pt: side gutter and gap between groups.
    public static let gutter: CGFloat = 24
}

/// A CSS-style box shadow layer: offset, blur and (negative) spread.
public struct WXShadowLayer: Hashable, Sendable {
    public var y: CGFloat
    public var blur: CGFloat
    public var spread: CGFloat
    public var opacity: Double

    public init(y: CGFloat, blur: CGFloat, spread: CGFloat = 0, opacity: Double) {
        self.y = y
        self.blur = blur
        self.spread = spread
        self.opacity = opacity
    }
}

/// Paper-like offset shadows (DESIGN.md "Shadow Vocabulary", .impeccable/design.json). All are
/// Ink (#22232E) at low opacity: a hairline contact shadow plus one soft drop.
public struct WXShadow: Hashable, Sendable {
    public var layers: [WXShadowLayer]

    public init(_ layers: [WXShadowLayer]) {
        self.layers = layers
    }

    /// `0 1px 2px .08, 0 10px 22px -12px .4`: chips and cards in the app.
    public static let chipRest = WXShadow([.init(y: 1, blur: 2, opacity: 0.08), .init(y: 10, blur: 22, spread: -12, opacity: 0.4)])
    /// `0 12px 30px -14px .45`: widgets over a wallpaper.
    public static let widgetOnWallpaper = WXShadow([.init(y: 12, blur: 30, spread: -14, opacity: 0.45)])
    /// `0 1px 2px .10, 0 14px 30px -12px .55`: the selected chip lifted out of a fan.
    public static let chipLifted = WXShadow([.init(y: 1, blur: 2, opacity: 0.10), .init(y: 14, blur: 30, spread: -12, opacity: 0.55)])
    /// Unselected strips in the onboarding fan (`… 0 14px 30px -12px .28`).
    public static let chipFanned = WXShadow([.init(y: 1, blur: 2, opacity: 0.10), .init(y: 14, blur: 30, spread: -12, opacity: 0.28)])
    /// The Home hero (Flow) card: `0 1px 2px .08, 0 18px 36px -16px .35`.
    public static let heroCard = WXShadow([.init(y: 1, blur: 2, opacity: 0.08), .init(y: 18, blur: 36, spread: -16, opacity: 0.35)])
    /// Metric cards (Tech): `0 1px 2px .08, 0 10px 22px -14px .4`.
    public static let metricCard = WXShadow([.init(y: 1, blur: 2, opacity: 0.08), .init(y: 10, blur: 22, spread: -14, opacity: 0.4)])
    /// Horizontal row chips (habits): `0 1px 2px .08, 0 8px 18px -12px .3`.
    public static let rowChip = WXShadow([.init(y: 1, blur: 2, opacity: 0.08), .init(y: 8, blur: 18, spread: -12, opacity: 0.3)])
    /// Suggestion/action chips: `0 1px 2px .08, 0 10px 24px -14px .3`.
    public static let actionChip = WXShadow([.init(y: 1, blur: 2, opacity: 0.08), .init(y: 10, blur: 24, spread: -14, opacity: 0.3)])
    /// Large action chips (breathe): `0 1px 2px .08, 0 10px 24px -14px .35`.
    public static let actionCard = WXShadow([.init(y: 1, blur: 2, opacity: 0.08), .init(y: 10, blur: 24, spread: -14, opacity: 0.35)])
    /// Class blocks in a week grid: `0 1px 2px .10, 0 6px 12px -8px .35`.
    public static let block = WXShadow([.init(y: 1, blur: 2, opacity: 0.10), .init(y: 6, blur: 12, spread: -8, opacity: 0.35)])
    /// Contact only (`0 1px 2px .08`): quiet list rows and info chips.
    public static let contact = WXShadow([.init(y: 1, blur: 2, opacity: 0.08)])
    /// Lightest contact (`0 1px 2px .06`): due-soon rows.
    public static let hairline = WXShadow([.init(y: 1, blur: 2, opacity: 0.06)])
    /// Preview chips in a compare well: `0 8px 18px -10px .4`.
    public static let preview = WXShadow([.init(y: 8, blur: 18, spread: -10, opacity: 0.4)])
    /// A picked photo (wallpaper thumbnail): `0 12px 26px -14px .5`.
    public static let photo = WXShadow([.init(y: 12, blur: 26, spread: -14, opacity: 0.5)])
    /// Selected segment: `0 1px 3px .15`.
    public static let segment = WXShadow([.init(y: 1, blur: 3, opacity: 0.15)])
}

/// Draws a `WXShadow` behind a rounded rectangle. CSS negative spread has no SwiftUI equivalent,
/// so each layer is an inset, offset, blurred copy of the shape (blur radius = CSS blur / 2,
/// the Gaussian sigma a browser uses), hidden under the opaque view in front of it.
struct WXShadowModifier: ViewModifier {
    let shadow: WXShadow
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let cornerRadius = WXDeck.current.corner(cornerRadius)
        return content.background {
            ZStack {
                ForEach(Array(shadow.layers.enumerated()), id: \.offset) { _, layer in
                    RoundedRectangle(cornerRadius: max(0, cornerRadius + layer.spread), style: .continuous)
                        .fill(WXColor.ink.opacity(layer.opacity))
                        .padding(-layer.spread)
                        .offset(y: layer.y)
                        .blur(radius: layer.blur / 2)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Paper shadow for an opaque rounded view: `.wxShadow(.chipRest, cornerRadius: WXRadius.card)`.
    public func wxShadow(_ shadow: WXShadow, cornerRadius: CGFloat) -> some View {
        modifier(WXShadowModifier(shadow: shadow, cornerRadius: cornerRadius))
    }

    /// Clips to a continuous rounded rectangle. `radius` is a `WXRadius` value; the active theme
    /// deck turns it into its own roundness (`WXDeck.corner`), so a deck's shape reaches every chip.
    public func wxRounded(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: WXDeck.current.corner(radius), style: .continuous))
    }
}

extension View {
    /// DESIGN.md "Chip rest": chips and cards resting on paper.
    public func chipRest(cornerRadius: CGFloat = WXRadius.card) -> some View {
        wxShadow(.chipRest, cornerRadius: cornerRadius)
    }

    /// DESIGN.md "Widget on wallpaper": widget previews over a wallpaper.
    public func widgetOnWallpaper(cornerRadius: CGFloat = WXRadius.widget) -> some View {
        wxShadow(.widgetOnWallpaper, cornerRadius: cornerRadius)
    }

    /// DESIGN.md "Lifted chip": the selected chip in a fan.
    public func chipLifted(cornerRadius: CGFloat = WXRadius.deckChip) -> some View {
        wxShadow(.chipLifted, cornerRadius: cornerRadius)
    }
}
