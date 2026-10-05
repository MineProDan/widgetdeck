import Foundation

/// The four product sections. Named `AppSection` to avoid clashing with SwiftUI's `Section`.
public enum AppSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case tech
    case student
    case aesthetic
    case wellness

    public var id: String { rawValue }

    /// User-facing name.
    public var title: String {
        switch self {
        case .tech: "Tech"
        case .student: "Student"
        case .aesthetic: "Aesthetic"
        case .wellness: "Wellness"
        }
    }

    /// SF Symbol used for tabs and chips.
    public var systemImage: String {
        switch self {
        case .tech: "cpu"
        case .student: "graduationcap"
        case .aesthetic: "paintpalette"
        case .wellness: "leaf"
        }
    }

    /// Deep link that opens this section, e.g. `widgetx://section/tech`.
    public var deepLink: URL {
        URL(string: "\(AppIdentifiers.urlScheme)://section/\(rawValue)")!
    }

    /// Parses a deep link produced by `deepLink`.
    public init?(deepLink url: URL) {
        guard url.scheme == AppIdentifiers.urlScheme, url.host() == "section",
              let raw = url.pathComponents.dropFirst().first,
              let section = AppSection(rawValue: raw) else { return nil }
        self = section
    }
}
