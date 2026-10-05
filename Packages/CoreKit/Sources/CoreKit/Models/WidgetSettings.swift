import Foundation

/// A user's saved customization for a widget kind + family (theme override and per-kind options).
/// (Named `WidgetSettings`, not `WidgetConfiguration`, to avoid clashing with WidgetKit.)
public struct WidgetSettings: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: WidgetKind
    public var family: WidgetFamilyKind
    public var themeOverrideID: UUID?
    /// Per-kind options as string key/values (e.g. `"calendarIDs": "a,b"`). Kept deliberately
    /// simple so it syncs cleanly through CloudKit and survives schema changes.
    public var settings: [String: String]
    public var updatedAt: Date

    public init(id: UUID = UUID(), kind: WidgetKind, family: WidgetFamilyKind, themeOverrideID: UUID? = nil,
                settings: [String: String] = [:], updatedAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.family = family
        self.themeOverrideID = themeOverrideID
        self.settings = settings
        self.updatedAt = updatedAt
    }
}
