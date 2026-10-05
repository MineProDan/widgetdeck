import Foundation
import MetricKit
import os

/// Receives MetricKit daily metric and diagnostic payloads (energy, memory, hangs, crashes).
///
/// Payloads are logged locally and summarized into a tiny, anonymous analytics event. Raw payloads
/// never leave the device. **Main app only.**
public final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber, Sendable {
    public static let shared = MetricKitSubscriber()

    private let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "MetricKit")

    /// Begins receiving payloads. Safe to call more than once.
    public func start() {
        MXMetricManager.shared.add(self)
    }

    public func stop() {
        MXMetricManager.shared.remove(self)
    }

    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            var parameters: [String: String] = [:]
            if let memory = payload.memoryMetrics {
                let megabytes = memory.peakMemoryUsage.converted(to: .megabytes).value
                parameters["peak_memory_mb"] = String(Int(megabytes.rounded()))
            }
            if let cpu = payload.cpuMetrics {
                parameters["cpu_time_s"] = String(Int(cpu.cumulativeCPUTime.converted(to: .seconds).value.rounded()))
            }
            logger.info("Metric payload: \(parameters.description, privacy: .public)")
            Analytics.shared.track(AnalyticsEvent("metrics_daily", parameters: parameters))
        }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            logger.info("Diagnostic payload: \(crashes) crashes, \(hangs) hangs")
            Analytics.shared.track(AnalyticsEvent("diagnostics", parameters: ["crashes": String(crashes), "hangs": String(hangs)]))
        }
    }
}
