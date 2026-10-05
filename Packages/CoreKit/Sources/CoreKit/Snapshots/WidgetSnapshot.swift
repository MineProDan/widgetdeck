import Foundation

/// A small, precomputed Codable value that one widget kind renders.
///
/// The app (or an App Intent) builds snapshots and writes them with `SnapshotStore`; the widget
/// extension only ever **reads** them. Keep them under `SnapshotStore.maxSize` (50 KB): no images
/// (store downsampled image file names instead), no unbounded arrays.
public protocol WidgetSnapshot: Codable, Sendable {
    /// The widget kind this snapshot feeds (also its file name).
    static var kind: WidgetKind { get }
    /// Increment when the snapshot's shape changes incompatibly. Old files are then ignored
    /// (the widget shows its placeholder until the app writes a new snapshot).
    static var schemaVersion: Int { get }
    /// File name (without extension) in the Snapshots folder. Defaults to `kind.rawValue`; override
    /// only when one kind needs several snapshot files (e.g. one per configured instance).
    static var fileName: String { get }
    /// When the data was computed. Widgets show "updated 12m ago" if it's older than 2 h.
    var generatedAt: Date { get }
}

extension WidgetSnapshot {
    public static var schemaVersion: Int { 1 }
    public static var fileName: String { kind.rawValue }

    /// Whether the widget should label the data as stale (older than `threshold`, default 2 h).
    public func isStale(at date: Date = .now, threshold: TimeInterval = 2 * 60 * 60) -> Bool {
        date.timeIntervalSince(generatedAt) > threshold
    }
}

/// On-disk wrapper so the schema version travels with the payload.
struct SnapshotEnvelope<S: WidgetSnapshot>: Codable {
    let schemaVersion: Int
    let snapshot: S
}
