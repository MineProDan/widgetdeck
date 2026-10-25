import CoreKit
import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

private func rgba(_ hex: UInt32) -> RGBAColor {
    RGBAColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
}

private let ink: UInt32 = 0x22232E
private let inkSecondary: UInt32 = 0x5B5D6B
private let clayLink: UInt32 = 0xB2492F
private let mossPositive: UInt32 = 0x4C7A62

@Suite("Theme decks")
struct DeckTests {
    @Test func catalogueIsCompleteAndUnique() {
        #expect(WXDeck.all.count == 10)
        #expect(WXDeck.all.first == .paintChip, "the default deck comes first")
        #expect(Set(WXDeck.all.map(\.id)).count == WXDeck.all.count)
        #expect(Set(WXDeck.all.map(\.code)).count == WXDeck.all.count)
        #expect(Set(WXDeck.all.map(\.name)).count == WXDeck.all.count)
        #expect(Set(WXDeck.all.map(\.punch)).count == WXDeck.all.count, "every deck has its own punch shape")
    }

    @Test func paintChipDeckMatchesDesignTokens() {
        let deck = WXDeck.paintChip
        #expect(deck.sectionPaints == [0xE07A5F, 0x81B29A, 0xF2CC8F, 0x3D405B, 0x6D597A])
        #expect(deck.paper == 0xF7F3EA)
        #expect(deck.band == 0xFFFDF8)
        #expect(deck.punch == .circle)
        #expect(deck.corner(WXRadius.card) == WXRadius.card)
        #expect(deck.paintNames == ["Coral Hour", "Sage Noon", "Beach Sand", "Deep Tide", "Plum Dusk"])
    }

    @Test(arguments: WXDeck.all)
    func textOnBandsAndPaperPassesAA(deck: WXDeck) {
        // All words live on the band (ink, caps labels, urgent clay, positive moss) or on paper.
        for foreground in [ink, inkSecondary, clayLink, mossPositive] {
            #expect(ContrastChecker.ratio(rgba(foreground), rgba(deck.band)) >= 4.5, "\(deck.name) band")
        }
        #expect(ContrastChecker.ratio(rgba(ink), rgba(deck.paper)) >= 4.5, "\(deck.name) paper")
        #expect(ContrastChecker.ratio(rgba(inkSecondary), rgba(deck.paper)) >= 4.5, "\(deck.name) paper labels")
    }

    @Test(arguments: WXDeck.all)
    func darkAndLightPaintsKeepTheirRoles(deck: WXDeck) {
        // Fill bars use the Aesthetic paint on the Tech field; mood keys are light tints on Evening.
        #expect(ContrastChecker.ratio(rgba(deck.aesthetic), rgba(deck.tech)) >= 3, "\(deck.name) bar on tech")
        #expect(ContrastChecker.ratio(rgba(deck.paper), rgba(deck.tech)) >= 3, "\(deck.name) punch on tech")
        #expect(ContrastChecker.ratio(rgba(deck.paper), rgba(deck.evening)) >= 3, "\(deck.name) punch on evening")
        #expect(deck.paintNames.count == 5)
        #expect(Set(deck.sectionPaints).count == 5, "each section keeps its own colour")
    }

    @Test(arguments: WXDeck.all)
    func displayFaceIsBundledAndResolves(deck: WXDeck) {
        #expect(WXFonts.registerIfNeeded())
        for name in [deck.displayFont, deck.displayFontSmall].compactMap({ $0 }) {
            #expect(WXFonts.fileNames.contains(name))
            #expect(UIFont(name: name, size: 17)?.fontName == name, "\(name) resolves")
        }
    }

    @Test func everyBundledFaceShipsItsLicence() throws {
        let licences = ["Fredoka", "Quicksand", "PlayfairDisplay", "YoungSerif", "Silkscreen",
                        "Unbounded", "Graduate", "SpaceGrotesk", "Caveat"]
        for family in licences {
            let url = try #require(WXFonts.bundle.url(forResource: "OFL-\(family)", withExtension: "txt", subdirectory: "Fonts"))
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("SIL Open Font License"), "\(family)")
        }
    }

    /// Display strings the app really shows, at the sizes it shows them.
    private static let displaySamples: [(String, CGFloat)] = [
        ("Pick your vibe.", 40), ("Today", 40), ("Match my wallpaper", 36), ("in 14 min", 30),
        ("3 of 4 done", 28), ("18:20", 34), ("Saturday Cartoons", 28), ("Habits", 17),
        ("How's today?", 18), ("Chem lab report", 22),
    ]

    private static func width(_ text: String, size: CGFloat, deck: WXDeck) -> CGFloat {
        let scaled = size * deck.displayScale
        guard let font = UIFont(name: deck.displayFontName(for: size), size: scaled) else { return .infinity }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: scaled * deck.displayTracking]
        return (text as NSString).size(withAttributes: attributes).width
    }

    @Test(arguments: WXDeck.all)
    func displayTextFitsLayoutsBuiltForBricolage(deck: WXDeck) {
        #expect(WXFonts.registerIfNeeded())
        for (text, size) in Self.displaySamples {
            let ratio = Self.width(text, size: size, deck: deck) / Self.width(text, size: size, deck: .paintChip)
            #expect(ratio <= 1.2, "\(deck.name): \"\(text)\" at \(size) pt is \(ratio)× Bricolage's width")
            #expect(ratio >= 0.75, "\(deck.name): \"\(text)\" at \(size) pt reads too small (\(ratio)×)")
        }
    }

    @Test(arguments: WXDeck.all)
    func capCentringBiasMatchesTheFace(deck: WXDeck) throws {
        #expect(WXFonts.registerIfNeeded())
        let font = try #require(UIFont(name: deck.displayFontName(for: 28), size: 28))
        let bias = WXFont.capCentringBias(font)
        // After shifting by `bias`, the room above the capitals equals the room below the baseline.
        let above = font.ascender - font.capHeight - bias
        let below = abs(font.descender) + bias
        #expect(abs(above - below) < 0.01)
        #expect(abs(bias) < 28 * 0.08, "\(deck.name) shifts by \(bias) pt; check the face's metrics")
        if deck == .paintChip {
            #expect(abs(bias) < 0.2, "Bricolage is already centred, so the Paint Chip look is unchanged")
        }
    }

    @Test func onlyPocketArcadeSetsPercentInTheLabelFace() {
        // Silkscreen's "%" reads as "Z" at widget size ("100Z"); every other face keeps its own.
        #expect(WXDeck.all.filter(\.percentFromLabelFace).map(\.id) == [WXDeck.pocketArcade.id])
    }

    @Test func cornersScaleAndCap() {
        #expect(WXDeck.pocketArcade.corner(WXRadius.widget) == 4)
        #expect(WXDeck.saturdayCartoons.corner(WXRadius.widget) == 28)
        #expect(WXDeck.oldLibrary.corner(WXRadius.card) == 8)
        #expect(WXDeck.oldLibrary.corner(0) == 0)
    }

    @Test func selectionRoundTripsAndUnknownFallsBack() throws {
        let name = "deck.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(WXDeck.current(in: defaults) == .paintChip)
        WXDeck.select(.tidePool, in: defaults)
        #expect(WXDeck.current(in: defaults) == .tidePool)
        defaults.set("a-deck-from-the-future", forKey: WXDeck.storageKey)
        #expect(WXDeck.current(in: defaults) == .paintChip)
    }

    @Test(arguments: WXDeck.PunchShape.allCases)
    func punchShapesFillTheirFrame(shape: WXDeck.PunchShape) {
        let bounds = PunchHoleShape(shape).path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).boundingRect
        #expect(!bounds.isEmpty)
        #expect(bounds.width >= 60 && bounds.height >= 60, "\(shape) reads at punch-hole size")
        #expect(bounds.minX >= -1 && bounds.minY >= -1 && bounds.maxX <= 101 && bounds.maxY <= 101, "\(shape) stays in frame")
    }
}
