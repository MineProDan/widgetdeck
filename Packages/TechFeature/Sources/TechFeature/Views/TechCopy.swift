import DesignSystem
import SwiftUI
import TechFeatureWidgetKit

/// Card trend lines for the Tech screen (the caps line under each value).
public enum TechCopy {
    public enum Tone: Sendable, Equatable {
        case positive, urgent, neutral

        var color: Color {
            switch self {
            case .positive: WXColor.mossPositive
            case .urgent: WXColor.clayLink
            case .neutral: WXColor.inkSecondary
            }
        }
    }

    public static func battery(_ status: BatteryStatus, now: Date) -> (String, Tone) {
        (BatteryCopy.cardTrend(status, now: now), status.state.isPluggedIn ? .positive : .neutral)
    }

    /// "Of 256 · −2.1 GB wk" (urgent when more than 1 GB went in a week) or "Of 256 GB".
    public static func storage(_ storage: StorageStatus?) -> (String, Tone) {
        guard let storage, storage.totalBytes > 0 else { return ("Not reported", .neutral) }
        let total = TechFormat.storageTotalNumber(storage.totalBytes)
        guard let change = storage.weeklyFreeChangeBytes else { return ("Of \(total) GB", .neutral) }
        let tone: Tone = change <= -1_000_000_000 ? .urgent : (change >= 1_000_000_000 ? .positive : .neutral)
        return ("Of \(total) · \(TechFormat.storageWeeklyChange(change))", tone)
    }

    /// "Down from 31% · 1 min". Changes under 3 points read as "steady".
    public static func cpu(current: Double?, minuteAgo: Double?) -> (String, Tone) {
        guard let current else { return ("Measuring…", .neutral) }
        guard let minuteAgo else { return ("Every 5 s while open", .neutral) }
        let delta = current - minuteAgo
        if delta <= -0.03 { return ("Down from \(TechFormat.percent(minuteAgo)) · 1 min", .positive) }
        if delta >= 0.03 { return ("Up from \(TechFormat.percent(minuteAgo)) · 1 min", .neutral) }
        return ("Steady · 1 min", .neutral)
    }

    /// "Of 6 GB · steady". Changes under 5 % of installed RAM read as "steady".
    public static func memory(used: Int64?, minuteAgo: Int64?, total: Int64) -> (String, Tone) {
        let totalText = "Of \(TechFormat.memoryTotal(total))"
        guard let used, let minuteAgo, total > 0 else { return (totalText, .neutral) }
        let change = Double(used - minuteAgo) / Double(total)
        if change >= 0.05 { return ("\(totalText) · rising", .neutral) }
        if change <= -0.05 { return ("\(totalText) · falling", .positive) }
        return ("\(totalText) · steady", .neutral)
    }
}
