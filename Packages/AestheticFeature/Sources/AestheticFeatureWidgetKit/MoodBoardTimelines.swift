import CoreKit
import Foundation
import WidgetKit

/// Mood board widget entry. Empty `photos` → "Add photos" state; `isSample` → gallery preview art.
public struct MoodBoardEntry: TimelineEntry, Sendable {
    public let date: Date
    /// Photos in display order (the widget shows as many as its layout has tiles).
    public let photos: [MoodBoardItem]
    public let style: WidgetStyle
    public let isSample: Bool

    public init(date: Date, photos: [MoodBoardItem], style: WidgetStyle = .default, isSample: Bool = false) {
        self.date = date
        self.photos = photos
        self.style = style
        self.isSample = isSample
    }

    public static func sample(at date: Date) -> MoodBoardEntry {
        MoodBoardEntry(date: date, photos: [], isSample: true)
    }
}

/// Pure timeline math (unit-tested).
public enum MoodBoardTimelineBuilder {
    /// Days precomputed when daily shuffle is on.
    public static let shuffleDays = 7

    /// The board's order for `date`: the user's order, or a deterministic per-day shuffle (the same
    /// day always gives the same arrangement, in every timeline and in the app's preview).
    public static func order(of photos: [MoodBoardItem], shuffleDaily: Bool, at date: Date, calendar: Calendar) -> [MoodBoardItem] {
        guard shuffleDaily, photos.count > 1 else { return photos }
        let day = PhotoTimelineBuilder.periodIndex(of: date, rotation: .daily, calendar: calendar)
        var generator = SplitMix64(seed: UInt64(bitPattern: Int64(day)) &+ 0x5EED)
        return photos.shuffled(using: &generator)
    }

    public static func timeline(snapshot: MoodBoardSnapshot?, style: WidgetStyle, now: Date,
                                calendar: Calendar = .current) -> Timeline<MoodBoardEntry> {
        guard let snapshot, !snapshot.photos.isEmpty else {
            return Timeline(entries: [MoodBoardEntry(date: now, photos: [], style: style)], policy: .never)
        }
        guard snapshot.shuffleDaily, snapshot.photos.count > 1 else {
            return Timeline(entries: [MoodBoardEntry(date: now, photos: snapshot.photos, style: style)], policy: .never)
        }
        var entries: [MoodBoardEntry] = []
        var boundary = calendar.startOfDay(for: now)
        for step in 0..<shuffleDays {
            let photos = order(of: snapshot.photos, shuffleDaily: true, at: boundary, calendar: calendar)
            entries.append(MoodBoardEntry(date: step == 0 ? now : boundary, photos: photos, style: style))
            guard let next = calendar.date(byAdding: .day, value: 1, to: boundary) else { break }
            boundary = next
        }
        return Timeline(entries: entries, policy: .after(boundary))
    }
}

/// Small deterministic generator (the system generator can't be seeded).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Mood board provider: entries from the app's snapshot, styled from `aesthetic-styles.json`.
public struct MoodBoardTimelineProvider: TimelineProvider {
    private let read: @Sendable () -> MoodBoardSnapshot?
    private let readStyle: @Sendable () -> WidgetStyle

    public init(read: @escaping @Sendable () -> MoodBoardSnapshot? = { SnapshotStore().read(MoodBoardSnapshot.self) },
                readStyle: @escaping @Sendable () -> WidgetStyle = { AestheticStyleSnapshot.load().moodBoard }) {
        self.read = read
        self.readStyle = readStyle
    }

    public func placeholder(in context: Context) -> MoodBoardEntry {
        .sample(at: .now)
    }

    public func getSnapshot(in context: Context, completion: @escaping (MoodBoardEntry) -> Void) {
        let snapshot = read()
        if context.isPreview, snapshot?.photos.isEmpty ?? true {
            completion(.sample(at: .now))
        } else {
            completion(MoodBoardTimelineBuilder.timeline(snapshot: snapshot, style: readStyle(), now: .now).entries[0])
        }
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<MoodBoardEntry>) -> Void) {
        completion(MoodBoardTimelineBuilder.timeline(snapshot: read(), style: readStyle(), now: .now))
    }
}
