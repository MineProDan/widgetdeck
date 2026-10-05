import CryptoKit
import Foundation

/// A calendar day, independent of time zone and DST ("2026-09-29").
///
/// Habit completions and mood entries are stored per `DayKey` (plus the time zone they were logged
/// in), never as instants. Day arithmetic runs on a fixed GMT Gregorian calendar, so a 23- or
/// 25-hour DST day is still exactly one day, and flying across time zones never splits or merges days.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "yyyy-MM-dd".
    public init?(_ string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Days since 1970-01-01 (monotonic, used for arithmetic and deterministic picks).
    public var ordinal: Int {
        let date = Self.gmt.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
        return Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    public init(ordinal: Int) {
        let date = Date(timeIntervalSince1970: Double(ordinal) * 86_400 + 12 * 3600)
        let c = Self.gmt.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public func adding(days: Int) -> DayKey { DayKey(ordinal: ordinal + days) }

    /// 1 = Sunday … 7 = Saturday (Gregorian), matching `Calendar.component(.weekday)`.
    public var weekday: Int {
        Self.gmt.component(.weekday, from: Date(timeIntervalSince1970: Double(ordinal) * 86_400 + 12 * 3600))
    }

    /// Start of the week containing this day (`firstWeekday`: 1 = Sunday, 2 = Monday).
    public func startOfWeek(firstWeekday: Int) -> DayKey {
        adding(days: -((weekday - firstWeekday + 7) % 7))
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.ordinal < rhs.ordinal }

    // Encoded as the "yyyy-MM-dd" string so snapshots and payloads stay readable.
    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let key = DayKey(string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad day \(string)"))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private static let gmt: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT") ?? .gmt
        return calendar
    }()
}

/// Maps instants to wellness days for the user's time zone and "day starts at" hour.
///
/// With `dayStartHour = 4`, 2:30 AM on Tuesday still belongs to Monday (shift workers, night owls).
public struct WellnessDayClock: Sendable, Equatable {
    public var dayStartHour: Int
    public var timeZone: TimeZone

    public init(dayStartHour: Int = 0, timeZone: TimeZone = .current) {
        self.dayStartHour = min(max(dayStartHour, 0), 12)
        self.timeZone = timeZone
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The wellness day that `date` belongs to: its local calendar date, or the day before when the
    /// local wall-clock time is earlier than the day-start hour. Wall-clock based, so DST can't shift it.
    public func day(for date: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let key = DayKey(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
        return (c.hour ?? 0) < dayStartHour ? key.adding(days: -1) : key
    }

    /// The instant a wellness day begins (its "day starts at" hour, local wall clock). If that hour
    /// doesn't exist (spring-forward gap), the calendar moves it to the next valid time.
    public func start(of day: DayKey) -> Date {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: dayStartHour)) ?? .now
    }

    /// The next day boundary after `date` (when widgets roll over).
    public func nextBoundary(after date: Date) -> Date {
        start(of: day(for: date).adding(days: 1))
    }
}

/// Stable UUIDs derived from a name (SHA-256, RFC 4122 variant bits).
///
/// Used for records that must be idempotent across devices: "habit X on day D" gets the same id
/// everywhere, so a CloudKit merge produces duplicate rows with one id, which dedupe collapses.
public enum StableID {
    public static func uuid(_ name: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 style (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    public static func completion(habit: UUID, day: DayKey) -> UUID { uuid("habit-completion/\(habit.uuidString)/\(day)") }
    public static func mood(day: DayKey) -> UUID { uuid("mood/\(day)") }
}
