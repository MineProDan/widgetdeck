import CoreKit
import Foundation
import TechFeatureWidgetKit

/// Everything the Tech screen shows at one moment. `nil` fields render as "—".
public struct SystemMetrics: Sendable, Equatable {
    public var battery: BatteryStatus
    public var storage: StorageStatus?
    public var thermal: ThermalLevel
    /// 0…1 across all cores. `nil` until two CPU readings exist, or when T-03 is off.
    public var cpuLoad: Double?
    public var memoryUsedBytes: Int64?
    public var memoryTotalBytes: Int64
    public var sampledAt: Date

    public init(battery: BatteryStatus = .unknown, storage: StorageStatus? = nil, thermal: ThermalLevel = .nominal,
                cpuLoad: Double? = nil, memoryUsedBytes: Int64? = nil,
                memoryTotalBytes: Int64 = Int64(ProcessInfo.processInfo.physicalMemory), sampledAt: Date = .now) {
        self.battery = battery
        self.storage = storage
        self.thermal = thermal
        self.cpuLoad = cpuLoad
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.sampledAt = sampledAt
    }
}

/// A persisted reading (CoreKit "Local" store, never synced, pruned after 7 days).
/// Used for the storage weekly trend; CPU/memory values are kept only when T-03 is on.
public struct MetricSample: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var batteryLevel: Double?
    public var storageFreeBytes: Int64?
    public var cpuLoad: Double?
    public var memoryUsedBytes: Int64?

    public init(id: UUID = UUID(), date: Date, batteryLevel: Double? = nil, storageFreeBytes: Int64? = nil,
                cpuLoad: Double? = nil, memoryUsedBytes: Int64? = nil) {
        self.id = id
        self.date = date
        self.batteryLevel = batteryLevel
        self.storageFreeBytes = storageFreeBytes
        self.cpuLoad = cpuLoad
        self.memoryUsedBytes = memoryUsedBytes
    }
}

/// This device: marketing name and chip from the bundled catalog, plus live OS/core/RAM facts.
public struct DeviceInfo: Sendable, Equatable {
    public var modelIdentifier: String
    public var name: String
    /// `nil` when the model isn't in the catalog (newer than this build).
    public var chip: String?
    public var systemVersion: String
    public var coreCount: Int
    public var memoryBytes: Int64

    public init(modelIdentifier: String, name: String, chip: String?, systemVersion: String,
                coreCount: Int, memoryBytes: Int64) {
        self.modelIdentifier = modelIdentifier
        self.name = name
        self.chip = chip
        self.systemVersion = systemVersion
        self.coreCount = coreCount
        self.memoryBytes = memoryBytes
    }

    /// "iPhone 14 Pro · A16 Bionic"
    public var title: String {
        guard let chip else { return name }
        return "\(name) · \(chip)"
    }

    /// "iOS 26.5 · 6-core CPU · 6 GB"
    public var detail: String {
        "iOS \(systemVersion) · \(coreCount)-core CPU · \(TechFormat.memoryTotal(memoryBytes))"
    }

    /// Reads the current device. Model lookup uses the bundled catalog (T-04).
    public static func current(catalog: ChipCatalog = .bundled, systemVersion: String) -> DeviceInfo {
        let identifier = modelIdentifier()
        let entry = catalog.lookup(identifier)
        return DeviceInfo(modelIdentifier: identifier,
                          name: entry?.name ?? ChipCatalog.fallbackName(for: identifier),
                          chip: entry?.chip,
                          systemVersion: systemVersion,
                          coreCount: ProcessInfo.processInfo.processorCount,
                          memoryBytes: Int64(ProcessInfo.processInfo.physicalMemory))
    }

    /// `utsname.machine` ("iPhone15,2"). In the Simulator that's the Mac's architecture, so the
    /// simulated model comes from `SIMULATOR_MODEL_IDENTIFIER`.
    static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// Model identifier → marketing name + chip (bundled `ChipCatalog.json`, iPhone XS onward).
public struct ChipCatalog: Codable, Sendable, Equatable {
    public struct Model: Codable, Sendable, Equatable {
        public var identifier: String
        public var name: String
        public var chip: String
    }

    public var version: Int
    public var models: [Model]

    public init(version: Int, models: [Model]) {
        self.version = version
        self.models = models
    }

    public func lookup(_ identifier: String) -> Model? {
        models.first { $0.identifier == identifier }
    }

    /// Unknown models still get an honest name: "iPhone" / "iPad", never a guessed chip.
    static func fallbackName(for identifier: String) -> String {
        if identifier.hasPrefix("iPad") { return "iPad" }
        return "iPhone"
    }

    /// The catalog shipped in the package. Empty (never crashes) if the resource is missing.
    public static let bundled: ChipCatalog = {
        guard let url = Bundle.module.url(forResource: "ChipCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(ChipCatalog.self, from: data) else {
            return ChipCatalog(version: 0, models: [])
        }
        return catalog
    }()
}

/// Feature flags for this section. `T-03` (CPU/memory) is an App Review risk, so it ships behind
/// a flag the app can turn off remotely (value written to the App Group by the app's flag loader).
public enum TechFeatureFlags {
    public static let cpuMemoryKey = "flag.T-03.cpuMemory"

    /// Defaults to on when no remote value has been written.
    public static func isCPUMemoryEnabled(defaults: UserDefaults = AppGroupContainer.shared.userDefaults) -> Bool {
        guard defaults.object(forKey: cpuMemoryKey) != nil else { return true }
        return defaults.bool(forKey: cpuMemoryKey)
    }
}
