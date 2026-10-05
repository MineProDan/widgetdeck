import CoreKit
import Foundation
import WidgetKit

// Timelines are built only from app-written snapshots and pre-downsampled App Group images.
// Rotation is precomputed as timeline entries at each day/hour boundary (widgets are not real-time).

/// Palette widget entry. `palette == nil` → "Pick a wallpaper" state.
public struct PaletteEntry: TimelineEntry, Sendable {
    public let date: Date
    public let palette: PaletteSnapshot?

    public init(date: Date, palette: PaletteSnapshot?) {
        self.date = date
        self.palette = palette
    }
}

/// Photo widget entry. `photo == nil` → "Add photos" state; `isSample` → gallery preview art.
public struct PhotoEntry: TimelineEntry, Sendable {
    public let date: Date
    public let photo: PhotoItem?
    /// 1-based position and count, for VoiceOver.
    public let position: Int
    public let count: Int
    public let isSample: Bool

    public init(date: Date, photo: PhotoItem?, position: Int, count: Int, isSample: Bool = false) {
        self.date = date
        self.photo = photo
        self.position = position
        self.count = count
        self.isSample = isSample
    }

    /// Gallery preview: drawn sample art, independent of the current time.
    public static func sample(at date: Date) -> PhotoEntry {
        PhotoEntry(date: date, photo: nil, position: 1, count: 1, isSample: true)
    }
}

/// Pure timeline math (unit-tested).
public enum PhotoTimelineBuilder {
    /// Entries precomputed per timeline: a week of days, or a day of hours.
    public static func entryCount(for rotation: PhotoRotation) -> Int {
        switch rotation {
        case .daily: 7
        case .hourly: 24
        }
    }

    /// A fixed local-calendar origin, so the photo for a given day/hour is the same in every
    /// timeline (and in the app's "showing now" preview).
    static func origin(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    /// Start of the rotation period containing `date` (local midnight or the top of the hour).
    public static func periodStart(of date: Date, rotation: PhotoRotation, calendar: Calendar) -> Date {
        switch rotation {
        case .daily:
            return calendar.startOfDay(for: date)
        case .hourly:
            return calendar.dateInterval(of: .hour, for: date)?.start ?? date
        }
    }

    /// Period number since the origin. Counting calendar days (not 86 400 s steps) keeps it DST-safe.
    public static func periodIndex(of date: Date, rotation: PhotoRotation, calendar: Calendar) -> Int {
        let origin = origin(calendar: calendar)
        let days = calendar.dateComponents([.day], from: origin, to: calendar.startOfDay(for: date)).day ?? 0
        switch rotation {
        case .daily:
            return days
        case .hourly:
            return days * 24 + calendar.component(.hour, from: date)
        }
    }

    /// Index into `count` photos for `date`.
    public static func photoIndex(at date: Date, count: Int, rotation: PhotoRotation, calendar: Calendar) -> Int {
        guard count > 0 else { return 0 }
        let index = periodIndex(of: date, rotation: rotation, calendar: calendar) % count
        return index < 0 ? index + count : index
    }

    public static func timeline(snapshot: PhotoSnapshot?, now: Date, calendar: Calendar = .current) -> Timeline<PhotoEntry> {
        guard let snapshot, !snapshot.photos.isEmpty else {
            return Timeline(entries: [PhotoEntry(date: now, photo: nil, position: 0, count: 0)], policy: .never)
        }
        let photos = snapshot.photos
        // One photo never changes: a single entry and no reloads until the app writes a new snapshot.
        guard photos.count > 1 else {
            return Timeline(entries: [PhotoEntry(date: now, photo: photos[0], position: 1, count: 1)], policy: .never)
        }
        var entries: [PhotoEntry] = []
        var boundary = periodStart(of: now, rotation: snapshot.rotation, calendar: calendar)
        let component: Calendar.Component = snapshot.rotation == .daily ? .day : .hour
        for step in 0..<entryCount(for: snapshot.rotation) {
            let date = step == 0 ? now : boundary
            let index = photoIndex(at: boundary, count: photos.count, rotation: snapshot.rotation, calendar: calendar)
            entries.append(PhotoEntry(date: date, photo: photos[index], position: index + 1, count: photos.count))
            guard let next = calendar.date(byAdding: component, value: 1, to: boundary) else { break }
            boundary = next
        }
        // `boundary` is now the start of the first period without an entry.
        return Timeline(entries: entries, policy: .after(boundary))
    }
}

/// Palette widget provider: one entry, reloaded when the app applies a new theme.
public struct PaletteTimelineProvider: TimelineProvider {
    private let read: @Sendable () -> PaletteSnapshot?

    public init(read: @escaping @Sendable () -> PaletteSnapshot? = { SnapshotStore().read(PaletteSnapshot.self) }) {
        self.read = read
    }

    public func placeholder(in context: Context) -> PaletteEntry {
        PaletteEntry(date: .now, palette: .sample)
    }

    public func getSnapshot(in context: Context, completion: @escaping (PaletteEntry) -> Void) {
        let palette = read()
        completion(PaletteEntry(date: .now, palette: palette ?? (context.isPreview ? .sample : nil)))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<PaletteEntry>) -> Void) {
        completion(Timeline(entries: [PaletteEntry(date: .now, palette: read())], policy: .never))
    }
}

/// Photo widget provider: rotation entries from the app's snapshot.
public struct PhotoTimelineProvider: TimelineProvider {
    private let read: @Sendable () -> PhotoSnapshot?

    public init(read: @escaping @Sendable () -> PhotoSnapshot? = { SnapshotStore().read(PhotoSnapshot.self) }) {
        self.read = read
    }

    public func placeholder(in context: Context) -> PhotoEntry {
        .sample(at: .now)
    }

    public func getSnapshot(in context: Context, completion: @escaping (PhotoEntry) -> Void) {
        let snapshot = read()
        if context.isPreview, snapshot?.photos.isEmpty ?? true {
            completion(.sample(at: .now))
        } else {
            completion(PhotoTimelineBuilder.timeline(snapshot: snapshot, now: .now).entries[0])
        }
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoEntry>) -> Void) {
        completion(PhotoTimelineBuilder.timeline(snapshot: read(), now: .now))
    }
}
