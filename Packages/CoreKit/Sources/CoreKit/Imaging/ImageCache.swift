import CryptoKit
import Foundation
import os

/// Disk cache for downsampled images in the App Group `Caches/Images` directory.
///
/// - Least-recently-used eviction once the total exceeds `capacity` (default 200 MB).
/// - Recency is the file's modification date, refreshed on every read.
/// - Excluded from backup; lives under Caches so iOS may purge it. Callers must always be able to
///   re-create an entry (re-download or re-import) and widgets must render a fallback if missing.
public actor ImageCache {
    public static let defaultCapacity = 200 * 1024 * 1024

    public nonisolated let directory: URL
    public nonisolated let capacity: Int
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "ImageCache")

    public init(directory: URL = AppGroupContainer.shared.imageCacheURL, capacity: Int = ImageCache.defaultCapacity,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.capacity = max(0, capacity)
        self.now = now
    }

    /// Stable key for a widget image: `(assetID, family, scale)`.
    public nonisolated static func key(assetID: String, family: WidgetFamilyKind, pixelSize: PixelSize) -> String {
        "\(assetID)|\(family.rawValue)|\(pixelSize)"
    }

    /// File URL for `key` (whether or not it exists). Widgets read this path directly.
    public nonisolated func fileURL(forKey key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: digest + ".img")
    }

    /// Stores `data` under `key`, then evicts least-recently-used entries if over capacity.
    @discardableResult
    public func store(_ data: Data, forKey key: String) throws -> URL {
        try prepareDirectory()
        let url = fileURL(forKey: key)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        touch(url)
        evict(toFit: capacity, keeping: url)
        return url
    }

    /// Cached data, refreshing its recency. `nil` if absent.
    public func data(forKey key: String) -> Data? {
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        touch(url)
        return data
    }

    public func contains(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(forKey: key).path(percentEncoded: false))
    }

    public func remove(_ key: String) {
        try? FileManager.default.removeItem(at: fileURL(forKey: key))
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Total bytes on disk.
    public func totalSize() -> Int {
        entries().reduce(0) { $0 + $1.size }
    }

    /// Trims the cache to half its capacity when free space for important data drops below
    /// `threshold` bytes (default 500 MB). Call on launch and when the app becomes active.
    /// - Returns: whether a purge happened.
    @discardableResult
    public func purgeIfLowStorage(threshold: Int64 = 500 * 1024 * 1024) -> Bool {
        let values = try? directory.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage, available < threshold else { return false }
        evict(toFit: capacity / 2, keeping: nil)
        logger.info("Low storage (\(available) bytes free): trimmed image cache")
        return true
    }

    // MARK: Internals

    private struct Entry {
        let url: URL
        let size: Int
        let lastUsed: Date
    }

    private func prepareDirectory() throws {
        var url = directory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path(percentEncoded: false))
    }

    private func entries() -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return Entry(url: url, size: values.fileSize ?? 0, lastUsed: values.contentModificationDate ?? .distantPast)
        }
    }

    /// Deletes least-recently-used files until the total is ≤ `limit`, never deleting `keeping`.
    private func evict(toFit limit: Int, keeping: URL?) {
        var all = entries()
        var total = all.reduce(0) { $0 + $1.size }
        guard total > limit else { return }
        all.sort { $0.lastUsed < $1.lastUsed }
        for entry in all where total > limit {
            if let keeping, entry.url.standardizedFileURL == keeping.standardizedFileURL { continue }
            do {
                try FileManager.default.removeItem(at: entry.url)
                total -= entry.size
            } catch {
                logger.error("Eviction failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
