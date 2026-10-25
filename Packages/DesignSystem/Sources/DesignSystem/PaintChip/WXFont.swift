import CoreText
import SwiftUI

/// Bundled typefaces (SIL OFL 1.1, licences next to the files in `Resources/Fonts`).
///
/// Registration is process-scoped through CoreText, so it works in the app and inside the widget
/// extension without Info.plist `UIAppFonts` entries. Every `WXFont` accessor registers lazily;
/// call `WXFonts.registerIfNeeded()` at launch only to warm it up. If registration fails the
/// custom font names resolve to the system font (SwiftUI's fallback), so text never disappears.
public enum WXFonts {
    /// PostScript names of the bundled static instances.
    public enum Name {
        /// Bricolage Grotesque Bold, optical size 16: titles and values up to ~20 pt.
        public static let grotesk = "BricolageGrotesque-Bold"
        /// Bricolage Grotesque Bold, optical size 36: display and headline sizes (≥ 21 pt).
        public static let groteskDisplay = "BricolageGrotesqueDisplay-Bold"
        /// Archivo Bold at width 75 (condensed): caps labels.
        public static let condensed = "ArchivoCondensed-Bold"
    }

    /// The package resource bundle that holds the fonts and their licences.
    static var bundle: Bundle { .module }

    /// The Paint Chip faces plus each theme deck's display face (`WXDeck.displayFont`).
    static let fileNames = [
        "BricolageGrotesque-Bold", "BricolageGrotesqueDisplay-Bold", "ArchivoCondensed-Bold",
        "Fredoka-Bold", "Quicksand-Bold", "PlayfairDisplay-Bold", "YoungSerif-Regular", "Silkscreen-Bold",
        "Unbounded-Bold", "Graduate-Regular", "SpaceGrotesk-Bold", "Caveat-Bold",
    ]

    private static let registration: Bool = {
        var allRegistered = true
        for name in fileNames {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else {
                allRegistered = false
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already registered (e.g. a second bundle load) is fine; anything else falls back.
                let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? 0
                if code != CTFontManagerError.alreadyRegistered.rawValue { allRegistered = false }
            }
        }
        return allRegistered
    }()

    /// Registers the bundled fonts once per process. Returns `false` if any font is unavailable
    /// (text then renders in the system font).
    @discardableResult
    public static func registerIfNeeded() -> Bool { registration }
}

/// Type roles from DESIGN.md. Every size scales with Dynamic Type relative to a system text style.
public enum WXFont {
    /// Screen titles: Bricolage 700, 40 pt (36 for long titles).
    public static func display(_ size: CGFloat = 40) -> Font {
        grotesk(size, relativeTo: .largeTitle)
    }

    /// Key values inside chips: Bricolage 700, 22–34 pt. Pair with `.monospacedDigit()` for numbers.
    public static func headline(_ size: CGFloat = 28) -> Font {
        grotesk(size, relativeTo: size >= 28 ? .title : .title2)
    }

    /// Chip and list item names: Bricolage 700, 15–18 pt.
    public static func title(_ size: CGFloat = 17) -> Font {
        grotesk(size, relativeTo: .headline)
    }

    /// Subtitles, explanations and control text in SF Pro. Sizes map to the iOS text style of
    /// the same default size (17 body, 16 callout, 15 subheadline, 13 footnote, 12 caption), so
    /// SF's own optical tracking applies and every size follows Dynamic Type.
    public static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        let style: Font.TextStyle = switch size {
        case 17...: .body
        case 16..<17: .callout
        case 14..<16: .subheadline
        case 13..<14: .footnote
        case 12..<13: .caption
        default: .caption2
        }
        return Font.system(style).weight(weight)
    }

    /// Condensed caps labels: Archivo Condensed 700, 9–11 pt. Use the `wxLabel` modifier to also
    /// get uppercase and +0.08 em tracking.
    public static func label(_ size: CGFloat = 11) -> Font {
        _ = WXFonts.registerIfNeeded()
        return .custom(WXFonts.Name.condensed, size: size, relativeTo: .caption2)
    }

    /// The active deck's display face at any size (Bricolage for the Paint Chip deck, picking the
    /// optical-size instance that matches the mockup). Faces that run wide or small are evened
    /// out by `WXDeck.displayScale`, so layouts built for Bricolage still fit.
    public static func grotesk(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        grotesk(size, relativeTo: style, deck: WXDeck.current)
    }

    /// `grotesk` for an explicit deck (theme pickers preview every deck side by side).
    public static func grotesk(_ size: CGFloat, relativeTo style: Font.TextStyle, deck: WXDeck) -> Font {
        _ = WXFonts.registerIfNeeded()
        return .custom(deck.displayFontName(for: size), size: size * deck.displayScale, relativeTo: style)
    }
}

// MARK: - Text styling modifiers (font + tracking + case in one call)

/// Letter-spacing that scales with Dynamic Type, like the font it belongs to.
private struct ScaledTracking: ViewModifier {
    @ScaledMetric private var tracking: CGFloat

    init(_ tracking: CGFloat, relativeTo style: Font.TextStyle) {
        _tracking = ScaledMetric(wrappedValue: tracking, relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.tracking(tracking)
    }
}

/// Emulates CSS `line-height` (the mockup's unit): SwiftUI lays a line out at the font's natural
/// height, so this pads single lines by half the difference and adds the difference between
/// lines of wrapped text. Negative differences (tight display type) trim the outer padding only.
///
/// With `centersCaps`, the line box is also shifted so capitals sit in its middle. Bricolage is
/// drawn that way already (bias 0, so the Paint Chip deck is unchanged); other deck faces put
/// more room above or below their capitals (Playfair sits 0.06 em low, Young Serif 0.035 em
/// high), which would otherwise offset values against their caps labels.
private struct CSSLineHeight: ViewModifier {
    /// `nil` = the system font.
    let fontName: String?
    let multiple: CGFloat
    let centersCaps: Bool
    @ScaledMetric private var size: CGFloat

    init(fontName: String?, size: CGFloat, multiple: CGFloat, relativeTo style: Font.TextStyle, centersCaps: Bool = false) {
        self.fontName = fontName
        self.multiple = multiple
        self.centersCaps = centersCaps
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    func body(content: Content) -> some View {
        let font = fontName.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
        let delta = multiple * size - font.lineHeight
        let bias = centersCaps ? WXFont.capCentringBias(font) : 0
        content
            .lineSpacing(max(delta, 0))
            .padding(.top, delta / 2 - bias)
            .padding(.bottom, delta / 2 + bias)
    }
}

extension WXFont {
    /// How far (in points) a line of `font` must move up so its capitals sit in the middle of the
    /// line box: half the difference between the room above the cap height and below the baseline.
    /// Positive = the face draws its capitals low. About 0 for Bricolage.
    static func capCentringBias(_ font: UIFont) -> CGFloat {
        ((font.ascender - font.capHeight) - abs(font.descender)) / 2
    }
}

extension Text {
    /// A value for `wxGrotesk(size)` ("100%", "25 GB"). In decks with `percentFromLabelFace`, each
    /// "%" is set in the condensed label face, sized so it matches the display face's digits
    /// (Silkscreen digits are 0.4125 em of the nominal size; Archivo's are 0.711 em of its own).
    /// A font set on a run of concatenated `Text` wins over the one `wxGrotesk` applies.
    public init(wxValue value: String, size: CGFloat, deck: WXDeck? = nil) {
        let deck = deck ?? WXDeck.current
        guard deck.percentFromLabelFace, value.contains("%") else {
            self.init(value)
            return
        }
        let style = WXFont.displayStyle(for: size)
        let percent = Text("%").font(.custom(WXFonts.Name.condensed, size: size * 0.58, relativeTo: style))
        let parts = value.components(separatedBy: "%")
        var text = Text(parts[0])
        for part in parts.dropFirst() {
            text = text + percent + Text(part)
        }
        self = text
    }
}

extension WXFont {
    /// The Dynamic Type style display text at `size` scales with (see `wxGrotesk`).
    static func displayStyle(for size: CGFloat) -> Font.TextStyle {
        size >= 36 ? .largeTitle : size >= 28 ? .title : size >= 21 ? .title2 : .headline
    }
}

extension View {
    /// Condensed caps label: Archivo Condensed Bold, uppercase, +0.08 em tracking.
    public func wxLabel(_ size: CGFloat = 11, color: Color = WXColor.inkSecondary) -> some View {
        font(WXFont.label(size))
            .textCase(.uppercase)
            .modifier(ScaledTracking(size * 0.08, relativeTo: .caption2))
            .modifier(CSSLineHeight(fontName: WXFonts.Name.condensed, size: size, multiple: 1.25, relativeTo: .caption2))
            .foregroundStyle(color)
    }

    /// Display-face name/value text at `size` (display ≥ 36, headline 22–34, title 15–18) in the
    /// active deck's face and tracking (Bricolage, −0.02 em for the Paint Chip deck). `tabular` switches on tabular numerals for values.
    /// Pass `deck` to set text in a specific deck (theme pickers); by default the active deck.
    public func wxGrotesk(_ size: CGFloat, tabular: Bool = false, color: Color = WXColor.ink, deck: WXDeck? = nil) -> some View {
        let style = WXFont.displayStyle(for: size)
        let deck = deck ?? WXDeck.current
        let font = WXFont.grotesk(size, relativeTo: style, deck: deck)
        return self.font(tabular ? font.monospacedDigit() : font)
            .modifier(ScaledTracking(size * deck.displayScale * deck.displayTracking, relativeTo: style))
            // The line box stays 1.05 × the nominal size in every deck, so chips keep the
            // heights they were designed with even when a face is scaled up or down.
            .modifier(CSSLineHeight(fontName: deck.displayFontName(for: size),
                                    size: size * deck.displayScale, multiple: 1.05 / deck.displayScale,
                                    relativeTo: style, centersCaps: true))
            .foregroundStyle(color)
    }

    /// SF body text in Ink Body (subtitles, explanations). `lineHeight` is the CSS multiple
    /// (1.35 subtitles, 1.4 onboarding, 1.45 footnotes).
    public func wxBody(_ size: CGFloat = 15, lineHeight: CGFloat = 1.35, color: Color = WXColor.inkBody) -> some View {
        font(WXFont.body(size))
            .modifier(CSSLineHeight(fontName: nil, size: size, multiple: lineHeight,
                                    relativeTo: size <= 13 ? .footnote : .body))
            .foregroundStyle(color)
    }
}
