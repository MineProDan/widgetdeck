import CoreKit
import DesignSystem
import Foundation
import Observation
import WidgetKit

/// First-launch onboarding (P-06): vibe → sections → live preview + just-in-time permissions →
/// "add a widget" guide → celebration. Completion is stored in the app's own defaults, so it
/// shows once per install (Delete All Data does not bring it back; reinstalling does).
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable, Comparable {
        case vibe, sections, preview, addWidget, celebration

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Page dots cover the four working steps; the celebration has none.
        static let dotCount = 4
    }

    /// Sections offered at launch (all four ship in 1.0).
    static let offeredSections: [AppSection] = [.student, .aesthetic, .wellness, .tech]

    static let completedKey = "onboarding.completed"
    static let sectionsKey = "onboarding.sections"

    var step: Step = .vibe
    var pickedPaintID: String = WXThemePaint.launchThemes[1].id
    var sections: Set<AppSection> = [.student, .aesthetic]
    /// Kinds of Widgetdeck widgets found on the home or lock screen, once detected.
    private(set) var detectedWidgetKinds: [String] = []
    private(set) var isCheckingWidgets = false
    /// Friendly message when the last widget check found nothing or failed.
    private(set) var widgetCheckMessage: String?

    private let defaults: UserDefaults
    private let configurations: @MainActor () async -> Result<[String], any Error>

    init(defaults: UserDefaults = .standard,
         configurations: @escaping @MainActor () async -> Result<[String], any Error> = OnboardingModel.currentWidgetKinds) {
        self.defaults = defaults
        self.configurations = configurations
    }

    var pickedPaint: WXThemePaint {
        WXThemePaint.launchThemes.first { $0.id == pickedPaintID } ?? WXThemePaint.launchThemes[1]
    }

    /// Sections in display order.
    var orderedSections: [AppSection] { Self.offeredSections.filter(sections.contains) }

    var isComplete: Bool { defaults.bool(forKey: Self.completedKey) }

    func toggle(_ section: AppSection) {
        if sections.contains(section) {
            // Keep at least one: the preview and the widget guide need something to show.
            guard sections.count > 1 else { return }
            sections.remove(section)
        } else {
            sections.insert(section)
        }
    }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Asks WidgetKit which of our widgets are installed. Moves on to the celebration on success.
    func checkForWidgets() async {
        guard !isCheckingWidgets else { return }
        isCheckingWidgets = true
        defer { isCheckingWidgets = false }
        switch await configurations() {
        case .success(let kinds):
            let ours = Set(WidgetKind.allCases.map(\.kindIdentifier))
            detectedWidgetKinds = kinds.filter(ours.contains)
            if detectedWidgetKinds.isEmpty {
                widgetCheckMessage = "No Widgetdeck widget yet. Add one, then come back here."
            } else {
                widgetCheckMessage = nil
                if step == .addWidget { step = .celebration }
            }
        case .failure:
            widgetCheckMessage = "Couldn't check your home screen just now. You can carry on and add a widget later."
        }
    }

    /// Stores completion and the chosen sections. Called from the celebration and from Skip.
    func finish() {
        defaults.set(true, forKey: Self.completedKey)
        defaults.set(orderedSections.map(\.rawValue), forKey: Self.sectionsKey)
        Analytics.shared.track(AnalyticsEvent("onboarding_completed", parameters: [
            "step": String(step.rawValue),
            "widget_added": detectedWidgetKinds.isEmpty ? "no" : "yes",
        ]))
    }

    /// The Theme saved when the user picks a vibe: lightest step is the background, darkest the
    /// primary (dark widget fields), third step the accent (warm/light fields).
    static func theme(for paint: WXThemePaint) -> Theme {
        func rgba(_ hex: UInt32) -> RGBAColor {
            RGBAColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                      blue: Double(hex & 0xFF) / 255)
        }
        let steps = paint.steps
        return Theme(
            // Stable per paint, so picking the same vibe twice (or on two devices) is one record.
            id: UUID(uuidString: "0B0A0D1E-0000-4000-8000-" + String(format: "%012X", paint.code.hashValueStable)) ?? UUID(),
            name: paint.name,
            source: .preset,
            palette: [
                .background: rgba(steps[0]),
                .surface: rgba(steps[1]),
                .accent: rgba(steps[2]),
                .primary: rgba(steps[3]),
                .textOnBackground: rgba(0x22232E),
                .textOnAccent: rgba(0x22232E),
            ],
            packID: "launch." + paint.code.replacingOccurrences(of: " ", with: "")
        )
    }

    /// Default detection: `WidgetCenter.getCurrentConfigurations`.
    static func currentWidgetKinds() async -> Result<[String], any Error> {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                continuation.resume(returning: result.map { $0.map(\.kind) }.mapError { $0 as any Error })
            }
        }
    }
}

private extension String {
    /// A deterministic (not per-launch-seeded) 48-bit hash for building stable preset IDs.
    var hashValueStable: UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash & 0xFFFF_FFFF_FFFF
    }
}
