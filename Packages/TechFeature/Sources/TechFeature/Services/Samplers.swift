import Darwin
import Foundation
import TechFeatureWidgetKit

/// Cumulative CPU ticks summed over all cores (from `host_processor_info`). Load is the busy share
/// of the ticks that elapsed between two readings, so one reading alone says nothing.
public struct CPUTicks: Sendable, Equatable {
    public var busy: UInt64
    public var idle: UInt64

    public init(busy: UInt64, idle: UInt64) {
        self.busy = busy
        self.idle = idle
    }

    /// Busy share (0…1) between `earlier` and `self`, or `nil` if no ticks elapsed / counters reset.
    public func load(since earlier: CPUTicks) -> Double? {
        guard busy >= earlier.busy, idle >= earlier.idle else { return nil }
        let busyDelta = Double(busy - earlier.busy)
        let total = busyDelta + Double(idle - earlier.idle)
        guard total > 0 else { return nil }
        return min(1, max(0, busyDelta / total))
    }
}

/// Reads raw device values. Abstracted so `SystemMonitorService` can be tested without hardware.
public protocol SystemReading: Sendable {
    /// T-03. Public Mach API; foreground use only.
    func cpuTicks() -> CPUTicks?
    /// T-03. Active + wired + compressed pages. Public Mach API; foreground use only.
    func memoryUsedBytes() -> Int64?
    func memoryTotalBytes() -> Int64
    /// T-02. Whole-volume totals only.
    func storage() -> StorageStatus?
    func thermal() -> ThermalLevel
}

/// Production reader: Mach `host_processor_info` / `host_statistics64`, `URLResourceValues`,
/// `ProcessInfo.thermalState`. No private API.
public struct DeviceSystemReader: SystemReading {
    public init() {}

    public func cpuTicks() -> CPUTicks? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var busy: UInt64 = 0
        var idle: UInt64 = 0
        let stride = Int(CPU_STATE_MAX)
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * stride
            // Tick counters are unsigned 32-bit values stored in integer_t slots.
            func ticks(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
            busy += ticks(CPU_STATE_USER) + ticks(CPU_STATE_SYSTEM) + ticks(CPU_STATE_NICE)
            idle += ticks(CPU_STATE_IDLE)
        }
        return CPUTicks(busy: busy, idle: idle)
    }

    public func memoryUsedBytes() -> Int64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return Int64(pages * UInt64(pageSize))
    }

    public func memoryTotalBytes() -> Int64 { Int64(ProcessInfo.processInfo.physicalMemory) }

    /// Required-reason API (DiskSpace, 85F4.1: shown to the user), declared in the app's manifest.
    public func storage() -> StorageStatus? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                             .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return StorageStatus(totalBytes: Int64(total), freeBytes: free)
    }

    public func thermal() -> ThermalLevel { ThermalLevel(ProcessInfo.processInfo.thermalState) }
}
