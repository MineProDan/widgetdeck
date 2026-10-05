import Foundation

/// Every widget kind in the product plan. The raw value is the WidgetKit `kind` string
/// **and** the snapshot file name, so it must never change once shipped.
public enum WidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    // Shell
    case welcome
    // Tech (T-05)
    case battery, systemOverview, storage
    // Student (S-03, S-05)
    case nextClass, todaySchedule, assignments
    // Aesthetic (A-01, A-02, A-06)
    case photo, palette, moodBoard
    // Wellness (W-01..W-04)
    case quote, affirmation, habits, mood, breathe, streak
    // Cross-section (P-11)
    case flow

    public var id: String { rawValue }

    /// WidgetKit kind string (`io.github.mineprodan.iospremium.widget.<rawValue>`).
    public var kindIdentifier: String { "\(AppIdentifiers.appBundleID).widget.\(rawValue)" }

    /// Owning section, or `nil` for shell/cross-section widgets.
    public var section: AppSection? {
        switch self {
        case .battery, .systemOverview, .storage: .tech
        case .nextClass, .todaySchedule, .assignments: .student
        case .photo, .palette, .moodBoard: .aesthetic
        case .quote, .affirmation, .habits, .mood, .breathe, .streak: .wellness
        case .welcome, .flow: nil
        }
    }
}

/// Widget family, mirrored from WidgetKit so CoreKit stays UI-free and Codable.
public enum WidgetFamilyKind: String, Codable, CaseIterable, Sendable {
    case systemSmall, systemMedium, systemLarge, systemExtraLarge
    case accessoryCircular, accessoryRectangular, accessoryInline

    /// Whether the family is a Lock Screen / StandBy accessory.
    public var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }
}
