import CoreKit
import Foundation

/// Widget-safe entry point for the Student section: snapshot types, timeline logic and widget views
/// live in this module so the widget extension doesn't link EventKit services it never uses.
public enum StudentWidgetModule {
    public static let section: AppSection = .student
}

/// The paint a course is drawn in. Courses rotate through the four day paints in the order the
/// mockup uses (BIO coral, ENG sand, CHEM tide, PSY sage). Plum Dusk is reserved for evening/mood.
public enum CoursePaint: String, Codable, CaseIterable, Sendable {
    case coral, sand, tide, sage

    /// Paint for the `index`-th course (stable rotation).
    public static func rotating(_ index: Int) -> CoursePaint {
        allCases[((index % allCases.count) + allCases.count) % allCases.count]
    }
}

/// One class occurrence as widgets see it. No notes, attendees or calendar names: only what the
/// widget draws, so the snapshot stays small and private.
public struct ClassSlot: Codable, Hashable, Sendable, Identifiable {
    /// Occurrence identifier (event identifier + start time), unique per occurrence.
    public var id: String
    public var courseID: UUID?
    /// Course code ("BIO 201"), or the event title when no code is known.
    public var code: String
    public var location: String?
    public var start: Date
    public var end: Date
    public var paint: CoursePaint
    /// When to leave, from the course's user-set "leave by" (minutes before start). `nil` = not set.
    public var leaveBy: Date?
    /// `leaveBy` is an estimate from travel time (shown as "~… est."), not a fixed user time.
    public var leaveByIsEstimate: Bool?
    /// The course's user-set room, when this occurrence is at the course's usual location.
    public var room: String?

    public init(id: String, courseID: UUID?, code: String, location: String?, start: Date, end: Date, paint: CoursePaint,
                leaveBy: Date? = nil, leaveByIsEstimate: Bool? = nil) {
        self.id = id
        self.courseID = courseID
        self.code = code
        self.location = location
        self.start = start
        self.end = end
        self.paint = paint
        self.leaveBy = leaveBy
        self.leaveByIsEstimate = leaveByIsEstimate
    }

    public func isInProgress(at date: Date) -> Bool { start <= date && date < end }

    /// What to show for the place in tight spaces (widgets, rows): the course's room if set, else
    /// `location` shortened. The full `location` is kept for MapKit.
    public var shortLocation: String? { room?.nilIfEmpty ?? location.flatMap(LocationFormat.short) }
}

/// Shortens calendar locations like "Information & Computer Science, 6210 Donald Bren Hall,
/// Irvine, CA 92697, United States" to the useful part ("6210 Donald Bren Hall").
extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum LocationFormat {
    /// A room-like token in free text ("ICS 192", "SSL 270", "Rm 3B", "Room 101A"), excluding
    /// `courseCode`. Used to suggest a course's room from event notes; the user confirms it.
    public static func roomSuggestion(in notes: String, excluding courseCode: String?) -> String? {
        let normalizedCode = courseCode?.replacingOccurrences(of: " ", with: "").uppercased()
        for match in notes.matches(of: #/\b(?:(?:Rm|Room)\.?\s*[A-Z]?\d{1,4}[A-Z]?|[A-Z]{2,5}\s?\d{2,4}[A-Z]?)\b/#) {
            let token = String(match.output).trimmingCharacters(in: .whitespaces)
            if token.replacingOccurrences(of: " ", with: "").uppercased() == normalizedCode { continue }
            return token
        }
        return nil
    }

    /// Words that mark the part naming a building or room.
    static let placeWords = ["hall", "building", "bldg", "room", "rm", "center", "centre", "ctr", "lab", "library",
                             "auditorium", "theater", "theatre", "pavilion", "annex", "tower", "gym", "studio", "classroom"]
    static let countries: Set<String> = ["united states", "usa", "us", "united states of america", "canada", "united kingdom",
                                         "uk", "australia", "new zealand", "ireland"]

    public static func short(_ location: String) -> String? {
        var parts = location.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return parts.first }
        // Drop the address tail: country, then "CA 92697"-style state + postal code, then the city.
        if let last = parts.last, countries.contains(last.lowercased()) { parts.removeLast() }
        var droppedRegion = false
        if let last = parts.last, last.contains(where: \.isNumber), last.count <= 12, parts.count > 1 {
            parts.removeLast()
            droppedRegion = true
        }
        if droppedRegion, parts.count > 1 { parts.removeLast() }
        // Prefer the part that names a building or room; otherwise the first part.
        let place = parts.first { part in
            part.lowercased().split(whereSeparator: { !$0.isLetter }).contains { placeWords.contains(String($0)) }
        }
        return place ?? parts.first
    }
}

/// Shared payload of both Student snapshots: upcoming class occurrences, sorted by start.
public protocol ClassScheduleSnapshot: WidgetSnapshot {
    var classes: [ClassSlot] { get }
    init(classes: [ClassSlot], generatedAt: Date)
}

extension ClassScheduleSnapshot {
    /// Most classes a snapshot carries. ~40 slots ≈ 8 KB, well under `SnapshotStore.maxSize`.
    public static var maxClasses: Int { 40 }
}

/// Feeds the Next Class widget (small, medium, accessoryRectangular).
public struct NextClassSnapshot: ClassScheduleSnapshot {
    public static var kind: WidgetKind { .nextClass }
    public var classes: [ClassSlot]
    public var generatedAt: Date

    public init(classes: [ClassSlot], generatedAt: Date) {
        self.classes = Array(classes.sorted { $0.start < $1.start }.prefix(Self.maxClasses))
        self.generatedAt = generatedAt
    }
}

/// Feeds the Today's Schedule widget (medium, large). Carries more than today so the widget can
/// roll over at midnight without the app running.
public struct TodayScheduleSnapshot: ClassScheduleSnapshot {
    public static var kind: WidgetKind { .todaySchedule }
    public var classes: [ClassSlot]
    public var generatedAt: Date

    public init(classes: [ClassSlot], generatedAt: Date) {
        self.classes = Array(classes.sorted { $0.start < $1.start }.prefix(Self.maxClasses))
        self.generatedAt = generatedAt
    }
}

/// Deep links into the Student section. `AppSection(deepLink:)` selects the tab from the path;
/// the `course` query item identifies the course to open.
public enum StudentDeepLink {
    public static func url(course courseID: UUID?) -> URL {
        var components = URLComponents(url: AppSection.student.deepLink, resolvingAgainstBaseURL: false)
        if let courseID {
            components?.queryItems = [URLQueryItem(name: "course", value: courseID.uuidString)]
        }
        return components?.url ?? AppSection.student.deepLink
    }

    /// The course a Student deep link points at, if any.
    public static func courseID(from url: URL) -> UUID? {
        guard AppSection(deepLink: url) == .student,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "course" })?.value else { return nil }
        return UUID(uuidString: value)
    }
}
