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

    @Test(arguments: WXThemePaint.launchThemes)
    func vibeThemeFeedsWidgetsAndPassesContrast(paint: WXThemePaint) throws {
        let theme = OnboardingModel.theme(for: paint)
        // Stable ID: picking the same vibe twice is one record (CloudKit has no unique constraints).
        #expect(theme.id == OnboardingModel.theme(for: paint).id)
        let snapshot = try #require(ActiveThemeSnapshot(theme: theme))
        #expect(snapshot.primary == theme.palette[.primary])
        #expect(snapshot.accent == theme.palette[.accent])
        // Label text sits on Label Ivory, never on fields; the background role must still carry ink.
        let ink = try #require(theme.palette[.textOnBackground])
        let background = try #require(theme.palette[.background])
        #expect(ContrastChecker.ratio(ink, background) >= 4.5)
    }

    @Test func launchThemeIDsAreDistinct() {
        let ids = Set(WXThemePaint.launchThemes.map { OnboardingModel.theme(for: $0).id })
        #expect(ids.count == WXThemePaint.launchThemes.count)
    }
}
