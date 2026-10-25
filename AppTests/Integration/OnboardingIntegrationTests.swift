import CoreKit
import DesignSystem
import Foundation
import Testing
@testable import WidgetX

@MainActor
@Suite("Onboarding (P-06)")
struct OnboardingIntegrationTests {
    private func makeDefaults() -> UserDefaults {
        let name = "onboarding.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func keepsAtLeastOneSection() {
        let model = OnboardingModel(defaults: makeDefaults(), configurations: { .success([]) })
        model.sections = [.tech]
        model.toggle(.tech)
        #expect(model.sections == [.tech])
        model.toggle(.student)
        #expect(model.orderedSections == [.student, .tech])
    }

    @Test func detectsOnlyOurWidgetsAndCelebrates() async {
        let model = OnboardingModel(defaults: makeDefaults(), configurations: {
            .success(["com.other.app.widget", WidgetKind.battery.kindIdentifier])
        })
        model.step = .addWidget
        await model.checkForWidgets()
        #expect(model.detectedWidgetKinds == [WidgetKind.battery.kindIdentifier])
        #expect(model.step == .celebration)
        #expect(model.widgetCheckMessage == nil)
    }

    @Test func noWidgetKeepsGuideWithFriendlyMessage() async {
        let model = OnboardingModel(defaults: makeDefaults(), configurations: { .success(["com.other.app.widget"]) })
        model.step = .addWidget
        await model.checkForWidgets()
        #expect(model.step == .addWidget)
        #expect(model.widgetCheckMessage?.contains("No Widgetdeck widget yet") == true)
    }

    @Test func detectionFailureIsFriendly() async {
        struct Boom: Error {}
        let model = OnboardingModel(defaults: makeDefaults(), configurations: { .failure(Boom()) })
        model.step = .addWidget
        await model.checkForWidgets()
        #expect(model.step == .addWidget)
        #expect(model.widgetCheckMessage?.hasPrefix("Couldn't check") == true)
    }

    @Test func finishPersistsCompletionAndSections() {
        let defaults = makeDefaults()
        let model = OnboardingModel(defaults: defaults, configurations: { .success([]) })
        #expect(!model.isComplete)
        model.sections = [.tech, .student]
        model.finish()
        #expect(defaults.bool(forKey: OnboardingModel.completedKey))
        #expect(defaults.stringArray(forKey: OnboardingModel.sectionsKey) == ["student", "tech"])
        #expect(OnboardingModel(defaults: defaults).isComplete)
    }

    @Test func vibeStepOffersEveryDeck() {
        let model = OnboardingModel(defaults: makeDefaults(), configurations: { .success([]) })
        #expect(WXDeck.all.contains(model.pickedDeck))
        model.pickedDeckID = WXDeck.pocketArcade.id
        #expect(model.pickedDeck == .pocketArcade)
        model.pickedDeckID = "not-a-deck"
        #expect(model.pickedDeck == .paintChip, "unknown ids fall back to the default deck")
    }
}
