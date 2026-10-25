import DesignSystem
import SwiftUI

/// Settings → Theme: flip through the theme decks, preview one on a mini home screen, then use it.
/// Every deck is free and all of them are available to everyone.
struct ThemePickerView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: String = WXDeck.current.id
    @State private var isApplying = false

    private var deck: WXDeck { WXDeck.deck(id: selection) }
    private var isActive: Bool { selection == environment.deckID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WXPageHeader(title: "Theme", subtitle: "Colours, fonts and shapes for the app and every widget.")
                    .padding(.horizontal, WXSpace.gutter)

                DeckPicker(selection: $selection)
                    .frame(height: 330)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(deck.code) · \(deck.mood)").wxLabel()
                    Text(deck.name).wxGrotesk(28, deck: deck)
                    Text("Inspired by \(deck.inspiration.lowercasedFirst). \(deck.punch.displayName) punch holes.")
                        .wxBody(15)
                }
                .padding(.horizontal, WXSpace.gutter)
                .padding(.top, 12)

                DeckPreview(deck)
                    .padding(.horizontal, WXSpace.gutter)
                    .padding(.top, 20)

                Group {
                    if isActive {
                        Text("You're using \(deck.name).")
                            .wxBody(15, color: WXColor.inkSecondary)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    } else {
                        WXPrimaryButton("Use \(deck.name)") {
                            Task { await apply() }
                        }
                        .disabled(isApplying)
                    }
                }
                .padding(.horizontal, WXSpace.gutter)
                .padding(.top, 24)

                Text("Using a theme replaces a Theme Sync palette. You can match your wallpaper again afterwards; it keeps this theme's fonts and shapes.")
                    .wxBody(13, color: WXColor.inkSecondary)
                    .padding(.horizontal, WXSpace.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
            }
        }
        .background(WXColor.paperIvory.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // The page itself redraws in the new deck once it's applied.
        .id(environment.deckID)
    }

    private func apply() async {
        isApplying = true
        defer { isApplying = false }
        await environment.applyDeck(deck)
    }
}

private extension String {
    /// "Lo-fi study streams" from "Lo-fi study streams"; "café menus" from "Café menus".
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
