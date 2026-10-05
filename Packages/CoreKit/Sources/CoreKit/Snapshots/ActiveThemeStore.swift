import Foundation
import os

/// The palette of the theme the user applied (Theme Sync, presets), in a small App Group file that
/// every widget reads to recolour its Paint Chip fields. Written only by the app
/// (`AppEnvironment.loadActiveTheme()`); the widget extension only reads it (Platform Rule 6).
/// No file = the standard Paint Chip colours.
public struct ActiveThemeSnapshot: Codable, Hashable, Sendable {
    public var themeID: UUID
    public var name: String
    /// Replaces the dark section paints (Deep Tide, Plum Dusk).
    public var primary: RGBAColor
    /// Replaces the light/warm section paints (Coral Hour, Sage Noon, Beach Sand).
    public var accent: RGBAColor
    public var generatedAt: Date

    public init(themeID: UUID, name: String, primary: RGBAColor, accent: RGBAColor, generatedAt: Date = .now) {
        self.themeID = themeID
        self.name = name
        self.primary = primary
        self.accent = accent
        self.generatedAt = generatedAt
    }

    /// Builds the snapshot from a stored theme. Returns nil when the theme lacks the two roles
    /// widgets need, so widgets keep their standard paints rather than guessing.
    public init?(theme: Theme) {
        guard let primary = theme.palette[.primary], let accent = theme.palette[.accent] ?? theme.palette[.primary] else {
            return nil
        }
        self.init(themeID: theme.id, name: theme.name, primary: primary, accent: accent, generatedAt: theme.updatedAt)
    }
}

public struct ActiveThemeStore: Sendable {
    public let url: URL
    private static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "ActiveTheme")

    public init(appGroup: AppGroupContainer = .shared) {
        url = appGroup.applicationSupportURL.appending(path: "ActiveTheme.json")
    }

    public func read() -> ActiveThemeSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ActiveThemeSnapshot.self, from: data)
    }

    /// Writes atomically, or removes the file when `snapshot` is nil (standard colours).
    /// Returns true when the stored value changed, so callers reload widgets only when needed.
    @discardableResult
    public func write(_ snapshot: ActiveThemeSnapshot?) -> Bool {
        let current = read()
        guard current != snapshot else { return false }
        do {
            if let snapshot {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            } else if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: url)
            }
            return true
        } catch {
            Self.logger.error("Active theme write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
