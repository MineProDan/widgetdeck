import CryptoKit
import Foundation
import WidgetKit

/// Spends the widget refresh budget (~40–70 reloads/day) only on real changes.
///
/// `publish(_:)` writes a snapshot and marks its kind dirty **only if the bytes changed** since the
/// last reload. Dirty kinds are reloaded together once the debounce interval (≥ 60 s) elapses.
///
/// Main app only. App Intents (which run briefly) should write with `SnapshotStore` and call
/// `WidgetCenter.shared.reloadTimelines(ofKind:)` for their own kind directly.
public actor WidgetReloadCoordinator {
    /// Receives WidgetKit kind identifiers to reload.
    public typealias Reloader = @Sendable ([String]) async -> Void

    /// Minimum debounce allowed in production.
    public static let minimumDebounce: Duration = .seconds(60)

    private let store: SnapshotStore
    private let debounce: Duration
    private let reloader: Reloader
    /// Content hash per snapshot file at the time of the last reload.
    private var reloadedHashes: [String: String] = [:]
    /// Latest content hash per snapshot file.
    private var currentHashes: [String: String] = [:]
    private var pendingFiles: [String: WidgetKind] = [:]
    private var flushTask: Task<Void, Never>?

    /// - Parameter debounce: clamped to at least 60 s.
    public init(store: SnapshotStore = SnapshotStore(), debounce: Duration = minimumDebounce,
                reloader: @escaping Reloader = WidgetReloadCoordinator.widgetCenterReloader) {
        self.init(store: store, unclampedDebounce: max(debounce, Self.minimumDebounce), reloader: reloader)
    }

    /// Unclamped initializer for tests.
    init(store: SnapshotStore, unclampedDebounce: Duration, reloader: @escaping Reloader) {
        self.store = store
        self.debounce = unclampedDebounce
        self.reloader = reloader
    }

    /// Reloads through `WidgetCenter`.
    public static let widgetCenterReloader: Reloader = { kinds in
        await MainActor.run {
            for kind in kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        }
    }

    /// Writes `snapshot` and schedules a reload of its kind if the content changed.
    /// - Returns: `true` if the content differs from what widgets last loaded.
    @discardableResult
    public func publish<S: WidgetSnapshot>(_ snapshot: S) throws -> Bool {
        let data = try store.write(snapshot)
        return markChanged(kind: S.kind, fileName: S.fileName, contentHash: Self.hash(data))
    }

    /// Records a content change for a snapshot written elsewhere.
    @discardableResult
    public func markChanged(kind: WidgetKind, fileName: String, contentHash: String) -> Bool {
        currentHashes[fileName] = contentHash
        guard reloadedHashes[fileName] != contentHash else {
            // Back to what the widget already shows: nothing to reload.
            pendingFiles[fileName] = nil
            return false
        }
        pendingFiles[fileName] = kind
        scheduleFlush()
        return true
    }

    /// Reloads all pending kinds immediately (e.g. when the app moves to the background).
    public func flushNow() async {
        flushTask?.cancel()
        flushTask = nil
        await flush()
    }

    /// Kinds waiting for the debounce to elapse (for diagnostics and tests).
    public var pendingKinds: Set<WidgetKind> { Set(pendingFiles.values) }

    private func scheduleFlush() {
        guard flushTask == nil else { return } // Already scheduled: changes coalesce into it.
        let delay = debounce
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.flushFromTimer()
        }
    }

    private func flushFromTimer() async {
        flushTask = nil
        await flush()
    }

    private func flush() async {
        guard !pendingFiles.isEmpty else { return }
        let kinds = Set(pendingFiles.values)
        for fileName in pendingFiles.keys { reloadedHashes[fileName] = currentHashes[fileName] }
        pendingFiles.removeAll()
        await reloader(kinds.map(\.kindIdentifier).sorted())
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
