import CoreKit
import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// sRGB hex of a SwiftUI colour, for token checks.
private func hex(_ color: Color) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
}

private func rgba(_ color: Color) -> RGBAColor {
    RGBAColor(hex: hex(color))!
}

@Suite("Paint Chip tokens")
struct PaintChipTokenTests {
    /// Every colour in the DESIGN.md frontmatter, verbatim.
    @Test(arguments: [
        (WXColor.coralHour, "#E07A5F"), (WXColor.sageNoon, "#81B29A"), (WXColor.beachSand, "#F2CC8F"),
        (WXColor.deepTide, "#3D405B"), (WXColor.plumDusk, "#6D597A"), (WXColor.paperIvory, "#F7F3EA"),
        (WXColor.labelIvory, "#FFFDF8"), (WXColor.shell, "#F6DDB2"), (WXColor.ink, "#22232E"),
        (WXColor.inkSecondary, "#5B5D6B"), (WXColor.inkBody, "#4A4C59"), (WXColor.inkInactive, "#6B6D7A"),
        (WXColor.rule, "#E4DED1"), (WXColor.clayLink, "#B2492F"), (WXColor.mossPositive, "#4C7A62"),
        (WXColor.segmentTrack, "#ECE6DA")
    ])
    func designColors(color: Color, expected: String) {
        #expect(hex(color) == expected)
    }

    @Test func sectionColoursAreLaw() {
        #expect(hex(WXSection.student.color) == "#E07A5F")
        #expect(hex(WXSection.wellness.color) == "#81B29A")
        #expect(hex(WXSection.aesthetic.color) == "#F2CC8F")
        #expect(hex(WXSection.tech.color) == "#3D405B")
        #expect(hex(WXSection.evening.color) == "#6D597A")
        for section in AppSection.allCases {
            #expect(WXSection(section).rawValue == section.rawValue)
        }
    }

    @Test func moodRampsHaveFiveSteps() {
        #expect(WXColor.moodTints.map(hex) == ["#A99BB3", "#BCAFC5", "#9C88AA", "#7E6A8C", "#6D597A"])
        #expect(WXColor.moodTintsOnPlum.count == 5)
        #expect(MoodScale.words.count == 5)
    }

    @Test func launchThemesHaveFourSteps() {
        #expect(WXThemePaint.launchThemes.count == 6)
        #expect(WXThemePaint.launchThemes.allSatisfy { $0.steps.count == 4 })
        #expect(Set(WXThemePaint.launchThemes.map(\.code)).count == 6, "codes are unique ids")
    }

    @Test func radiiAndSpacing() {
        #expect([WXRadius.swatch, WXRadius.chip, WXRadius.card, WXRadius.widget, WXRadius.pill] == [8, 14, 16, 22, 22])
        #expect([WXSpace.xs, WXSpace.sm, WXSpace.md, WXSpace.gutter] == [6, 10, 14, 24])
    }

    @Test func shadowsMatchDesignValues() {
        #expect(WXShadow.chipRest.layers == [.init(y: 1, blur: 2, opacity: 0.08), .init(y: 10, blur: 22, spread: -12, opacity: 0.4)])
        #expect(WXShadow.widgetOnWallpaper.layers == [.init(y: 12, blur: 30, spread: -14, opacity: 0.45)])
        #expect(WXShadow.chipLifted.layers == [.init(y: 1, blur: 2, opacity: 0.10), .init(y: 14, blur: 30, spread: -12, opacity: 0.55)])
    }

    /// Text pairs used on chips must meet WCAG AA (4.5:1 body; caps labels are small text).
    @Test(arguments: [
        (WXColor.ink, WXColor.labelIvory), (WXColor.inkSecondary, WXColor.labelIvory), (WXColor.inkBody, WXColor.paperIvory),
        (WXColor.inkInactive, WXColor.paperIvory), (WXColor.clayLink, WXColor.labelIvory), (WXColor.mossPositive, WXColor.labelIvory),
        (WXColor.labelIvory, WXColor.ink), (WXColor.inkSecondary, WXColor.paperIvory), (WXColor.plumDusk, WXColor.paperIvory)
    ])
    func textPairsMeetAA(foreground: Color, background: Color) {
        #expect(ContrastChecker.meets(rgba(foreground), on: rgba(background), size: .body))
    }

    @Test func defaultSemanticPaletteIsPaintChip() {
        #expect(SemanticPalette.light.surfaceBase == RGBAColor(hex: "#F7F3EA"))
        #expect(SemanticPalette.light.surfaceElevated == RGBAColor(hex: "#FFFDF8"))
        #expect(SemanticPalette.light.textPrimary == RGBAColor(hex: "#22232E"))
    }
}

@Suite("Paint Chip fonts")
struct PaintChipFontTests {
    @Test func bundledFontsRegisterAndResolve() {
        #expect(WXFonts.registerIfNeeded())
        for name in [WXFonts.Name.grotesk, WXFonts.Name.groteskDisplay, WXFonts.Name.condensed] {
            let font = UIFont(name: name, size: 17)
            #expect(font != nil, "\(name) resolves after registration")
            #expect(font?.fontName == name)
        }
    }

    @Test func licencesShipWithFonts() throws {
        for licence in ["OFL-BricolageGrotesque", "OFL-Archivo"] {
            let url = try #require(WXFonts.bundle.url(forResource: licence, withExtension: "txt", subdirectory: "Fonts"))
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("SIL Open Font License"))
        }
    }

    @Test func condensedIsNarrowerThanRegularWidth() throws {
        // Tests run in parallel: don't rely on another test having registered the fonts first.
        try #require(WXFonts.registerIfNeeded())
        let condensed = try #require(UIFont(name: WXFonts.Name.condensed, size: 11))
        let string = "CORAL HOUR · FLOW" as NSString
        let condensedWidth = string.size(withAttributes: [.font: condensed]).width
        let systemWidth = string.size(withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .bold)]).width
        #expect(condensedWidth < systemWidth * 0.9)
    }
}

@Suite("PaintChip layout")
@MainActor
struct PaintChipLayoutTests {
    private func size(of view: some View, proposal: ProposedViewSize) -> CGSize {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: proposal.width ?? .infinity, height: proposal.height ?? .infinity))
    }

    @Test func fixedFieldGrowsWithBand() {
        let small = PaintChip(color: WXColor.deepTide, field: .fixed(78), shadow: nil) {
            ChipLabelBand(caption: "Battery", value: "82%")
        }
        let tall = PaintChip(color: WXColor.deepTide, field: .fixed(78), shadow: nil) {
            ChipLabelBand(caption: "Battery", value: "82%", trend: "Charging · est. 1h 10m")
        }
        let a = size(of: small, proposal: ProposedViewSize(width: 166, height: nil))
        let b = size(of: tall, proposal: ProposedViewSize(width: 166, height: nil))
        #expect(a.height > 78)
        #expect(b.height > a.height, "a longer band makes the chip taller when height is free")
    }

    @Test func largeDynamicTypeGrowsTheChipInsteadOfClipping() {
        let chip = PaintChip(color: WXColor.deepTide, field: .fixed(78), shadow: nil) {
            ChipLabelBand(caption: "Battery", value: "82%", trend: "Charging · est. 1h 10m")
        }
        let regular = size(of: chip.environment(\.dynamicTypeSize, .large), proposal: ProposedViewSize(width: 166, height: nil))
        let ax3 = size(of: chip.environment(\.dynamicTypeSize, .accessibility3), proposal: ProposedViewSize(width: 166, height: nil))
        #expect(ax3.height > regular.height + 20)
    }
}

@Suite("Widget theme paint")
struct WidgetThemePaintTests {
    let theme = ActiveThemeSnapshot(themeID: UUID(), name: "T", primary: .black, accent: .white)

    @Test func noThemeKeepsPaints() {
        #expect(WidgetThemePaint.resolve(WXColor.deepTide, theme: nil) == WXColor.deepTide)
    }

    @Test func darkPaintsTakePrimaryWarmPaintsTakeAccent() {
        let primary = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
        let accent = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)
        #expect(WidgetThemePaint.resolve(WXColor.deepTide, theme: theme) == primary)
        #expect(WidgetThemePaint.resolve(WXColor.plumDusk, theme: theme) == primary)
        for paint in [WXColor.coralHour, WXColor.sageNoon, WXColor.beachSand] {
            #expect(WidgetThemePaint.resolve(paint, theme: theme) == accent)
        }
        #expect(WidgetThemePaint.resolve(WXColor.ink, theme: theme) == WXColor.ink)
    }
}
