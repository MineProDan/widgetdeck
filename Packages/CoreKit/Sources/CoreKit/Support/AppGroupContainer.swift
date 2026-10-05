import Foundation

/// Resolves the shared App Group directories used by the app, the widget extension and App Intents.
///
/// Layout:
/// ```
/// <AppGroup>/
///   Library/Application Support/Stores/     Core Data stores (Cloud.sqlite, Local.sqlite)
///   Library/Application Support/Snapshots/  Widget snapshots (<kind>.json)
///   Library/Caches/Images/                  Downsampled widget images (LRU, purgeable)
///   Library/Application Support/Exports/    Temporary JSON exports
/// ```
public struct AppGroupContainer: Sendable {
    /// Root directory of the container.
    public let rootURL: URL

    /// Creates a container rooted at an arbitrary directory (tests, previews).
    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// The real App Group container. Falls back to the app's own Application Support directory
    /// when the App Group entitlement is missing (unsigned simulator builds, unit tests), so the
    /// app keeps working locally instead of crashing.
    public static let shared: AppGroupContainer = {
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup) {
            return AppGroupContainer(rootURL: url)
        }
        let fallback = URL.applicationSupportDirectory.appending(path: "AppGroupFallback", directoryHint: .isDirectory)
        return AppGroupContainer(rootURL: fallback)
    }()

    /// A fresh, empty container in the temporary directory. Intended for tests and previews.
    public static func temporary() -> AppGroupContainer {
        AppGroupContainer(rootURL: FileManager.default.temporaryDirectory
            .appending(path: "AppGroup-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    public var applicationSupportURL: URL {
        rootURL.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }
    public var storesURL: URL { applicationSupportURL.appending(path: "Stores", directoryHint: .isDirectory) }
    public var snapshotsURL: URL { applicationSupportURL.appending(path: "Snapshots", directoryHint: .isDirectory) }
    public var exportsURL: URL { applicationSupportURL.appending(path: "Exports", directoryHint: .isDirectory) }
    public var cachesURL: URL { rootURL.appending(path: "Library/Caches", directoryHint: .isDirectory) }
    public var imageCacheURL: URL { cachesURL.appending(path: "Images", directoryHint: .isDirectory) }

    /// Shared `UserDefaults` suite (small flags only, e.g. remote flags).
    public var userDefaults: UserDefaults {
        UserDefaults(suiteName: AppIdentifiers.appGroup) ?? .standard
    }

    /// Creates `url` (and intermediate directories) if needed and returns it.
    @discardableResult
    public func ensureDirectory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
