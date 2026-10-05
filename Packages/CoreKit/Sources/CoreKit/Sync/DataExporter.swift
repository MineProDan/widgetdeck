import Foundation

/// A feature's contribution to "Export my data".
public protocol DataExportContributor: Sendable {
    /// Top-level key in the export JSON (e.g. `"wellness"`).
    var exportKey: String { get }
    /// A JSON document (object or array) with the feature's user data.
    func exportJSON() async throws -> Data
}

/// Writes a single human-readable JSON file with everything the user created (P-08).
public struct DataExporter: Sendable {
    private let stack: CoreDataStack
    private let appGroup: AppGroupContainer
    private let contributors: [any DataExportContributor]

    public init(stack: CoreDataStack, appGroup: AppGroupContainer = .shared, contributors: [any DataExportContributor] = []) {
        self.stack = stack
        self.appGroup = appGroup
        self.contributors = contributors
    }

    private struct CoreExport: Encodable {
        let exportedAt: Date
        let app: String
        let profile: [UserProfile]
        let themes: [Theme]
        let widgetConfigurations: [WidgetSettings]
    }

    /// Builds the export and returns the file URL (in the App Group `Exports/` folder).
    public func export(now: Date = .now) async throws -> URL {
        let core = CoreExport(
            exportedAt: now,
            app: AppIdentifiers.appBundleID,
            profile: try await RecordStore<UserProfile>(stack: stack).fetchAll(),
            themes: try await RecordStore<Theme>(stack: stack).fetchAll(),
            widgetConfigurations: try await RecordStore<WidgetSettings>(stack: stack).fetchAll()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        var root = try JSONSerialization.jsonObject(with: encoder.encode(core)) as? [String: Any] ?? [:]
        for contributor in contributors {
            let data = try await contributor.exportJSON()
            root[contributor.exportKey] = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
        let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])

        let directory = try appGroup.ensureDirectory(appGroup.exportsURL)
        // Keep only the newest export: older copies of the user's data shouldn't pile up on disk.
        for old in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: old)
        }
        let stamp = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate])
        let url = directory.appending(path: "Widgetdeck-Export-\(stamp).json")
        try output.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
