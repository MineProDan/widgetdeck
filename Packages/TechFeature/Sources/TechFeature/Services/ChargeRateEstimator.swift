import Foundation

/// Estimates time-to-full from the charge rate we observe (T-01). iOS doesn't report one, so this
/// is always shown as "est.".
///
/// Method: least-squares slope of (time, level) over the current charging session's last 30
/// minutes. We need at least two readings, 3 minutes apart, and a rise of at least 1 %, because
/// iOS reports the level in 1 % steps and a shorter window is mostly noise. Above 80 % iPhones
/// slow charging (and Optimized Charging may pause at 80 %), so the remainder above 80 % is
/// projected at half the observed rate.
public struct ChargeRateEstimator: Sendable {
    public struct Reading: Sendable, Equatable {
        public var date: Date
        public var level: Double
        public init(date: Date, level: Double) {
            self.date = date
            self.level = level
        }
    }

    public static let window: TimeInterval = 30 * 60
    public static let minimumSpan: TimeInterval = 3 * 60
    public static let minimumRise = 0.01
    public static let taperThreshold = 0.8

    public private(set) var readings: [Reading] = []

    public init() {}

    /// Records a level reported while charging.
    public mutating func record(level: Double, at date: Date) {
        guard level.isFinite, (0...1).contains(level) else { return }
        // A drop while "charging" means the session restarted (heavy use, cable wiggle).
        if let last = readings.last, level < last.level - 0.005 { readings.removeAll() }
        readings.append(Reading(date: date, level: level))
        readings.removeAll { date.timeIntervalSince($0.date) > Self.window }
    }

    /// Call when charging stops, so the next session starts fresh.
    public mutating func reset() { readings.removeAll() }

    /// Observed rate in fraction per hour, or `nil` when there isn't enough evidence yet.
    public var ratePerHour: Double? {
        guard readings.count >= 2, let first = readings.first, let last = readings.last,
              last.date.timeIntervalSince(first.date) >= Self.minimumSpan,
              last.level - first.level >= Self.minimumRise else { return nil }
        let t0 = first.date
        let xs = readings.map { $0.date.timeIntervalSince(t0) / 3600 }
        let ys = readings.map(\.level)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0
        var denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator > 0 else { return nil }
        let slope = numerator / denominator
        return slope > 0 ? slope : nil
    }

    /// Seconds until 100 % from `level`, or `nil` when unknown.
    public func timeToFull(from level: Double) -> TimeInterval? {
        guard let rate = ratePerHour else { return nil }
        return Self.timeToFull(from: level, ratePerHour: rate)
    }

    /// Seconds to 100 % at `ratePerHour`, with the above-80 % taper.
    public static func timeToFull(from level: Double, ratePerHour rate: Double) -> TimeInterval? {
        guard rate > 0, level.isFinite else { return nil }
        let level = min(1, max(0, level))
        let fast = max(0, taperThreshold - level)
        let slow = 1 - max(level, taperThreshold)
        let hours = fast / rate + slow / (rate / 2)
        return hours * 3600
    }
}
