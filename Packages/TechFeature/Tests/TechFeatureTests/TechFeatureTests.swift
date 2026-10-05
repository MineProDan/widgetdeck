import CoreKit
import Foundation
import Testing
@testable import TechFeature
@testable import TechFeatureWidgetKit

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

// MARK: - ChargeRateEstimator

@Suite("ChargeRateEstimator")
struct ChargeRateEstimatorTests {
    @Test func needsEnoughEvidence() {
        var estimator = ChargeRateEstimator()
        estimator.record(level: 0.50, at: t0)
        #expect(estimator.ratePerHour == nil)
        estimator.record(level: 0.51, at: t0.addingTimeInterval(60)) // 1 minute: too short
        #expect(estimator.ratePerHour == nil)
    }

    @Test func linearRate() throws {
        var estimator = ChargeRateEstimator()
        // 1 % per minute = 60 %/h.
        for minute in 0...10 {
            estimator.record(level: 0.40 + Double(minute) * 0.01, at: t0.addingTimeInterval(Double(minute) * 60))
        }
        let rate = try #require(estimator.ratePerHour)
        #expect(abs(rate - 0.6) < 0.0001)
        // 0.5 → 0.8 at 60 %/h = 30 min, 0.8 → 1.0 at 30 %/h = 40 min.
        let seconds = try #require(estimator.timeToFull(from: 0.5))
        #expect(abs(seconds - 70 * 60) < 1)
    }

    @Test func taperAboveEighty() throws {
        let seconds = try #require(ChargeRateEstimator.timeToFull(from: 0.9, ratePerHour: 0.6))
        #expect(abs(seconds - 20 * 60) < 1) // 10 % at half rate (30 %/h)
        #expect(ChargeRateEstimator.timeToFull(from: 1.0, ratePerHour: 0.6) == 0)
        #expect(ChargeRateEstimator.timeToFull(from: 0.5, ratePerHour: 0) == nil)
    }

    @Test func dropRestartsSessionAndWindowSlides() {
        var estimator = ChargeRateEstimator()
        estimator.record(level: 0.60, at: t0)
        estimator.record(level: 0.65, at: t0.addingTimeInterval(300))
        estimator.record(level: 0.55, at: t0.addingTimeInterval(360))
        #expect(estimator.readings.count == 1)
        estimator.record(level: 0.56, at: t0.addingTimeInterval(360 + 31 * 60))
        #expect(estimator.readings.count == 1) // the older reading fell out of the 30-min window
    }

    @Test func ignoresInvalidLevels() {
        var estimator = ChargeRateEstimator()
        estimator.record(level: -1, at: t0)
        estimator.record(level: .nan, at: t0)
        #expect(estimator.readings.isEmpty)
    }
}

// MARK: - Formatting

@Suite("Formatting")
struct FormattingTests {
    @Test(arguments: [(0.823, "82%"), (0.0, "0%"), (1.0, "100%"), (1.4, "100%"), (-0.2, "0%")])
    func percent(value: Double, expected: String) {
        #expect(TechFormat.percent(value) == expected)
    }

    @Test func unavailable() {
        #expect(TechFormat.percent(nil) == "—")
        #expect(TechFormat.percent(.nan) == "—")
        #expect(TechFormat.storage(nil) == "—")
        #expect(TechFormat.memory(nil) == "—")
        #expect(TechFormat.duration(nil) == "—")
    }

    @Test func bytes() {
        #expect(TechFormat.storage(118_400_000_000) == "118 GB")
        #expect(TechFormat.storage(9_440_000_000) == "9.4 GB")
        #expect(TechFormat.storage(512_000_000) == "512 MB")
        #expect(TechFormat.storageTotalNumber(255_900_000_000) == "256")
        #expect(TechFormat.storageWeeklyChange(-2_100_000_000) == "−2.1 GB wk")
        #expect(TechFormat.storageWeeklyChange(500_000_000) == "+0.5 GB wk")
        #expect(TechFormat.memory(3_328_599_654) == "3.1 GB")
        #expect(TechFormat.memoryTotal(5_900_000_000) == "5 GB")
        #expect(TechFormat.memoryTotal(6 * 1_073_741_824) == "6 GB")
    }

    @Test(arguments: [(4200.0, "1h 10m"), (900.0, "15m"), (20.0, "<1m"), (7200.0, "2h")])
    func durations(seconds: Double, expected: String) {
        #expect(TechFormat.duration(seconds) == expected)
    }

    @Test func asOf() {
        let text = TechFormat.asOf(t0, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
        #expect(text.hasPrefix("As of "))
    }

    @Test func batteryCopyAlwaysLabelsEstimate() {
        let charging = BatteryStatus(level: 0.82, state: .charging, estimatedFullAt: t0.addingTimeInterval(4200))
        #expect(BatteryCopy.cardTrend(charging, now: t0) == "Charging · est. 1h 10m")
        #expect(BatteryCopy.widgetTrend(charging, isLive: false, generatedAt: t0, now: t0) == "Est. 1h 10m to full")
        #expect(BatteryCopy.cardTrend(BatteryStatus(level: 0.5, state: .charging), now: t0) == "Charging · estimating")
        #expect(BatteryCopy.cardTrend(.unknown, now: t0) == "Not reported")
    }

    @Test func cardTrends() {
        #expect(TechCopy.cpu(current: 0.23, minuteAgo: 0.31) == ("Down from 31% · 1 min", .positive))
        #expect(TechCopy.cpu(current: 0.30, minuteAgo: 0.31).0 == "Steady · 1 min")
        #expect(TechCopy.cpu(current: nil, minuteAgo: nil).0 == "Measuring…")
        let storage = StorageStatus(totalBytes: 256_000_000_000, freeBytes: 118_000_000_000, weeklyFreeChangeBytes: -2_100_000_000)
        #expect(TechCopy.storage(storage) == ("Of 256 · −2.1 GB wk", .urgent))
        #expect(TechCopy.memory(used: 3_300_000_000, minuteAgo: 3_310_000_000, total: 6 * 1_073_741_824).0 == "Of 6 GB · steady")
    }
}

// MARK: - Chip catalog / device

@Suite("ChipCatalog")
struct ChipCatalogTests {
    @Test func bundledCatalogLoads() {
        let catalog = ChipCatalog.bundled
        #expect(catalog.version == 1)
        #expect(catalog.models.count >= 30)
        #expect(Set(catalog.models.map(\.identifier)).count == catalog.models.count)
    }

    @Test(arguments: [("iPhone11,2", "iPhone XS", "A12 Bionic"), ("iPhone15,2", "iPhone 14 Pro", "A16 Bionic"),
                      ("iPhone16,1", "iPhone 15 Pro", "A17 Pro"), ("iPhone18,1", "iPhone 17 Pro", "A19 Pro")])
    func lookup(identifier: String, name: String, chip: String) throws {
        let model = try #require(ChipCatalog.bundled.lookup(identifier))
        #expect(model.name == name)
        #expect(model.chip == chip)
    }

    @Test func unknownModelIsHonest() {
        let info = DeviceInfo.current(catalog: ChipCatalog(version: 1, models: []), systemVersion: "26.2")
        #expect(info.chip == nil)
        #expect(info.title == "iPhone" || info.title == "iPad")
    }

    @Test func deviceText() {
        let info = DeviceInfo(modelIdentifier: "iPhone15,2", name: "iPhone 14 Pro", chip: "A16 Bionic",
                              systemVersion: "26.5", coreCount: 6, memoryBytes: 6 * 1_073_741_824)
        #expect(info.title == "iPhone 14 Pro · A16 Bionic")
        #expect(info.detail == "iOS 26.5 · 6-core CPU · 6 GB")
    }
}

// MARK: - Snapshots and timelines

@Suite("Snapshots")
struct SnapshotTests {
    private let metrics = SystemMetrics(
        battery: BatteryStatus(level: 0.82, state: .charging, estimatedFullAt: t0.addingTimeInterval(4200), chargeRatePerHour: 0.3),
        storage: StorageStatus(totalBytes: 256_000_000_000, freeBytes: 118_000_000_000),
        thermal: .fair, cpuLoad: 0.23, memoryUsedBytes: 3_328_599_654, memoryTotalBytes: 6 * 1_073_741_824, sampledAt: t0)

    @Test func builderFillsAllSnapshots() throws {
        let output = TechSnapshotBuilder.build(from: metrics, includeProcessor: true, now: t0)
        #expect(output.battery.battery.level == 0.82)
        #expect(output.storage?.storage.freeBytes == 118_000_000_000)
        #expect(output.overview.thermal == .fair)
        let processor = try #require(output.overview.processor)
        #expect(processor.cpuLoad == 0.23)
        #expect(processor.sampledAt == t0)
    }

    @Test func processorOmittedWhenFlagOff() {
        let output = TechSnapshotBuilder.build(from: metrics, includeProcessor: false, now: t0)
        #expect(output.overview.processor == nil)
    }

    @Test func snapshotsRoundTripThroughStore() throws {
        let store = SnapshotStore(appGroup: .temporary())
        let output = TechSnapshotBuilder.build(from: metrics, includeProcessor: true, now: t0)
        let data = try store.write(output.overview)
        #expect(data.count < SnapshotStore.maxSize)
        #expect(store.read(SystemOverviewSnapshot.self) == output.overview)
        _ = try store.write(output.battery)
        #expect(store.read(BatterySnapshot.self) == output.battery)
    }

    @Test func signatureIgnoresTimeAndCPU() {
        var other = metrics
        other.sampledAt = t0.addingTimeInterval(5)
        other.cpuLoad = 0.9
        other.battery.estimatedFullAt = t0.addingTimeInterval(3000)
        #expect(TechSnapshotBuilder.signature(of: other) == TechSnapshotBuilder.signature(of: metrics))
        other.battery.level = 0.83
        #expect(TechSnapshotBuilder.signature(of: other) != TechSnapshotBuilder.signature(of: metrics))
    }

    @Test func chargingTimelineCountsDownEstimate() {
        let snapshot = BatterySnapshot(battery: metrics.battery, generatedAt: t0)
        let timeline = TechTimelineBuilder.battery(snapshot: snapshot, live: nil, now: t0)
        #expect(timeline.entries.count == 4) // now, +5, +10, +15 min
        #expect(timeline.entries.allSatisfy { $0.battery.level == 0.82 }) // never a projected level
    }

    @Test func liveReadingReprojectsEstimate() throws {
        let snapshot = BatterySnapshot(battery: metrics.battery, generatedAt: t0)
        let live = BatteryStatus(level: 0.97, state: .charging)
        let entry = try #require(TechTimelineBuilder.battery(snapshot: snapshot, live: live, now: t0).entries.first)
        #expect(entry.isLive)
        #expect(entry.battery.level == 0.97)
        let fullAt = try #require(entry.battery.estimatedFullAt)
        #expect(abs(fullAt.timeIntervalSince(t0) - 0.03 / 0.3 * 3600) < 1)
    }

    @Test func noDataRendersUnknownNotBlank() {
        let timeline = TechTimelineBuilder.battery(snapshot: nil, live: nil, now: t0)
        #expect(timeline.entries.count == 1)
        #expect(timeline.entries[0].battery.level == nil)
        #expect(TechTimelineBuilder.storage(snapshot: nil, now: t0).entries[0].storage == nil)
    }

    @Test func unpluggedDropsEstimate() {
        let snapshot = BatterySnapshot(battery: BatteryStatus(level: 0.5, state: .unplugged, estimatedFullAt: t0.addingTimeInterval(60)),
                                       generatedAt: t0)
        let entry = TechTimelineBuilder.battery(snapshot: snapshot, live: nil, now: t0).entries[0]
        #expect(entry.battery.estimatedFullAt == nil)
    }
}

// MARK: - Persistence

@Suite("MetricSampleStore")
struct MetricSampleStoreTests {
    @Test func coreDataPrunesAfterSevenDays() async throws {
        let stack = try await CoreDataStack.load(mode: .inMemory, contributors: [TechPersistenceModel.self])
        let store = CoreDataMetricSampleStore(stack: stack)
        let now = t0
        try await store.append(MetricSample(date: now.addingTimeInterval(-8 * 86_400), storageFreeBytes: 1))
        try await store.append(MetricSample(date: now.addingTimeInterval(-6.5 * 86_400), storageFreeBytes: 2))
        try await store.append(MetricSample(date: now, storageFreeBytes: 3))
        let removed = try await store.prune(olderThan: now.addingTimeInterval(-SystemMonitorService.retention))
        #expect(removed == 1)
        let oldest = try await store.oldest(since: now.addingTimeInterval(-7 * 86_400))
        #expect(oldest?.storageFreeBytes == 2)
    }
}

// MARK: - SystemMonitorService

private final class FakeReader: SystemReading, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var ticks = CPUTicks(busy: 0, idle: 0)

    var callCount: Int { lock.withLock { calls } }

    func cpuTicks() -> CPUTicks? {
        lock.withLock {
            calls += 1
            ticks = CPUTicks(busy: ticks.busy + 25, idle: ticks.idle + 75)
            return ticks
        }
    }

    func memoryUsedBytes() -> Int64? { 3_000_000_000 }
    func memoryTotalBytes() -> Int64 { 6 * 1_073_741_824 }
    func storage() -> StorageStatus? { StorageStatus(totalBytes: 256_000_000_000, freeBytes: 100_000_000_000) }
    func thermal() -> ThermalLevel { .nominal }
}

private actor RecordingPublisher: TechSnapshotPublishing {
    private(set) var published: [TechSnapshotBuilder.Output] = []
    private(set) var flushes = 0
    func publish(_ output: TechSnapshotBuilder.Output) { published.append(output) }
    func flush() { flushes += 1 }
}

@Suite("SystemMonitorService")
@MainActor
struct SystemMonitorServiceTests {
    private let device = DeviceInfo(modelIdentifier: "iPhone15,2", name: "iPhone 14 Pro", chip: "A16 Bionic",
                                    systemVersion: "26.2", coreCount: 6, memoryBytes: 6 * 1_073_741_824)

    @Test func samplingPausesWhenBackgrounded() async throws {
        let reader = FakeReader()
        let service = SystemMonitorService(reader: reader, publisher: nil, device: device, interval: .milliseconds(20),
                                           observesBattery: false, cpuMemoryEnabled: { true })
        service.setActive(true)
        #expect(service.isSampling)
        try await Task.sleep(for: .milliseconds(200))
        #expect(reader.callCount >= 2)
        #expect(service.metrics.cpuLoad == 0.25)

        service.setActive(false) // scenePhase left .active
        #expect(!service.isSampling)
        try await Task.sleep(for: .milliseconds(50))
        let paused = reader.callCount
        try await Task.sleep(for: .milliseconds(200))
        #expect(reader.callCount == paused)

        service.setActive(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(reader.callCount > paused)
        service.setActive(false)
    }

    @Test func flagOffSkipsMachReads() {
        let reader = FakeReader()
        let service = SystemMonitorService(reader: reader, publisher: nil, device: device, observesBattery: false,
                                           cpuMemoryEnabled: { false })
        service.sampleOnce()
        #expect(reader.callCount == 0)
        #expect(service.metrics.cpuLoad == nil)
        #expect(service.metrics.memoryUsedBytes == nil)
        #expect(service.metrics.storage?.freeBytes == 100_000_000_000)
    }

    @Test func chargingProducesEstimate() throws {
        let service = SystemMonitorService(reader: FakeReader(), publisher: nil, device: device, observesBattery: false)
        for minute in 0...5 {
            service.handleBattery(level: 0.5 + Double(minute) * 0.01, state: .charging, at: t0.addingTimeInterval(Double(minute) * 60))
        }
        let fullAt = try #require(service.metrics.battery.estimatedFullAt)
        #expect(fullAt > t0)
        service.handleBattery(level: 0.55, state: .unplugged, at: t0.addingTimeInterval(400))
        #expect(service.metrics.battery.estimatedFullAt == nil)
    }

    @Test func publishesOnlyOnVisibleChangeAndOnStop() async throws {
        let publisher = RecordingPublisher()
        let service = SystemMonitorService(reader: FakeReader(), publisher: publisher, device: device,
                                           interval: .milliseconds(20), observesBattery: false, cpuMemoryEnabled: { true })
        service.setActive(true)
        try await Task.sleep(for: .milliseconds(200))
        service.setActive(false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await publisher.published.count == 2) // first reading + final on stop
        #expect(await publisher.flushes == 1)
        #expect(await publisher.published.last?.overview.processor != nil)
    }
}
