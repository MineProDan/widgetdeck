import CoreKit
import Foundation
import Observation
import os
import TechFeatureWidgetKit
import UIKit

enum TechLog {
    static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Tech")
}

/// Samples the device every 5 s **only while the Tech screen is visible and the app is active**
/// (Platform Reality Rules 3 and 8). Battery comes from `UIDevice` notifications, not timers.
///
/// Main-actor isolated, so it's `Sendable` and safe to hand to SwiftUI.
@MainActor
@Observable
public final class SystemMonitorService {
    /// Latest readings. `nil` fields render as "—".
    public private(set) var metrics: SystemMetrics
    /// CPU load about a minute ago, for "Down from 31% · 1 min".
    public private(set) var cpuMinuteAgo: Double?
    /// Memory used about a minute ago, for "steady / rising / falling".
    public private(set) var memoryMinuteAgo: Int64?
    public private(set) var isSampling = false
    public private(set) var sampleCount = 0
    public let device: DeviceInfo
    /// T-03 flag, read once per start.
    public private(set) var cpuMemoryEnabled: Bool

    @ObservationIgnored private let reader: any SystemReading
    @ObservationIgnored private let store: any MetricSampleStore
    @ObservationIgnored private let publisher: (any TechSnapshotPublishing)?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let observesBattery: Bool
    @ObservationIgnored private let flagProvider: @Sendable () -> Bool
    @ObservationIgnored private let now: @Sendable () -> Date

    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    @ObservationIgnored private var batteryTask: Task<Void, Never>?
    @ObservationIgnored private var estimator = ChargeRateEstimator()
    @ObservationIgnored private var previousTicks: CPUTicks?
    @ObservationIgnored private var history: [(date: Date, cpu: Double?, memory: Int64?)] = []
    @ObservationIgnored private var lastPersisted: Date?
    @ObservationIgnored private var lastSignature: String?
    @ObservationIgnored private var weekBaseline: MetricSample?

    public static let sampleInterval: Duration = .seconds(5)
    public static let persistInterval: TimeInterval = 60
    public static let retention: TimeInterval = 7 * 24 * 60 * 60

    public init(reader: any SystemReading = DeviceSystemReader(),
                store: any MetricSampleStore = InMemoryMetricSampleStore(),
                publisher: (any TechSnapshotPublishing)? = CoordinatorSnapshotPublisher(),
                device: DeviceInfo? = nil,
                interval: Duration = SystemMonitorService.sampleInterval,
                observesBattery: Bool = true,
                cpuMemoryEnabled: @escaping @Sendable () -> Bool = { TechFeatureFlags.isCPUMemoryEnabled() },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.reader = reader
        self.store = store
        self.publisher = publisher
        self.interval = interval
        self.observesBattery = observesBattery
        self.flagProvider = cpuMemoryEnabled
        self.now = now
        self.cpuMemoryEnabled = cpuMemoryEnabled()
        self.device = device ?? DeviceInfo.current(systemVersion: UIDevice.current.systemVersion)
        self.metrics = SystemMetrics(memoryTotalBytes: reader.memoryTotalBytes(), sampledAt: now())
    }

    // MARK: Lifecycle

    /// Drive from `scenePhase == .active` and the screen's appear/disappear.
    public func setActive(_ active: Bool) {
        active ? start() : stop()
    }

    private func start() {
        guard samplingTask == nil else { return }
        isSampling = true
        cpuMemoryEnabled = flagProvider()
        previousTicks = nil
        if observesBattery { startBatteryObservation() }

        let interval = interval
        samplingTask = Task { [weak self] in
            await self?.loadWeekBaseline()
            while !Task.isCancelled {
                self?.sampleOnce()
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func stop() {
        guard samplingTask != nil else { return }
        samplingTask?.cancel()
        samplingTask = nil
        batteryTask?.cancel()
        batteryTask = nil
        if observesBattery { UIDevice.current.isBatteryMonitoringEnabled = false }
        isSampling = false

        // Leave the widgets the latest values (CPU/RAM "as of" now) and push reloads.
        guard sampleCount > 0, let publisher else { return }
        let output = TechSnapshotBuilder.build(from: metrics, includeProcessor: cpuMemoryEnabled, now: now())
        lastSignature = TechSnapshotBuilder.signature(of: metrics)
        Task {
            await publisher.publish(output)
            await publisher.flush()
        }
    }

    // MARK: Battery (T-01)

    private func startBatteryObservation() {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        updateBattery(level: device.batteryLevel, state: device.batteryState)
        let level = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIDevice.batteryLevelDidChangeNotification).map({ _ in () }) {
                self?.updateBattery(level: UIDevice.current.batteryLevel, state: UIDevice.current.batteryState)
            }
        }
        let state = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIDevice.batteryStateDidChangeNotification).map({ _ in () }) {
                self?.updateBattery(level: UIDevice.current.batteryLevel, state: UIDevice.current.batteryState)
            }
        }
        batteryTask = Task {
            await withTaskCancellationHandler {
                _ = await (level.value, state.value)
            } onCancel: {
                level.cancel()
                state.cancel()
            }
        }
    }

    private func updateBattery(level: Float, state: UIDevice.BatteryState) {
        handleBattery(level: level >= 0 ? Double(level) : nil, state: BatteryChargeState(state), at: now())
    }

    /// Applies a battery reading (public for tests).
    public func handleBattery(level: Double?, state: BatteryChargeState, at date: Date) {
        var status = BatteryStatus(level: level, state: state)
        if state == .charging, let level {
            estimator.record(level: level, at: date)
            if let rate = estimator.ratePerHour, let seconds = ChargeRateEstimator.timeToFull(from: level, ratePerHour: rate) {
                status.chargeRatePerHour = rate
                status.estimatedFullAt = date.addingTimeInterval(seconds)
            }
        } else {
            estimator.reset()
        }
        metrics.battery = status
        publishIfChanged()
    }

    // MARK: Sampling

    /// One 5-second tick (public for tests).
    public func sampleOnce() {
        let date = now()
        sampleCount += 1
        metrics.sampledAt = date
        metrics.thermal = reader.thermal()

        if var storage = reader.storage() {
            if let base = weekBaseline, let baseFree = base.storageFreeBytes {
                storage.weeklyFreeChangeBytes = storage.freeBytes - baseFree
            }
            metrics.storage = storage
        }

        if cpuMemoryEnabled {
            let ticks = reader.cpuTicks()
            if let ticks, let previous = previousTicks { metrics.cpuLoad = ticks.load(since: previous) ?? metrics.cpuLoad }
            previousTicks = ticks
            metrics.memoryUsedBytes = reader.memoryUsedBytes()
            metrics.memoryTotalBytes = reader.memoryTotalBytes()
        } else {
            metrics.cpuLoad = nil
            metrics.memoryUsedBytes = nil
        }

        history.append((date, metrics.cpuLoad, metrics.memoryUsedBytes))
        history.removeAll { date.timeIntervalSince($0.date) > 120 }
        let minuteAgo = history.last { date.timeIntervalSince($0.date) >= 60 }
        cpuMinuteAgo = minuteAgo?.cpu
        memoryMinuteAgo = minuteAgo?.memory

        persistIfDue(at: date)
        publishIfChanged()
    }

    private func publishIfChanged() {
        guard let publisher else { return }
        let signature = TechSnapshotBuilder.signature(of: metrics)
        guard signature != lastSignature else { return }
        lastSignature = signature
        let output = TechSnapshotBuilder.build(from: metrics, includeProcessor: cpuMemoryEnabled, now: now())
        Task { await publisher.publish(output) }
    }

    // MARK: Persistence (Local store, 7-day window)

    private func persistIfDue(at date: Date) {
        if let lastPersisted, date.timeIntervalSince(lastPersisted) < Self.persistInterval { return }
        lastPersisted = date
        let sample = MetricSample(date: date, batteryLevel: metrics.battery.level,
                                  storageFreeBytes: metrics.storage?.freeBytes,
                                  cpuLoad: cpuMemoryEnabled ? metrics.cpuLoad : nil,
                                  memoryUsedBytes: cpuMemoryEnabled ? metrics.memoryUsedBytes : nil)
        let store = store
        Task {
            do {
                try await store.append(sample)
                try await store.prune(olderThan: date.addingTimeInterval(-Self.retention))
            } catch {
                TechLog.logger.error("Metric sample save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The weekly storage trend compares against the oldest sample that is 6–7 days old.
    private func loadWeekBaseline() async {
        let date = now()
        do {
            try await store.prune(olderThan: date.addingTimeInterval(-Self.retention))
            let oldest = try await store.oldest(since: date.addingTimeInterval(-Self.retention))
            if let oldest, date.timeIntervalSince(oldest.date) >= 6 * 24 * 60 * 60 {
                weekBaseline = oldest
            }
        } catch {
            TechLog.logger.error("Metric history load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
