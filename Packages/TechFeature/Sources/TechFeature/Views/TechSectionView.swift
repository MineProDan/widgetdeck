import CoreKit
import DesignSystem
import SwiftUI
import TechFeatureWidgetKit

/// Root view of the Tech section (T-05). The app shell draws the page header ("Tech" / "Live while
/// the app is open, every 5 seconds") above it.
///
/// Sampling runs only while this view is on screen **and** the scene is active.
public struct TechSectionView: View {
    @State private var monitor: SystemMonitorService
    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameter stack: the app's Core Data stack loaded with `TechPersistenceModel`. Without it,
    ///   samples are kept in memory for this session only (no weekly storage trend).
    public init(stack: CoreDataStack? = nil) {
        let store: any MetricSampleStore = stack.map { CoreDataMetricSampleStore(stack: $0) } ?? InMemoryMetricSampleStore()
        _monitor = State(initialValue: SystemMonitorService(store: store))
    }

    /// Previews and tests: inject a configured service.
    public init(monitor: SystemMonitorService) {
        _monitor = State(initialValue: monitor)
    }

    public var body: some View {
        TechDashboard(monitor: monitor)
            .onAppear {
                isVisible = true
                monitor.setActive(scenePhase == .active)
            }
            .onDisappear {
                isVisible = false
                monitor.setActive(false)
            }
            .onChange(of: scenePhase) { _, phase in
                monitor.setActive(isVisible && phase == .active)
            }
    }
}

/// The static layout, driven by the monitor's current values.
struct TechDashboard: View {
    let monitor: SystemMonitorService

    var body: some View {
        let metrics = monitor.metrics
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                let (batteryTrend, batteryTone) = TechCopy.battery(metrics.battery, now: metrics.sampledAt)
                MetricCard(caption: "Battery", value: TechFormat.percent(metrics.battery.level), fill: metrics.battery.level,
                           fillColor: WXColor.beachSand, trend: batteryTrend, tone: batteryTone)
                StorageView(storage: metrics.storage)
                if monitor.cpuMemoryEnabled {
                    CPUGaugeView(load: metrics.cpuLoad, minuteAgo: monitor.cpuMinuteAgo)
                    let (memoryTrend, memoryTone) = TechCopy.memory(used: metrics.memoryUsedBytes, minuteAgo: monitor.memoryMinuteAgo,
                                                                    total: metrics.memoryTotalBytes)
                    MetricCard(caption: "Memory", value: TechFormat.memory(metrics.memoryUsedBytes),
                               fill: memoryFraction(metrics), fillColor: WXColor.shell, trend: memoryTrend, tone: memoryTone)
                }
            }

            ThermalIndicator(level: metrics.thermal)
                .padding(.top, 24)

            DeviceChipView(device: monitor.device)
                .padding(.top, 24)

            Text("Estimates are labelled. CPU and memory are measured only while this screen is open.")
                .wxBody(13, lineHeight: 1.45)
                .padding(.top, 16)
        }
    }

    private func memoryFraction(_ metrics: SystemMetrics) -> Double? {
        guard let used = metrics.memoryUsedBytes, metrics.memoryTotalBytes > 0 else { return nil }
        return min(1, Double(used) / Double(metrics.memoryTotalBytes))
    }
}

#if DEBUG
/// Static sample data only (previews are slow on the Intel dev Mac).
private struct PreviewReader: SystemReading {
    func cpuTicks() -> CPUTicks? { nil }
    func memoryUsedBytes() -> Int64? { 3_328_599_654 }
    func memoryTotalBytes() -> Int64 { 6 * 1_073_741_824 }
    func storage() -> StorageStatus? { StorageStatus(totalBytes: 256_000_000_000, freeBytes: 118_000_000_000) }
    func thermal() -> ThermalLevel { .nominal }
}

#Preview {
    let monitor = SystemMonitorService(reader: PreviewReader(), publisher: nil, observesBattery: false)
    ScrollView {
        TechSectionView(monitor: monitor).padding(24)
    }
    .background(WXColor.paperIvory)
}
#endif
