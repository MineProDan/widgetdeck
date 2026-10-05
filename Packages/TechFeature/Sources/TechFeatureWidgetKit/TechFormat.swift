import Foundation

/// Text formatting shared by the Tech screen and widgets. "—" means "not available".
///
/// Storage uses decimal GB (1 GB = 10⁹ bytes), matching iOS Settings. Memory uses binary GB
/// (2³⁰), because RAM is sold in binary sizes (a "6 GB" iPhone reports about 5.6 × 10⁹ bytes).
public enum TechFormat {
    public static let unavailable = "—"

    static let decimalGB = 1_000_000_000.0
    static let binaryGB = 1_073_741_824.0

    /// `0.823` → `"82%"`. Clamped to 0…100.
    public static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return unavailable }
        return "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// Whole percent number without the sign, for tight accessory widgets.
    public static func percentNumber(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return unavailable }
        return "\(Int((min(1, max(0, fraction)) * 100).rounded()))"
    }

    /// Storage bytes: `118_400_000_000` → `"118 GB"`; below 10 GB one decimal (`"9.4 GB"`);
    /// below 1 GB in MB.
    public static func storage(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return unavailable }
        let gb = Double(bytes) / decimalGB
        if gb >= 10 { return "\(Int(gb.rounded())) GB" }
        if gb >= 1 { return "\(oneDecimal(gb)) GB" }
        return "\(Int((Double(bytes) / 1_000_000).rounded())) MB"
    }

    /// Volume size as a round number of GB: `255_900_000_000` → `"256"`.
    public static func storageTotalNumber(_ bytes: Int64) -> String {
        "\(Int((Double(bytes) / decimalGB).rounded()))"
    }

    /// Signed weekly change: `-2_100_000_000` → `"−2.1 GB wk"` (true minus sign).
    public static func storageWeeklyChange(_ bytes: Int64) -> String {
        let gb = Double(bytes) / decimalGB
        let sign = gb < 0 ? "−" : "+"
        return "\(sign)\(oneDecimal(abs(gb))) GB wk"
    }

    /// Memory in use: `3_328_599_654` → `"3.1 GB"`.
    public static func memory(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return unavailable }
        return "\(oneDecimal(Double(bytes) / binaryGB)) GB"
    }

    /// Installed RAM as whole GB: `5_999_999_000` → `"6 GB"`.
    public static func memoryTotal(_ bytes: Int64) -> String {
        "\(Int((Double(bytes) / binaryGB).rounded())) GB"
    }

    /// Duration: 4200 s → `"1h 10m"`, 900 s → `"15m"`, under a minute → `"<1m"`.
    public static func duration(_ interval: TimeInterval?) -> String {
        guard let interval, interval.isFinite, interval >= 0 else { return unavailable }
        let minutes = Int((interval / 60).rounded())
        if minutes < 1 { return "<1m" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// "As of" clock time for values the widget can't refresh itself.
    public static func asOf(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.timeZone = timeZone
        return "As of \(date.formatted(style))"
    }

    private static func oneDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }
}
