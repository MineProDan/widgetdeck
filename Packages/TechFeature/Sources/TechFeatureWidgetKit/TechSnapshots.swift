import CoreKit
import Foundation

/// Widget-safe entry point for the Tech section: snapshot types, formatting and widget views live
/// in this module so the widget extension doesn't link services it never uses.
public enum TechWidgetModule {
    public static let section: AppSection = .tech
}

/// Charging state, mirrored from `UIDevice.BatteryState` so snapshots stay Codable and UI-free.
public enum BatteryChargeState: String, Codable, Sendable, CaseIterable {
    case unknown, unplugged, charging, full

    /// Whether the device is connected to power.
    public var isPluggedIn: Bool { self == .charging || self == .full }
}

/// One battery reading. `level` is 0…1, or `nil` when iOS doesn't report it (Simulator,
/// monitoring disabled).
public struct BatteryStatus: Codable, Sendable, Equatable {
    public var level: Double?
    public var state: BatteryChargeState
    /// Our own estimate of when the battery reaches 100 %, from the observed charge rate.
    /// Only set while charging. Always labelled "est." in UI.
    public var estimatedFullAt: Date?
    /// Observed charge rate in fraction per hour (0.5 = 50 %/h), used to re-project the estimate
    /// when a newer level is read.
    public var chargeRatePerHour: Double?

    public init(level: Double?, state: BatteryChargeState, estimatedFullAt: Date? = nil,
                chargeRatePerHour: Double? = nil) {
        self.level = level
        self.state = state
        self.estimatedFullAt = estimatedFullAt
        self.chargeRatePerHour = chargeRatePerHour
    }

    public static let unknown = BatteryStatus(level: nil, state: .unknown)
}

/// Device storage totals (the whole volume; iOS doesn't expose a per-category breakdown).
public struct StorageStatus: Codable, Sendable, Equatable {
    public var totalBytes: Int64
    public var freeBytes: Int64
    /// Change in free space over roughly the last week (negative = space used up), if we have a
    /// sample that old.
    public var weeklyFreeChangeBytes: Int64?

    public init(totalBytes: Int64, freeBytes: Int64, weeklyFreeChangeBytes: Int64? = nil) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.weeklyFreeChangeBytes = weeklyFreeChangeBytes
    }

    public var usedBytes: Int64 { max(0, totalBytes - freeBytes) }

    /// Used share of the volume, 0…1, or `nil` when the total is unknown.
    public var usedFraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }
}

/// Mirror of `ProcessInfo.ThermalState`.
public enum ThermalLevel: Int, Codable, Sendable, CaseIterable {
    case nominal, fair, serious, critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }

    public var title: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }
}

/// The last CPU/memory reading taken in the app. Widgets can't sample these themselves, so they
/// show the value with its "as of" time.
public struct ProcessorStatus: Codable, Sendable, Equatable {
    /// 0…1 across all cores.
    public var cpuLoad: Double?
    public var memoryUsedBytes: Int64?
    public var memoryTotalBytes: Int64
    public var sampledAt: Date

    public init(cpuLoad: Double?, memoryUsedBytes: Int64?, memoryTotalBytes: Int64, sampledAt: Date) {
        self.cpuLoad = cpuLoad
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.sampledAt = sampledAt
    }
}

// MARK: - Snapshots

/// Feeds the Battery widget.
public struct BatterySnapshot: WidgetSnapshot, Equatable {
    public static var kind: WidgetKind { .battery }
    public var battery: BatteryStatus
    public var generatedAt: Date

    public init(battery: BatteryStatus, generatedAt: Date) {
        self.battery = battery
        self.generatedAt = generatedAt
    }
}

/// Feeds the Storage widget.
public struct StorageSnapshot: WidgetSnapshot, Equatable {
    public static var kind: WidgetKind { .storage }
    public var storage: StorageStatus
    public var generatedAt: Date

    public init(storage: StorageStatus, generatedAt: Date) {
        self.storage = storage
        self.generatedAt = generatedAt
    }
}

/// Feeds the System Overview widget.
public struct SystemOverviewSnapshot: WidgetSnapshot, Equatable {
    public static var kind: WidgetKind { .systemOverview }
    public var battery: BatteryStatus
    public var storage: StorageStatus?
    public var thermal: ThermalLevel
    /// `nil` when CPU/RAM sampling is switched off (feature flag `T-03`) or hasn't run yet.
    public var processor: ProcessorStatus?
    public var generatedAt: Date

    public init(battery: BatteryStatus, storage: StorageStatus?, thermal: ThermalLevel,
                processor: ProcessorStatus?, generatedAt: Date) {
        self.battery = battery
        self.storage = storage
        self.thermal = thermal
        self.processor = processor
        self.generatedAt = generatedAt
    }
}
