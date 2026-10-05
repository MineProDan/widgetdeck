import CoreKit
import DesignSystem
import Foundation
import os

// MARK: - Mood

/// The five-step mood scale (W-03). Raw values 0…4 index `MoodScale.words` / `WXColor.moodTints`.
/// Shown as Rough · Low · Okay · Good · Great, the mockup's words for awful … great.
public enum Mood: Int, Codable, CaseIterable, Sendable, Identifiable {
    case awful = 0, bad, okay, good, great

    public var id: Int { rawValue }

    /// The word shown in the UI ("Good").
    public var word: String { MoodScale.words[rawValue] }
}

// MARK: - Quotes and affirmations (W-01)

/// Content categories shared by quotes and affirmations.
public enum ContentCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case calm, focus, courage, growth, kindness, nature

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .calm: String(localized: "Calm")
        case .focus: String(localized: "Focus")
        case .courage: String(localized: "Courage")
        case .growth: String(localized: "Growth")
        case .kindness: String(localized: "Kindness")
        case .nature: String(localized: "Nature")
        }
    }
}

/// A public-domain quote with its author and source (bundled `quotes.json`).
public struct Quote: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let author: String
    public let source: String
    public let category: ContentCategory

    public init(id: String, text: String, author: String, source: String, category: ContentCategory) {
        self.id = id
        self.text = text
        self.author = author
        self.source = source
        self.category = category
    }
}

/// An affirmation written in-house (bundled `affirmations.json`).
public struct Affirmation: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let category: ContentCategory

    public init(id: String, text: String, category: ContentCategory) {
        self.id = id
        self.text = text
        self.category = category
    }
}

/// Loads the bundled content. Safe in the widget extension: local files only, no network.
public enum WellnessContentLibrary {
    private static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Wellness")

    public static let quotes: [Quote] = load("quotes")
    public static let affirmations: [Affirmation] = load("affirmations")

    private static func load<T: Decodable>(_ name: String) -> [T] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            logger.error("Missing bundled \(name, privacy: .public).json")
            return []
        }
        do {
            return try JSONDecoder().decode([T].self, from: Data(contentsOf: url))
        } catch {
            logger.error("Bad bundled \(name, privacy: .public).json: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Shown when the bundle can't be read (never blank).
    public static let fallbackQuote = Quote(id: "fallback", text: "Well done is better than well said.",
                                            author: "Benjamin Franklin", source: "Poor Richard's Almanack (1737)", category: .focus)
    public static let fallbackAffirmation = Affirmation(id: "fallback", text: "I can take one slow breath before I decide.", category: .calm)
}

/// Deterministic daily pick: the same day and category always give the same item, on every device
/// and in the widget and app alike, without storing anything.
///
/// Items are walked in a shuffled order that is reshuffled every cycle, so nothing repeats until the
/// whole (filtered) list has been shown, and consecutive cycles don't restart in the same order.
public enum DailyPicker {
    public static func pick<T: Identifiable>(from items: [T], day: DayKey, salt: String = "") -> T? where T.ID == String {
        guard !items.isEmpty else { return nil }
        let sorted = items.sorted { $0.id < $1.id }
        let n = sorted.count
        let dayIndex = day.ordinal
        let cycle = Int(floor(Double(dayIndex) / Double(n)))
        let position = ((dayIndex % n) + n) % n
        let order = permutation(count: n, seed: seed("\(salt)#\(cycle)"))
        return sorted[order[position]]
    }

    public static func quote(for day: DayKey, category: ContentCategory? = nil,
                             from quotes: [Quote] = WellnessContentLibrary.quotes) -> Quote {
        let pool = category.map { c in quotes.filter { $0.category == c } } ?? quotes
        return pick(from: pool.isEmpty ? quotes : pool, day: day, salt: "quote-\(category?.rawValue ?? "all")")
            ?? WellnessContentLibrary.fallbackQuote
    }

    public static func affirmation(for day: DayKey, category: ContentCategory? = nil,
                                   from affirmations: [Affirmation] = WellnessContentLibrary.affirmations) -> Affirmation {
        let pool = category.map { c in affirmations.filter { $0.category == c } } ?? affirmations
        return pick(from: pool.isEmpty ? affirmations : pool, day: day, salt: "affirmation-\(category?.rawValue ?? "all")")
            ?? WellnessContentLibrary.fallbackAffirmation
    }

    /// Fisher–Yates with SplitMix64, so the order is identical on every platform and run
    /// (Swift's `Hasher` is randomly seeded per process and must not be used here).
    static func permutation(count: Int, seed: UInt64) -> [Int] {
        var state = seed
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        var order = Array(0..<count)
        guard count > 1 else { return order }
        for i in stride(from: count - 1, to: 0, by: -1) {
            order.swapAt(i, Int(next() % UInt64(i + 1)))
        }
        return order
    }

    static func seed(_ string: String) -> UInt64 {
        // FNV-1a: stable across launches.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
