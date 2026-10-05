import SwiftUI

/// Chips rotated about a shared pivot below the row, overlapping, front chip on top: the
/// system's signature arrangement for a set of chips (Home "On your home screen", onboarding).
///
/// Every card is laid out at the same centred spot, then rotated about `pivot` (a unit point in
/// the card's own bounds, usually far below it, e.g. `y: 2.15`). The selected card lifts along
/// its own rotated axis and comes to the front.
public struct FanDeck<Item: Identifiable, Card: View>: View {
    private let items: [Item]
    private let angles: [Double]
    private let pivot: UnitPoint
    private let cardSize: CGSize
    private let selectedID: Item.ID?
    private let lift: CGFloat
    private let cornerRadius: CGFloat
    private let onSelect: ((Item) -> Void)?
    private let card: (Item) -> Card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - angles: degrees per item, back to front (Home: −27, −9, 9, 27; Main: ±24, ±14.5, ±5).
    ///   - pivot: rotation origin in card units (Home 0.5 × 2.15, Main 0.5 × 1.18).
    ///   - cardSize: every card's size (Home 96 × 138, Main 96 × 300).
    ///   - selectedID: lifted (−34 pt) with the lifted shadow and brought to the front.
    public init(
        _ items: [Item],
        angles: [Double],
        pivot: UnitPoint,
        cardSize: CGSize,
        selectedID: Item.ID? = nil,
        lift: CGFloat = -34,
        cornerRadius: CGFloat = WXRadius.deckChip,
        onSelect: ((Item) -> Void)? = nil,
        @ViewBuilder card: @escaping (Item) -> Card
    ) {
        self.items = items
        self.angles = angles
        self.pivot = pivot
        self.cardSize = cardSize
        self.selectedID = selectedID
        self.lift = lift
        self.cornerRadius = cornerRadius
        self.onSelect = onSelect
        self.card = card
    }

    public var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let selected = item.id == selectedID
                let angle = index < angles.count ? angles[index] : 0
                cardView(item, selected: selected)
                    .frame(width: cardSize.width, height: cardSize.height)
                    .offset(y: selected ? lift : 0)
                    .rotationEffect(.degrees(angle), anchor: pivot)
                    .zIndex(selected ? Double(items.count + 1) : Double(index))
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45), value: selectedID)
    }

    @ViewBuilder
    private func cardView(_ item: Item, selected: Bool) -> some View {
        let content = card(item)
        if let onSelect {
            Button { onSelect(item) } label: { content }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            content
        }
    }
}

/// A small vertical deck chip (Home fan): 96 × 138, field 82, caps paint name + 15 pt name.
public struct DeckChip: View {
    private let color: Color
    private let paint: String
    private let name: String
    private let shadow: WXShadow

    public init(color: Color, paint: String, name: String, shadow: WXShadow = .chipRest) {
        self.color = color
        self.paint = paint
        self.name = name
        self.shadow = shadow
    }

    public var body: some View {
        PaintChip(color: color, field: .fixed(82), punchHole: .deck, cornerRadius: WXRadius.deckChip, shadow: shadow) {
            ChipLabelBand(caption: paint, value: name, captionSize: 9, valueSize: 15,
                          padding: EdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9), spacing: 3, alignment: .topLeading)
                .lineLimit(1)
        }
    }
}

/// The 4-step onboarding paint strip (Main): four stacked steps, centred punch hole, band with
/// code and name. 96 × 300 in the fan.
public struct PaintStrip: View {
    private let steps: [Color]
    private let code: String
    private let name: String
    private let stepHeight: CGFloat
    private let shadow: WXShadow

    public init(steps: [Color], code: String, name: String, stepHeight: CGFloat = 58, shadow: WXShadow = .chipFanned) {
        self.steps = steps
        self.code = code
        self.name = name
        self.stepHeight = stepHeight
        self.shadow = shadow
    }

    public init(_ paint: WXThemePaint, shadow: WXShadow = .chipFanned) {
        self.init(steps: paint.colors, code: paint.code, name: paint.name, shadow: shadow)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, color in
                color
                    .frame(height: stepHeight)
                    .overlay(alignment: .top) {
                        if index == 0 {
                            Circle().fill(WXColor.paperIvory).frame(width: 10, height: 10).padding(.top, 10)
                        }
                    }
            }
            ChipLabelBand(caption: code, value: name, captionSize: 9, valueSize: 14,
                          padding: EdgeInsets(top: 9, leading: 9, bottom: 9, trailing: 9), spacing: 4, alignment: .topLeading)
                .lineLimit(1)
                .frame(minHeight: 68)
                .background(WXColor.labelIvory)
        }
        .background(WXColor.labelIvory)
        .wxRounded(WXRadius.deckChip)
        .wxShadow(shadow, cornerRadius: WXRadius.deckChip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) theme")
    }
}

#Preview("FanDeck") {
    struct Card: Identifiable { let id: Int; let color: Color; let paint: String; let name: String }
    let cards = [
        Card(id: 0, color: WXColor.sageNoon, paint: "Sage Noon", name: "Habits"),
        Card(id: 1, color: WXColor.beachSand, paint: "Beach Hour", name: "Palette"),
        Card(id: 2, color: WXColor.deepTide, paint: "Deep Tide", name: "Battery"),
        Card(id: 3, color: WXColor.coralHour, paint: "Coral Hour", name: "Next Class")
    ]
    return FanDeck(cards, angles: [-27, -9, 9, 27], pivot: UnitPoint(x: 0.5, y: 2.15), cardSize: CGSize(width: 96, height: 138)) {
        DeckChip(color: $0.color, paint: $0.paint, name: $0.name)
    }
    .frame(height: 200)
    .frame(maxWidth: .infinity)
    .background(WXColor.paperIvory)
}
