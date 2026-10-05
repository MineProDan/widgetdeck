import Foundation
import UIKit

/// Battery wording shared by the Tech screen and widgets. Every time-to-full is labelled "est.",
/// because it's our own projection from the observed charge rate, not an iOS value.
public enum BatteryCopy {
    /// Trend line on the Tech screen card: "Charging · est. 1h 10m".
    public static func cardTrend(_ status: BatteryStatus, now: Date = .now) -> String {
        switch status.state {
        case .charging:
            if let fullAt = status.estimatedFullAt, fullAt > now {
                return "Charging · est. \(TechFormat.duration(fullAt.timeIntervalSince(now)))"
            }
            return "Charging · estimating"
        case .full: return "Full · plugged in"
        case .unplugged: return "On battery"
        case .unknown: return "Not reported"
        }
    }

    /// Widget caption: "Battery · charging".
    public static func widgetCaption(_ status: BatteryStatus) -> String {
        switch status.state {
        case .charging: "Battery · charging"
        case .full: "Battery · full"
        default: "Battery"
        }
    }

    /// Widget trend line: "Est. 1h 10m to full", or the "as of" time when the level may be stale.
    public static func widgetTrend(_ status: BatteryStatus, isLive: Bool, generatedAt: Date, now: Date) -> String {
        if status.state == .charging, let fullAt = status.estimatedFullAt, fullAt > now {
            return "Est. \(TechFormat.duration(fullAt.timeIntervalSince(now))) to full"
        }
        if status.state == .full { return "Plugged in" }
        if status.level == nil { return "Open Widgetdeck to update" }
        return isLive ? "On battery" : TechFormat.asOf(generatedAt)
    }
}

/// Reads the battery directly with `UIDevice` (T-01 spike). Works in the app; inside the widget
/// extension it's attempted first and the app-written snapshot is the fallback (see README).
public enum LiveBatteryReader {
    /// Returns `nil` when iOS reports no level (`-1`: Simulator, or not permitted in this process).
    @MainActor
    public static func read() -> BatteryStatus? {
        let device = UIDevice.current
        let wasEnabled = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { if !wasEnabled { device.isBatteryMonitoringEnabled = false } }
        let level = device.batteryLevel
        guard level >= 0 else { return nil }
        return BatteryStatus(level: Double(level), state: BatteryChargeState(device.batteryState))
    }
}

extension BatteryChargeState {
    public init(_ state: UIDevice.BatteryState) {
        switch state {
        case .unplugged: self = .unplugged
        case .charging: self = .charging
        case .full: self = .full
        case .unknown: self = .unknown
        @unknown default: self = .unknown
        }
    }
}
