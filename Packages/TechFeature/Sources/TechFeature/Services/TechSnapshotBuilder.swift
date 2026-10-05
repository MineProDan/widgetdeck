import CoreKit
import Foundation
import TechFeatureWidgetKit

/// Turns in-app readings into the three widget snapshots (T-06).
public enum TechSnapshotBuilder {
    public struct Output: Sendable, Equatable {
        public var battery: BatterySnapshot
        public var storage: StorageSnapshot?
        public var overview: SystemOverviewSnapshot
    }

    /// - Parameter includeProcessor: `false` when T-03 is off; the widget then shows "—" for CPU/RAM.
    public static func build(from metrics: SystemMetrics, includeProcessor: Bool, now: Date = .now) -> Output {
        let processor: ProcessorStatus? = includeProcessor && (metrics.cpuLoad != nil || metrics.memoryUsedBytes != nil)
            ? ProcessorStatus(cpuLoad: metrics.cpuLoad, memoryUsedBytes: metrics.memoryUsedBytes,
                              memoryTotalBytes: metrics.memoryTotalBytes, sampledAt: metrics.sampledAt)
            : nil
        return Output(
            battery: BatterySnapshot(battery: metrics.battery, generatedAt: now),
            storage: metrics.storage.map { StorageSnapshot(storage: $0, generatedAt: now) },
            overview: SystemOverviewSnapshot(battery: metrics.battery, storage: metrics.storage, thermal: metrics.thermal,
                                             processor: processor, generatedAt: now))
    }

    /// What a widget would visibly show, ignoring timestamps and CPU/RAM (which change every
    /// sample). A snapshot is only republished when this changes, or when sampling stops, so we
    /// don't burn the widgets' daily reload budget.
    public static func signature(of metrics: SystemMetrics) -> String {
        let level = metrics.battery.level.map { String(Int(($0 * 100).rounded())) } ?? "-"
        let free = metrics.storage.map { String($0.freeBytes / 100_000_000) } ?? "-"
        let week = metrics.storage?.weeklyFreeChangeBytes.map { String($0 / 100_000_000) } ?? "-"
        let hasEstimate = metrics.battery.estimatedFullAt != nil ? "e" : "-"
        return [level, metrics.battery.state.rawValue, hasEstimate, free, week, String(metrics.thermal.rawValue)]
            .joined(separator: "|")
    }
}

/// Where snapshots go. Abstracted for tests.
public protocol TechSnapshotPublishing: Sendable {
    func publish(_ output: TechSnapshotBuilder.Output) async
    /// Push pending reloads now (called when the app leaves the foreground).
    func flush() async
}

/// Production publisher: `WidgetReloadCoordinator` writes atomically to the App Group and reloads
/// only kinds whose bytes changed, debounced ≥ 60 s.
public struct CoordinatorSnapshotPublisher: TechSnapshotPublishing {
    private let coordinator: WidgetReloadCoordinator

    public init(coordinator: WidgetReloadCoordinator = WidgetReloadCoordinator()) {
        self.coordinator = coordinator
    }

    public func publish(_ output: TechSnapshotBuilder.Output) async {
        do {
            _ = try await coordinator.publish(output.battery)
            if let storage = output.storage { _ = try await coordinator.publish(storage) }
            _ = try await coordinator.publish(output.overview)
        } catch {
            // A failed write leaves the previous snapshot in place; widgets keep showing it.
            TechLog.logger.error("Tech snapshot publish failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func flush() async {
        await coordinator.flushNow()
    }
}
