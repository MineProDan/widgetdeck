import CoreKit
import DesignSystem
import StudentFeature
import StudentFeatureWidgetKit
import SwiftUI

/// Home tab (mockup Home.png): the Flow hero (next class), the fan deck of widgets the user
/// actually has on their Home Screen, and one suggestion. Everything comes from real data;
/// sections that aren't set up yet turn into invitations instead of sample content.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = HomeModel()
    @State private var isShowingAddGuide = false
    @State private var isShowingWhy = false
    let open: (WXTab) -> Void
    let showSettings: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    TimelineView(.everyMinute) { context in
                        hero(now: context.date)
                    }
                    .padding(.top, 18)

                    deckSection.padding(.top, 24)

                    if let suggestion = model.suggestion(student: environment.studentStore, now: .now) {
                        suggestionChip(suggestion).padding(.top, 24)
                    }

                    #if DEBUG
                    NavigationLink {
                        DesignGalleryView()
                    } label: {
                        WXSectionHeader("Design gallery (debug)", accessory: "Open")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 32)
                    #endif
                }
                .padding(.horizontal, WXSpace.gutter)
                .padding(.bottom, WXSpace.gutter)
            }
            .scrollIndicators(.hidden)
            .background(WXColor.paperIvory.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        // Re-run once the Student store exists (it is created after the data stack loads).
        .task(id: environment.studentStore != nil) { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .sheet(isPresented: $isShowingAddGuide) { AddWidgetGuide() }
    }

    private func refresh() async {
        await model.refreshWidgets()
        // Refresh even before the Student tab has been opened, so the Flow card and the planner know
        // the calendar is connected (refresh never shows a permission prompt).
        if let store = environment.studentStore { await store.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            WXPageHeader(title: "Today", subtitle: HomeModel.subtitle(for: .now))
            Spacer(minLength: 0)
            Button(action: showSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(WXColor.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
            .padding(.top, 6)
        }
    }

    // MARK: Flow hero

    @ViewBuilder
    private func hero(now: Date) -> some View {
        let flow = HomeModel.flow(student: environment.studentStore, now: now)
        Button { open(.student) } label: {
            PaintChip(color: flow.color, field: .fixed(190), punchHole: .large, shadow: .heroCard) {
                ZStack(alignment: .topTrailing) {
                    ClockGlyph().opacity(0.9).padding(20)
                    if let progress = flow.progress {
                        FillBar(value: progress, color: WXColor.labelIvory, height: 6, trackOpacity: 0.32)
                            .fieldBottomBar(horizontal: 20, bottom: 20)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            } label: {
                ChipLabelBand(caption: flow.caption, value: flow.value, trailingValue: flow.trailing,
                              trend: flow.trend, trendColor: WXColor.clayLink, valueSize: 28,
                              padding: EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18), spacing: 6)
            }
            .frame(minHeight: 292)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your schedule")
    }

    // MARK: Fan deck

    @ViewBuilder
    private var deckSection: some View {
        let cards = model.deckCards
        if cards.isEmpty {
            WXSectionHeader("No Widgetdeck widgets yet", accessory: "How to add") { isShowingAddGuide = true }
            FanDeck(HomeModel.exampleCards, angles: HomeModel.angles(for: HomeModel.exampleCards.count),
                    pivot: UnitPoint(x: 0.5, y: 2.15), cardSize: CGSize(width: 96, height: 138)) {
                DeckChip(color: $0.color, paint: $0.paint, name: $0.name)
            }
            .compositingGroup() // fade the fan as one picture, not card by card
            .opacity(0.45)
            .accessibilityHidden(true)
            .deckFrame()
        } else {
            WXSectionHeader("On your home screen · \(model.liveCount) live", accessory: "Add more") { isShowingAddGuide = true }
            FanDeck(cards, angles: HomeModel.angles(for: cards.count),
                    pivot: UnitPoint(x: 0.5, y: 2.15), cardSize: CGSize(width: 96, height: 138)) {
                DeckChip(color: $0.color, paint: $0.paint, name: $0.name)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Widgets on your Home Screen: " + cards.map(\.name).joined(separator: ", "))
            .deckFrame()
        }
    }

    // MARK: Suggestion

    private func suggestionChip(_ suggestion: HomeModel.Suggestion) -> some View {
        PaintChip(axis: .horizontal, color: suggestion.color, field: .fixed(64), punchHole: .deck,
                  cornerRadius: WXRadius.chip, shadow: .actionChip) {
            EmptyView()
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.caption).wxLabel()
                    Text(suggestion.title).wxGrotesk(17)
                    Button { isShowingWhy = true } label: {
                        Text("Why am I seeing this").wxLabel().underline()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                WXPillButton(suggestion.action) { perform(suggestion) }
                    .padding(.trailing, 14)
            }
        }
        .frame(minHeight: 76)
        .alert("Why this suggestion", isPresented: $isShowingWhy) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(suggestion.why)
        }
    }

    private func perform(_ suggestion: HomeModel.Suggestion) {
        switch suggestion.kind {
        case .connectCalendar, .deadlines: open(.student)
        case .addWidget: isShowingAddGuide = true
        case .matchWallpaper: open(.aesthetic)
        }
    }
}

private extension View {
    /// The mockup's deck geometry: cards overlap the header slightly and the fan sits in 160 pt.
    func deckFrame() -> some View {
        padding(.top, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 160, alignment: .top)
            .padding(.top, -10)
    }
}

/// How to add a widget (same steps as onboarding and the support page).
private struct AddWidgetGuide: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = [
        "Touch and hold an empty spot on your Home Screen.",
        "Tap Edit (top left), then Add Widget.",
        "Search for Widgetdeck, pick a widget and size, and tap Add Widget."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add a widget").wxGrotesk(28)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(index + 1)").wxGrotesk(22, tabular: true, color: WXColor.inkSecondary)
                    Text(step).wxBody(16, color: WXColor.ink)
                }
            }
            Text("For the Lock Screen: touch and hold it, tap Customize → Lock Screen, then tap the widget area.")
                .wxBody(14)
            Spacer(minLength: 0)
            WXPrimaryButton("Done") { dismiss() }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WXColor.paperIvory.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}
