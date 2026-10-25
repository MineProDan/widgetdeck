import CoreKit
import DesignSystem
import SwiftUI

/// First-launch onboarding (P-06), built only from DesignSystem Paint Chip components.
/// Step 1 matches the Main artboard (`docs/design/mockup/screens/Main.png`).
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = OnboardingModel()
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.step != .celebration {
                topBar.padding(.horizontal, WXSpace.gutter)
            }
            Group {
                switch model.step {
                case .vibe: VibeStep(model: model, onUse: useVibe)
                case .sections: SectionsStep(model: model)
                case .preview: PreviewStep(model: model)
                case .addWidget: AddWidgetStep(model: model)
                case .celebration: CelebrationStep(model: model, onDone: finish)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                              removal: .opacity))
            .id(model.step)
        }
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45), value: model.step)
        .background(WXColor.paperIvory.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            // Back from the home screen after adding a widget: look for it straight away.
            if phase == .active, model.step == .addWidget {
                Task { await model.checkForWidgets() }
            }
        }
    }

    private var topBar: some View {
        HStack {
            if model.step > .vibe {
                Button { model.back() } label: {
                    Text("Back").wxLabel().padding(.vertical, 12).padding(.trailing, 12)
                }
                .buttonStyle(.plain)
            }
            WXPageDots(count: OnboardingModel.Step.dotCount, current: model.step.rawValue)
            Spacer()
            Button(action: finish) {
                Text("Skip").wxLabel().padding(.vertical, 12).padding(.leading, 12)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Closes setup. You can add widgets any time.")
        }
        .frame(minHeight: 44)
    }

    private func useVibe() {
        let deck = model.pickedDeck
        // Store it now so the next step already draws in the new deck; the rest (clearing a
        // Theme Sync palette, reloading widgets) runs async.
        WXDeck.select(deck)
        Task { await environment.applyDeck(deck) }
        model.advance()
    }

    private func finish() {
        model.finish()
        onFinish()
    }
}

// MARK: - 1 Vibe (Main artboard)

private struct VibeStep: View {
    @Bindable var model: OnboardingModel
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pick your vibe.").wxGrotesk(40).accessibilityAddTraits(.isHeader)
                Text("One theme styles the app and every widget you add. Change it any time in Settings.")
                    .wxBody(16, lineHeight: 1.4)
                    .frame(maxWidth: 300, alignment: .leading)
            }
            .padding(.horizontal, WXSpace.gutter)

            // Ten theme decks, flipped through like a swatch deck. Each strip is drawn in its own
            // colours, face and punch shape; the rest of the app switches when the user taps Use.
            DeckPicker(selection: $model.pickedDeckID)
                .frame(height: 330)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(model.pickedDeck.code) · \(model.pickedDeck.mood)").wxLabel()
                Text(model.pickedDeck.name).wxGrotesk(28, deck: model.pickedDeck)
            }
            .padding(.horizontal, WXSpace.gutter)
            .padding(.top, 24)

            Spacer(minLength: 16)

            VStack(spacing: 8) {
                WXPrimaryButton("Use \(model.pickedDeck.name)", action: onUse)
                Text("Or match your wallpaper later with Theme Sync.")
                    .wxBody(13, color: WXColor.inkSecondary)
                    .padding(.vertical, 6)
            }
            .padding(.horizontal, WXSpace.gutter)
            .padding(.bottom, 6)
        }
    }
}

// MARK: - 2 Sections

private struct SectionsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepLayout(title: "What's it for?",
                   subtitle: "Pick the sections you want on your home screen. The rest stay one tap away.") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 14) {
                ForEach(OnboardingModel.offeredSections, id: \.self) { section in
                    let isOn = model.sections.contains(section)
                    Button { model.toggle(section) } label: {
                        PaintChip(color: WXSection(section).color, field: .fixed(84),
                                  shadow: isOn ? .chipLifted : .chipRest) {
                            CheckKey(isOn: isOn)
                        } label: {
                            ChipLabelBand(caption: WXSection(section).paintName, value: section.title,
                                          captionSize: 9, valueSize: 17)
                        }
                        .frame(height: 156)
                        .offset(y: isOn ? -6 : 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.title)
                    .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.top, 12)

            Text(sectionBlurb).wxBody(15).padding(.top, 8)
        } footer: {
            WXPrimaryButton("Continue") { model.advance() }
        }
    }

    private var sectionBlurb: String {
        model.orderedSections.map(\.blurb).joined(separator: " ")
    }
}

// MARK: - 3 Live preview + just-in-time permissions

private struct PreviewStep: View {
    @Environment(AppEnvironment.self) private var environment
    @Bindable var model: OnboardingModel
    @State private var requesting: PermissionKind?

    var body: some View {
        StepLayout(title: "Here's your look.",
                   subtitle: "\(model.pickedDeck.name) paints every widget. Allow only what each section needs.") {
            HStack(spacing: 10) {
                ForEach(model.orderedSections, id: \.self) { section in
                    // Share the row, up to 96 pt each: four fixed 96 pt chips (414 pt) were wider
                    // than a 402 pt screen and pushed the whole step off both edges. The height
                    // grows with Dynamic Type so the colour field isn't squeezed by a taller band.
                    DeckChip(color: WXSection(section).color,
                             paint: WXSection(section).paintName, name: section.sampleWidget)
                        .frame(maxWidth: 96, minHeight: 138)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of \(model.orderedSections.map(\.sampleWidget).joined(separator: ", ")) in \(model.pickedDeck.name)")

            VStack(spacing: 10) {
                ForEach(model.orderedSections, id: \.self) { section in
                    permissionRows(for: section)
                }
            }
            .padding(.top, 8)
        } footer: {
            WXPrimaryButton("Continue") { model.advance() }
        }
        .onAppear { environment.permissions.refresh() }
    }

    @ViewBuilder
    private func permissionRows(for section: AppSection) -> some View {
        let color = WXSection(section).color
        switch section {
        case .student:
            permissionRow(.calendar, color: color, title: "Calendar",
                          meta: "Reads class times. Never writes.")
            permissionRow(.notifications, color: color, title: "Class reminders",
                          meta: "Before each class")
        case .aesthetic:
            ListRowChip(color: color, title: "Photos", meta: "You pick each one. No library access.") { EmptyView() }
        case .tech:
            ListRowChip(color: color, title: "Battery and storage", meta: "No permission needed") { EmptyView() }
        case .wellness:
            ListRowChip(color: color, title: "Habits and mood", meta: "No permission needed") { EmptyView() }
        }
    }

    private func permissionRow(_ kind: PermissionKind, color: Color, title: String, meta: String) -> some View {
        let status = environment.permissions.status(for: kind)
        return ListRowChip(color: color, title: title, meta: statusMeta(status, fallback: meta),
                           metaColor: status.isUsable ? WXColor.mossPositive : WXColor.inkSecondary) {
            if status.canRequest {
                // Keep the title fixed while the system prompt is up: swapping it for "…" made the
                // pill shrink with the old label still fading out behind it.
                WXPillButton("Allow") {
                    requesting = kind
                    Task {
                        _ = await environment.permissions.request(kind)
                        requesting = nil
                    }
                }
                .disabled(requesting != nil)
                .opacity(requesting == kind ? 0.5 : 1)
            } else if status.needsSettings {
                WXPillButton("Settings") {
                    UIApplication.shared.open(PermissionManager.settingsURL)
                }
            }
        }
    }

    private func statusMeta(_ status: PermissionStatus, fallback: String) -> String {
        if status.isUsable { return "Allowed" }
        if status.needsSettings { return "Off. Turn on in Settings" }
        return fallback
    }
}

// MARK: - 4 Add a widget

private struct AddWidgetStep: View {
    @Bindable var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlighted = 0

    private let steps: [(String, String)] = [
        ("Touch and hold", "an empty spot on your home screen"),
        ("Tap Edit", "top left, then Add Widget"),
        ("Search Widgetdeck", "and pick a size"),
        ("Tap Add Widget", "then come back here"),
    ]

    var body: some View {
        StepLayout(title: "Add your first widget.",
                   subtitle: "It takes four taps. We'll spot it when you come back.") {
            VStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    let color = WXSection(model.orderedSections[index % model.orderedSections.count]).color
                    ListRowChip(color: color, title: step.0, meta: step.1) {
                        Text("\(index + 1)").wxGrotesk(22, tabular: true, color: WXColor.inkSecondary)
                            .frame(width: 44)
                    }
                    // Highlight the current step by lifting it, not nudging it sideways: a sideways
                    // offset looks like a misaligned row in any still frame (e.g. screenshots).
                    .wxShadow(highlighted == index && !reduceMotion ? .chipLifted : WXShadow([]), cornerRadius: WXRadius.chip)
                    .zIndex(highlighted == index ? 1 : 0)
                }
            }
            .padding(.top, 8)

            if let message = model.widgetCheckMessage {
                Text(message).wxBody(14, color: WXColor.clayLink).padding(.top, 6)
            }
        } footer: {
            VStack(spacing: 8) {
                WXPrimaryButton(model.isCheckingWidgets ? "Checking…" : "I added one") {
                    Task { await model.checkForWidgets() }
                }
                Button { model.advance() } label: {
                    Text("Later").wxLabel().padding(.vertical, 12).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            // A slow walk through the four taps, as a guide.
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45)) {
                    highlighted = (highlighted + 1) % steps.count
                }
            }
        }
    }
}

// MARK: - 5 Celebration

private struct CelebrationStep: View {
    let model: OnboardingModel
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fanned = false

    private var chips: [PreviewChip] {
        model.orderedSections.map { PreviewChip(section: $0) }
    }

    private var angles: [Double] {
        switch chips.count {
        case 1: [0]
        case 2: [-9, 9]
        default: [-18, 0, 18]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 40)
            FanDeck(chips, angles: fanned ? angles : Array(repeating: 0, count: chips.count),
                    pivot: UnitPoint(x: 0.5, y: 2.15), cardSize: CGSize(width: 96, height: 138),
                    selectedID: chips.last?.id) { chip in
                DeckChip(color: WXSection(chip.section).color, paint: WXSection(chip.section).paintName,
                         name: chip.section.title)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text(model.detectedWidgetKinds.isEmpty ? "You're set." : "Nice. It's on.")
                    .wxGrotesk(40).accessibilityAddTraits(.isHeader)
                Text(model.detectedWidgetKinds.isEmpty
                     ? "Add a widget whenever you like. Your \(model.pickedDeck.name) theme is ready for it."
                     : "Your widget updates through the day. Habits and Mood widgets work right on the Home Screen: tap to tick a habit or log your mood.")
                    .wxBody(16, lineHeight: 1.4)
            }
            .padding(.horizontal, WXSpace.gutter)
            .padding(.top, 24)

            Spacer(minLength: 16)
            WXPrimaryButton("Start", action: onDone)
                .padding(.horizontal, WXSpace.gutter)
                .padding(.bottom, 6)
        }
        .onAppear {
            if reduceMotion { fanned = true } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.15)) { fanned = true }
            }
        }
    }

    private struct PreviewChip: Identifiable {
        let section: AppSection
        var id: String { section.rawValue }
    }
}

// MARK: - Shared layout

/// Title, subtitle, scrolling content and a pinned footer: the frame for steps 2–4.
private struct StepLayout<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).wxGrotesk(40).accessibilityAddTraits(.isHeader)
                    Text(subtitle).wxBody(16, lineHeight: 1.4)
                    content
                }
                .padding(.horizontal, WXSpace.gutter)
                .padding(.bottom, WXSpace.gutter)
            }
            .scrollIndicators(.hidden)
            footer
                .padding(.horizontal, WXSpace.gutter)
                .padding(.bottom, 6)
        }
    }
}

private extension AppSection {
    var blurb: String {
        switch self {
        case .student: "Student shows your next class and today's schedule."
        case .aesthetic: "Aesthetic matches widgets to your wallpaper and rotates your photos."
        case .tech: "Tech shows battery, storage and heat."
        case .wellness: "Wellness tracks habits and mood, with a breathing timer."
        }
    }

    var sampleWidget: String {
        switch self {
        case .student: "Next class"
        case .aesthetic: "Palette"
        case .tech: "Battery"
        case .wellness: "Habits"
        }
    }
}
