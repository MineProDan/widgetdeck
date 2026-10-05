import CoreKit
import Foundation
import WidgetKit

// Timelines are built from app-written snapshots (plus, for Battery, a direct UIDevice read when
// the extension gets one). Nothing here fetches data. Widgets are not real-time: entries are
// precomputed and WidgetKit decides when to reload within its daily budget.

/// Timeline entry for the Battery widget.
public struct BatteryEntry: TimelineEntry, Sendable {
    public let date: Date
    public let battery: BatteryStatus
    /// `true` when the level was read directly in the widget process for this timeline.
    public let isLive: Bool
    /// When the underlying data was captured.
    public let generatedAt: Date

    public init(date: Date, battery: BatteryStatus, isLive: Bool, generatedAt: Date) {
        self.date = date
        self.battery = battery
        self.isLive = isLive
        self.generatedAt = generatedAt
    }

    public static func placeholder(at date: Date = .now) -> BatteryEntry {
        BatteryEntry(date: date, battery: BatteryStatus(level: 0.82, state: .charging,
                                                        estimatedFullAt: date.addingTimeInterval(70 * 60)),
                     isLive: true, generatedAt: date)
    }
}

/// Timeline entry for the Storage widget. `storage == nil` → "—" state.
public struct StorageEntry: TimelineEntry, Sendable {
    public let date: Date
    public let storage: StorageStatus?
    public let generatedAt: Date?

    public init(date: Date, storage: StorageStatus?, generatedAt: Date?) {
        self.date = date
        self.storage = storage
        self.generatedAt = generatedAt
    }

    public static func placeholder(at date: Date = .now) -> StorageEntry {
        StorageEntry(date: date, storage: StorageStatus(totalBytes: 256_000_000_000, freeBytes: 118_000_000_000,
                                                        weeklyFreeChangeBytes: -2_100_000_000),
                     generatedAt: date)
    }
}

/// Timeline entry for the System Overview widget. `snapshot == nil` → "—" state.
public struct SystemOverviewEntry: TimelineEntry, Sendable {
    public let date: Date
    public let snapshot: SystemOverviewSnapshot?

    public init(date: Date, snapshot: SystemOverviewSnapshot?) {
        self.date = date
        self.snapshot = snapshot
    }

    public static func placeholder(at date: Date = .now) -> SystemOverviewEntry {
        SystemOverviewEntry(date: date, snapshot: SystemOverviewSnapshot(
            battery: BatteryStatus(level: 0.82, state: .charging, estimatedFullAt: date.addingTimeInterval(70 * 60)),
            storage: StorageStatus(totalBytes: 256_000_000_000, freeBytes: 118_000_000_000),
            thermal: .nominal,
            processor: ProcessorStatus(cpuLoad: 0.23, memoryUsedBytes: 3_328_599_654,
                                       memoryTotalBytes: 6 * 1_073_741_824, sampledAt: date),
            generatedAt: date))
    }
}

/// Pure timeline builders (unit-tested).
public enum TechTimelineBuilder {
    /// Reload cadence requests. WidgetKit may stretch these to fit its refresh budget.
    public static let chargingReload: TimeInterval = 15 * 60
    public static let batteryReload: TimeInterval = 30 * 60
    public static let snapshotReload: TimeInterval = 60 * 60

    /// Merges a direct reading (if any) with the app's snapshot and precomputes entries.
    ///
    /// While charging, entries every 5 minutes count the "est." time-to-full down. The level shown
    /// stays the last measured one: we never project a level we didn't read.
    public static func battery(snapshot: BatterySnapshot?, live: BatteryStatus?, now: Date) -> Timeline<BatteryEntry> {
        var status: BatteryStatus
        let isLive = live != nil
        let generatedAt: Date
        if var live {
            generatedAt = now
            if live.state == .charging, let rate = snapshot?.battery.chargeRatePerHour, rate > 0, let level = live.level {
                // Re-project the app's observed rate from the fresher level.
                live.chargeRatePerHour = rate
                live.estimatedFullAt = now.addingTimeInterval(max(0, 1 - level) / rate * 3600)
            }
            status = live
        } else if let snapshot {
            generatedAt = snapshot.generatedAt
            status = snapshot.battery
        } else {
            return Timeline(entries: [BatteryEntry(date: now, battery: .unknown, isLive: false, generatedAt: now)],
                            policy: .after(now.addingTimeInterval(batteryReload)))
        }
        if status.state != .charging { status.estimatedFullAt = nil }

        guard status.state == .charging, let fullAt = status.estimatedFullAt, fullAt > now else {
            return Timeline(entries: [BatteryEntry(date: now, battery: status, isLive: isLive, generatedAt: generatedAt)],
                            policy: .after(now.addingTimeInterval(batteryReload)))
        }
        var entries: [BatteryEntry] = []
        var date = now
        while date < fullAt, date <= now.addingTimeInterval(chargingReload) {
            entries.append(BatteryEntry(date: date, battery: status, isLive: isLive, generatedAt: generatedAt))
            date = date.addingTimeInterval(5 * 60)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(chargingReload)))
    }

    public static func storage(snapshot: StorageSnapshot?, now: Date) -> Timeline<StorageEntry> {
        Timeline(entries: [StorageEntry(date: now, storage: snapshot?.storage, generatedAt: snapshot?.generatedAt)],
                 policy: .after(now.addingTimeInterval(snapshotReload)))
    }

    public static func systemOverview(snapshot: SystemOverviewSnapshot?, now: Date) -> Timeline<SystemOverviewEntry> {
        Timeline(entries: [SystemOverviewEntry(date: now, snapshot: snapshot)],
                 policy: .after(now.addingTimeInterval(snapshotReload)))
    }
}

// MARK: - Providers

public struct BatteryTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> BatteryEntry { .placeholder() }

    public func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        if context.isPreview { return completion(.placeholder()) }
        let snapshot = SnapshotStore().read(BatterySnapshot.self)
        completion(TechTimelineBuilder.battery(snapshot: snapshot, live: nil, now: .now).entries.first ?? .placeholder())
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let snapshot = SnapshotStore().read(BatterySnapshot.self)
        let deliver = UncheckedSendableBox(completion)
        Task { @MainActor in
            let live = LiveBatteryReader.read()
            deliver.value(TechTimelineBuilder.battery(snapshot: snapshot, live: live, now: .now))
        }
    }
}

public struct StorageTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> StorageEntry { .placeholder() }

    public func getSnapshot(in context: Context, completion: @escaping (StorageEntry) -> Void) {
        if context.isPreview { return completion(.placeholder()) }
        completion(TechTimelineBuilder.storage(snapshot: SnapshotStore().read(StorageSnapshot.self), now: .now).entries[0])
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<StorageEntry>) -> Void) {
        completion(TechTimelineBuilder.storage(snapshot: SnapshotStore().read(StorageSnapshot.self), now: .now))
    }
}

public struct SystemOverviewTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> SystemOverviewEntry { .placeholder() }

    public func getSnapshot(in context: Context, completion: @escaping (SystemOverviewEntry) -> Void) {
        if context.isPreview { return completion(.placeholder()) }
        completion(timeline().entries[0])
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<SystemOverviewEntry>) -> Void) {
        completion(timeline())
    }

    private func timeline() -> Timeline<SystemOverviewEntry> {
        TechTimelineBuilder.systemOverview(snapshot: SnapshotStore().read(SystemOverviewSnapshot.self), now: .now)
    }
}

/// WidgetKit's completion handlers aren't annotated `@Sendable`, but calling them from another
/// thread is documented as safe. The box lets us hop to the main actor for `UIDevice`.
struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
