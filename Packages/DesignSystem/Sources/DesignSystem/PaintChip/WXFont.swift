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

    static let fileNames = ["BricolageGrotesque-Bold", "BricolageGrotesqueDisplay-Bold", "ArchivoCondensed-Bold"]

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

    /// Bricolage at any size: picks the optical-size instance that matches the mockup.
    public static func grotesk(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        _ = WXFonts.registerIfNeeded()
        let name = size >= 21 ? WXFonts.Name.groteskDisplay : WXFonts.Name.grotesk
        return .custom(name, size: size, relativeTo: style)
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
private struct CSSLineHeight: ViewModifier {
    /// `nil` = the system font.
    let fontName: String?
    let multiple: CGFloat
    @ScaledMetric private var size: CGFloat

    init(fontName: String?, size: CGFloat, multiple: CGFloat, relativeTo style: Font.TextStyle) {
        self.fontName = fontName
        self.multiple = multiple
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    func body(content: Content) -> some View {
        let font = fontName.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
        let delta = multiple * size - font.lineHeight
        content
            .lineSpacing(max(delta, 0))
            .padding(.vertical, delta / 2)
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

    /// Bricolage name/value text at `size` (display ≥ 36, headline 22–34, title 15–18),
    /// −0.02 em tracking. `tabular` switches on tabular numerals for values.
    public func wxGrotesk(_ size: CGFloat, tabular: Bool = false, color: Color = WXColor.ink) -> some View {
        let style: Font.TextStyle = size >= 36 ? .largeTitle : size >= 28 ? .title : size >= 21 ? .title2 : .headline
        let font = WXFont.grotesk(size, relativeTo: style)
        return self.font(tabular ? font.monospacedDigit() : font)
            .modifier(ScaledTracking(size * -0.02, relativeTo: style))
            .modifier(CSSLineHeight(fontName: size >= 21 ? WXFonts.Name.groteskDisplay : WXFonts.Name.grotesk,
                                    size: size, multiple: 1.05, relativeTo: style))
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
