import SwiftUI

// Theme pickers show every deck side by side, so these views draw from an explicit `WXDeck`
// instead of the active one (`WXColor` / `WXFont` follow `WXDeck.current`).

/// A theme deck as a paint strip: four section paints stacked, the deck's own punch mark, and a
/// band with its code and name set in the deck's display face. Used in onboarding and Settings.
public struct DeckStrip: View {
    private let deck: WXDeck
    private let isSelected: Bool
    private let stepHeight: CGFloat

    public init(_ deck: WXDeck, isSelected: Bool = false, stepHeight: CGFloat = 46) {
        self.deck = deck
        self.isSelected = isSelected
        self.stepHeight = stepHeight
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(deck.stripPaints.enumerated()), id: \.offset) { index, paint in
                Color(wxHex: paint)
                    .frame(height: stepHeight)
                    .overlay(alignment: .top) {
                        if index == 0 {
                            let size = 10 * deck.punch.sizeMultiplier
                            PunchHoleShape(deck.punch)
                                .fill(Color(wxHex: deck.paper))
                                .frame(width: size, height: size)
                                .padding(.top, 10)
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.code).wxLabel(9)
                Text(deck.name)
                    .wxGrotesk(15, deck: deck)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(Color(wxHex: deck.band))
        }
        .background(Color(wxHex: deck.band))
        .clipShape(RoundedRectangle(cornerRadius: deck.corner(WXRadius.deckChip), style: .continuous))
        .wxShadow(isSelected ? .chipLifted : .chipFanned, cornerRadius: WXRadius.deckChip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(deck.name) theme")
        .accessibilityValue(deck.mood)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A row of deck strips you flip through like a swatch deck. The selected strip lifts.
public struct DeckPicker: View {
    @Binding private var selection: String
    private let decks: [WXDeck]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<String>, decks: [WXDeck] = WXDeck.all) {
        _selection = selection
        self.decks = decks
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(decks) { deck in
                        let isSelected = deck.id == selection
                        Button {
                            withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)) {
                                selection = deck.id
                                proxy.scrollTo(deck.id, anchor: .center)
                            }
                        } label: {
                            DeckStrip(deck, isSelected: isSelected)
                                .frame(width: 104)
                                .offset(y: isSelected ? 0 : 22)
                        }
                        .buttonStyle(.plain)
                        .id(deck.id)
                    }
                }
                .padding(.horizontal, WXSpace.gutter)
                .padding(.vertical, 18)
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
    }
}

/// A mini home screen in `deck`: Next Class (Student), Habits (Wellness), Battery (Tech) and
/// Mood (Evening) chips with sample values, so people can judge a deck before using it.
public struct DeckPreview: View {
    private let deck: WXDeck

    public init(_ deck: WXDeck) {
        self.deck = deck
    }

    public var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MiniChip(deck: deck, paint: deck.student, caption: "\(deck.paintNames[0]) · BIO 201", value: "14 min") { EmptyView() }
                MiniChip(deck: deck, paint: deck.tech, caption: "Battery", value: "82%") {
                    FillBar(value: 0.82, color: Color(wxHex: deck.aesthetic), height: 10, trackOpacity: 0.18)
                        .padding(.horizontal, 12)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 12)
                }
            }
            HStack(spacing: 10) {
                MiniChip(deck: deck, paint: deck.wellness, caption: "Habits", value: "3 of 4") { EmptyView() }
                MiniChip(deck: deck, paint: deck.evening, caption: deck.paintNames[4], value: "Good") { EmptyView() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of widgets in \(deck.name)")
    }
}

private struct MiniChip<Field: View>: View {
    let deck: WXDeck
    let paint: UInt32
    let caption: String
    let value: String
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color(wxHex: paint)
                field()
                let size = 9 * deck.punch.sizeMultiplier
                PunchHoleShape(deck.punch)
                    .fill(Color(wxHex: deck.paper))
                    .frame(width: size, height: size)
                    .padding(.top, max(10 - (size - 9) / 2, 0))
                    .padding(.leading, max(10 - (size - 9) / 2, 0))
            }
            .frame(height: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(caption).wxLabel(9).lineLimit(1)
                Text(value)
                    .wxGrotesk(22, tabular: true, deck: deck)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(wxHex: deck.band))
        }
        .clipShape(RoundedRectangle(cornerRadius: deck.corner(WXRadius.widget), style: .continuous))
        .wxShadow(.chipRest, cornerRadius: WXRadius.widget)
    }
}

private struct DeckPickerPreview: View {
    @State private var selection = WXDeck.tidePool.id

    var body: some View {
        VStack(spacing: 20) {
            DeckPicker(selection: $selection).frame(height: 330)
            DeckPreview(WXDeck.deck(id: selection)).padding(.horizontal, 24)
        }
        .background(WXColor.paperIvory)
    }
}

#Preview("Deck picker") {
    DeckPickerPreview()
}
