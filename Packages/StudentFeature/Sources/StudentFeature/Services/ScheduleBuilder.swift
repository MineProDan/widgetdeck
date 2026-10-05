import CryptoKit
import CoreKit
import Foundation
import StudentFeatureWidgetKit

/// A deadline occurrence for "Due soon".
public struct DeadlineItem: Hashable, Sendable, Identifiable {
    public var id: String
    public var seriesKey: String
    public var title: String
    public var courseID: UUID?
    public var code: String?
    public var due: Date
    public var paint: CoursePaint
    public var isDone: Bool
    /// Set for manual or imported assignments (S-05); `nil` for calendar deadlines.
    public var assignmentID: UUID? = nil
}

/// The classified schedule for the rolling window.
public struct StudentSchedule: Sendable, Equatable {
    public var classes: [ClassSlot]
    public var deadlines: [DeadlineItem]
    /// Courses after the build, including any auto-created from new course codes.
    public var courses: [Course]
    /// Courses that didn't exist before this build (persist these).
    public var newCourses: [Course]
    /// Series key per class occurrence id (to open the correction sheet).
    public var seriesByOccurrence: [String: String]
    /// `ScheduleBuilder.titleKey` per series key (saved with a correction).
    public var titleKeyBySeries: [String: String] = [:]
    /// Room-like text found in a course's event notes ("ICS 192"), offered in the course sheet.
    public var roomSuggestions: [UUID: String] = [:]

    public static let empty = StudentSchedule(classes: [], deadlines: [], courses: [], newCourses: [], seriesByOccurrence: [:])
}

/// Turns raw events + our annotations into classes and deadlines. Pure: no EventKit, no I/O.
public enum ScheduleBuilder {
    public static func build(events: [CalendarEvent], links: [CourseEventLink], courses: [Course], now: Date = .now) -> StudentSchedule {
        let linkBySeries = Dictionary(links.map { ($0.seriesKey, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        // Fallback when the series identifier changed: the newest correction for the same calendar + title.
        let linkByTitle = Dictionary(links.compactMap { link in link.titleKey.map { ($0, link) } },
                                     uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        var titleKeyBySeries: [String: String] = [:]
        var allCourses = courses
        var newCourses: [Course] = []
        var classes: [ClassSlot] = []
        var deadlines: [DeadlineItem] = []
        var seriesByOccurrence: [String: String] = [:]

        func course(forCode code: String) -> Course {
            if let existing = allCourses.first(where: { $0.code == code }) { return existing }
            let created = Course(code: code, paint: .rotating(allCourses.count), updatedAt: now)
            allCourses.append(created)
            newCourses.append(created)
            return created
        }

        var roomSuggestions: [UUID: String] = [:]
        var locationsByCourse: [UUID: [String: Int]] = [:]

        for event in events.sorted(by: { $0.start < $1.start }) {
            let key = titleKey(for: event)
            titleKeyBySeries[event.seriesKey] = key
            let link = linkBySeries[event.seriesKey] ?? linkByTitle[key]
            let result = EventClassifier.classify(event, userTag: link?.userCategory)
            // A user-assigned course wins over the code found in the title.
            let linked = link?.courseID.flatMap { id in allCourses.first { $0.id == id } }
            var matched = linked ?? result.courseCode.map(course(forCode:))
            // A class with no course code (e.g. one the user tagged as a class, or a weekly
            // "Lecture") still gets a course, named after the event, so it shows under Courses
            // and can have reminders and a leave-by time.
            if matched == nil, result.category == .classSession {
                matched = course(forCode: event.title.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            switch result.category {
            case .classSession:
                seriesByOccurrence[event.id] = event.seriesKey
                if let id = matched?.id {
                    if let location = event.location?.nilIfBlank { locationsByCourse[id, default: [:]][location, default: 0] += 1 }
                    if roomSuggestions[id] == nil, let notes = event.notes,
                       let room = LocationFormat.roomSuggestion(in: notes, excluding: EventClassifier.courseCode(in: event.title)) {
                        roomSuggestions[id] = room
                    }
                }
                classes.append(ClassSlot(id: event.id, courseID: matched?.id, code: matched?.code ?? event.title,
                                         location: event.location?.nilIfBlank, start: event.start, end: event.end,
                                         paint: matched?.paint ?? .coral,
                                         leaveBy: matched?.leaveMinutesBefore.map { event.start.addingTimeInterval(-TimeInterval($0 * 60)) }))
            case .deadline:
                // All-day deadlines are due at the end of that day.
                let due = event.isAllDay ? event.end.addingTimeInterval(-1) : event.start
                deadlines.append(DeadlineItem(id: event.id, seriesKey: event.seriesKey, title: displayTitle(event.title, code: matched?.code),
                                              courseID: matched?.id, code: matched?.code, due: due, paint: matched?.paint ?? .coral,
                                              isDone: link?.completedOccurrences.contains(event.id) ?? false))
            case .other:
                continue
            }
        }
        deadlines.sort { $0.due < $1.due }
        // The course's room applies where the class meets at its usual (most common) location; a
        // one-off move keeps showing its own calendar location.
        let usual = locationsByCourse.mapValues { counts in counts.max { $0.value < $1.value }?.key }
        for index in classes.indices {
            guard let id = classes[index].courseID, let room = allCourses.first(where: { $0.id == id })?.room?.nilIfBlank else { continue }
            if classes[index].location == nil || classes[index].location == usual[id] ?? nil { classes[index].room = room }
        }
        return StudentSchedule(classes: classes, deadlines: deadlines, courses: allCourses, newCourses: newCourses,
                               seriesByOccurrence: seriesByOccurrence, titleKeyBySeries: titleKeyBySeries,
                               roomSuggestions: roomSuggestions)
    }

    /// SHA-256 of calendar id + trimmed, lowercased title. Stored instead of the title (links keep
    /// only identifiers).
    public static func titleKey(for event: CalendarEvent) -> String {
        let text = event.calendarID + "|" + event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// "BIO 201 Problem set 4 due" → "Problem set 4 due" (the code is shown separately).
    static func displayTitle(_ title: String, code: String?) -> String {
        guard let code else { return title }
        let compact = code.replacingOccurrences(of: " ", with: "")
        var result = title
        for variant in [code, compact] { result = result.replacingOccurrences(of: variant, with: "") }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:·|"))
        // "Lab report due" → "Lab report": the row already reads as a deadline.
        if result.lowercased().hasSuffix(" due") { result = String(result.dropLast(4)) }
        return result.isEmpty ? title : result
    }

    // MARK: Snapshots

    /// Upcoming classes for widgets: from the start of today, ended ones included so the
    /// Today's Schedule widget can show the whole day.
    public static func snapshotClasses(_ classes: [ClassSlot], now: Date, calendar: Calendar = .current) -> [ClassSlot] {
        let startOfToday = calendar.startOfDay(for: now)
        return classes.filter { $0.end > startOfToday }.sorted { $0.start < $1.start }
    }

    public static func nextClassSnapshot(_ classes: [ClassSlot], now: Date, calendar: Calendar = .current) -> NextClassSnapshot {
        NextClassSnapshot(classes: snapshotClasses(classes, now: now, calendar: calendar).filter { $0.end > now }, generatedAt: now)
    }

    public static func todayScheduleSnapshot(_ classes: [ClassSlot], now: Date, calendar: Calendar = .current) -> TodayScheduleSnapshot {
        TodayScheduleSnapshot(classes: snapshotClasses(classes, now: now, calendar: calendar), generatedAt: now)
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
