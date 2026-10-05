import Foundation
import os

/// Errors from `SnapshotStore`.
public enum SnapshotError: Error, Equatable, LocalizedError {
    case tooLarge(fileName: String, bytes: Int)
    case encodingFailed(fileName: String)
    case writeFailed(fileName: String)

    public var errorDescription: String? {
        switch self {
        case let .tooLarge(name, bytes): "Widget snapshot \(name) is \(bytes) bytes (limit \(SnapshotStore.maxSize))."
        case let .encodingFailed(name): "Couldn't encode widget snapshot \(name)."
        case let .writeFailed(name): "Couldn't save widget snapshot \(name)."
        }
    }
}

/// Reads and writes widget snapshots as JSON files in `AppGroup/Snapshots/`.
///
/// Writes are atomic (temp file + rename), so the widget extension never sees a half-written file.
/// Reads never throw: a missing, corrupt or outdated snapshot returns `nil` and the widget shows
/// its placeholder state.
public struct SnapshotStore: Sendable {
    /// Hard ceiling per snapshot. Widgets must stay tiny in memory.
    public static let maxSize = 50 * 1024

    public let directory: URL
    private static var logger: Logger { Logger(subsystem: AppIdentifiers.appBundleID, category: "Snapshots") }

    public init(appGroup: AppGroupContainer = .shared) {
        self.directory = appGroup.snapshotsURL
    }

    public func url<S: WidgetSnapshot>(for type: S.Type) -> URL {
        directory.appending(path: "\(S.fileName).json")
    }

    /// Deterministic encoding, so equal snapshots produce equal bytes (and equal hashes).
    public static func encode<S: WidgetSnapshot>(_ snapshot: S) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        do {
            return try encoder.encode(SnapshotEnvelope(schemaVersion: S.schemaVersion, snapshot: snapshot))
        } catch {
            throw SnapshotError.encodingFailed(fileName: S.fileName)
        }
    }

    /// Atomically writes `snapshot`.
    /// - Returns: the bytes written (used for change detection).
    /// - Throws: `SnapshotError.tooLarge` if the encoded snapshot exceeds `maxSize`.
    @discardableResult
    public func write<S: WidgetSnapshot>(_ snapshot: S) throws -> Data {
        let data = try Self.encode(snapshot)
        guard data.count <= Self.maxSize else { throw SnapshotError.tooLarge(fileName: S.fileName, bytes: data.count) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // .atomic = write to a temporary file, then rename over the old one.
            // Protection: widgets may render while the device is locked after first unlock.
            try data.write(to: url(for: S.self), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.logger.error("Snapshot write failed for \(S.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw SnapshotError.writeFailed(fileName: S.fileName)
        }
        return data
    }

    /// The stored snapshot, or `nil` if missing, unreadable or from another schema version.
    public func read<S: WidgetSnapshot>(_ type: S.Type) -> S? {
        guard let data = try? Data(contentsOf: url(for: type)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            let envelope = try decoder.decode(SnapshotEnvelope<S>.self, from: data)
            guard envelope.schemaVersion == S.schemaVersion else { return nil }
            return envelope.snapshot
        } catch {
            Self.logger.error("Snapshot decode failed for \(S.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Removes a snapshot (e.g. when its data source is disconnected).
    public func delete<S: WidgetSnapshot>(_ type: S.Type) {
        try? FileManager.default.removeItem(at: url(for: type))
    }
}
