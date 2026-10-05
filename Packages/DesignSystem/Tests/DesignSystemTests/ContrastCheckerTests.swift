import CoreKit
import Testing
@testable import DesignSystem

@Suite("ContrastChecker")
struct ContrastCheckerTests {
    @Test func blackOnWhiteIs21() {
        #expect(abs(ContrastChecker.ratio(.black, .white) - 21) < 0.001)
        #expect(abs(ContrastChecker.ratio(.white, .black) - 21) < 0.001, "order doesn't matter")
    }

    @Test func sameColorIs1() {
        let gray = RGBAColor(hex: "#777777")!
        #expect(abs(ContrastChecker.ratio(gray, gray) - 1) < 0.0001)
    }

    @Test func knownReferenceValues() {
        // Reference ratios from the WebAIM contrast checker.
        #expect(abs(ContrastChecker.ratio(RGBAColor(hex: "#767676")!, .white) - 4.54) < 0.01)
        #expect(abs(ContrastChecker.ratio(RGBAColor(hex: "#777777")!, .white) - 4.48) < 0.01)
        #expect(abs(ContrastChecker.ratio(RGBAColor(hex: "#0000FF")!, .white) - 8.59) < 0.01)
    }

    @Test func thresholds() {
        let gray = RGBAColor(hex: "#777777")! // 4.48:1 on white
        #expect(ContrastChecker.meets(gray, on: .white, size: .body) == false)
        #expect(ContrastChecker.meets(gray, on: .white, size: .large))
    }

    @Test func translucentForegroundIsComposited() {
        let halfBlack = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        let ratio = ContrastChecker.ratio(halfBlack, .white)
        #expect(ratio > 3 && ratio < 5)
    }

    @Test func bestTextColor() {
        #expect(ContrastChecker.bestTextColor(on: RGBAColor(hex: "#FFE066")!) == .black)
        #expect(ContrastChecker.bestTextColor(on: RGBAColor(hex: "#1B1F3B")!) == .white)
    }

    @Test(arguments: ["#FFFFFF", "#F5EFE6", "#FFB3C6", "#7FB2F0", "#2E7D32", "#121318", "#808080"])
    func ensureContrastAlwaysMeetsBody(backgroundHex: String) {
        let background = RGBAColor(hex: backgroundHex)!
        let pastel = RGBAColor(hex: "#C9B6E4")!
        let fixed = ContrastChecker.ensureContrast(pastel, on: background)
        #expect(ContrastChecker.ratio(fixed, background) >= 4.5)
    }

    @Test func ensureContrastKeepsPassingColors() {
        let ink = RGBAColor(hex: "#121318")!
        #expect(ContrastChecker.ensureContrast(ink, on: .white) == ink)
    }
}

@Suite("Tokens and ThemeResolver")
struct ThemeResolverTests {
    @Test(arguments: [SemanticPalette.light, SemanticPalette.dark])
    func defaultPalettesMeetWCAG(palette: SemanticPalette) {
        for surface in [palette.surfaceBase, palette.surfaceElevated] {
            #expect(ContrastChecker.meets(palette.textPrimary, on: surface))
            #expect(ContrastChecker.meets(palette.textSecondary, on: surface))
            #expect(ContrastChecker.meets(palette.accentPrimary, on: surface, size: .large))
        }
        #expect(ContrastChecker.meets(palette.onAccent, on: palette.accentPrimary))
    }

    @Test func emptyPaletteUsesDefaults() {
        #expect(ThemeResolver.resolve(.system) == .standard)
    }

    @Test func illegibleUserPaletteIsFixedAndWarned() {
        // Pastel wallpaper palette with pastel text: fails WCAG as picked.
        let theme = Theme(name: "Pastel", source: .wallpaper, palette: [
            .background: RGBAColor(hex: "#F8E1E7")!,
            .accent: RGBAColor(hex: "#F9C5D5")!,
            .textOnBackground: RGBAColor(hex: "#E7A1B0")!
        ])
        let resolved = ThemeResolver.resolve(theme)
        let palette = resolved.light
        #expect(ContrastChecker.meets(palette.textPrimary, on: palette.surfaceBase))
        #expect(ContrastChecker.meets(palette.textPrimary, on: palette.surfaceElevated))
        #expect(ContrastChecker.meets(palette.textSecondary, on: palette.surfaceElevated))
        #expect(ContrastChecker.meets(palette.onAccent, on: palette.accentPrimary))
        #expect(ContrastChecker.meets(palette.accentPrimary, on: palette.surfaceBase, size: .large))
        #expect(!resolved.contrastWarnings.isEmpty)
        #expect(resolved.light == resolved.dark, "custom palettes have a fixed look")
    }

    @Test func darkWallpaperGetsDarkDefaults() {
        let theme = Theme(name: "Night", palette: [.background: RGBAColor(hex: "#0B1026")!])
        let palette = ThemeResolver.resolve(theme).light
        #expect(palette.textPrimary.isDark == false)
        #expect(ContrastChecker.meets(palette.textPrimary, on: palette.surfaceBase))
    }

    @Test func increasedContrastCollapsesSecondaryText() {
        let palette = DSTheme.standard.palette(for: .light, increasedContrast: true)
        #expect(palette.textSecondary == palette.textPrimary)
    }
}
