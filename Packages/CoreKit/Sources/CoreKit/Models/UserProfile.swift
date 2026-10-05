import Foundation

/// The single local user profile. There are no accounts: iCloud identity is implicit.
public struct UserProfile: Identifiable, Hashable, Codable, Sendable {
    public enum Units: String, Codable, Sendable { case metric, imperial }

    public struct Preferences: Hashable, Codable, Sendable {
        /// Default reminder offsets in minutes before an event (15 min, 1 h, 1 day, …).
        public var reminderOffsetsMinutes: [Int]
        /// 1 = Sunday … 7 = Saturday (matches `Calendar.firstWeekday`).
        public var weekStartsOn: Int
        public var units: Units
        /// Hour at which a "day" begins for streaks (shift workers); 0 = midnight.
        public var dayStartsAtHour: Int

        public init(reminderOffsetsMinutes: [Int] = [15, 60, 1440], weekStartsOn: Int = Calendar.current.firstWeekday,
                    units: Units = Locale.current.measurementSystem == .metric ? .metric : .imperial,
                    dayStartsAtHour: Int = 0) {
            self.reminderOffsetsMinutes = reminderOffsetsMinutes
            self.weekStartsOn = min(max(weekStartsOn, 1), 7)
            self.units = units
            self.dayStartsAtHour = min(max(dayStartsAtHour, 0), 23)
        }
    }

    public var id: UUID
    /// Optional name shown in greetings. Stored cloud-encrypted.
    public var displayName: String?
    public var selectedSections: [AppSection]
    public var personaTags: [String]
    public var onboardingCompletedAt: Date?
    public var preferences: Preferences
    public var activeThemeID: UUID?
    public var updatedAt: Date

    public init(id: UUID = UUID(), displayName: String? = nil, selectedSections: [AppSection] = AppSection.allCases,
                personaTags: [String] = [], onboardingCompletedAt: Date? = nil,
                preferences: Preferences = Preferences(), activeThemeID: UUID? = nil, updatedAt: Date = .now) {
        self.id = id
        self.displayName = displayName
        self.selectedSections = selectedSections
        self.personaTags = personaTags
        self.onboardingCompletedAt = onboardingCompletedAt
        self.preferences = preferences
        self.activeThemeID = activeThemeID
        self.updatedAt = updatedAt
    }

    public var hasCompletedOnboarding: Bool { onboardingCompletedAt != nil }
}
