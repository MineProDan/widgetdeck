import Foundation

/// Decides whether a calendar event is a class, a deadline or something else (S-02).
///
/// Priority (first match wins):
/// 1. the user's tag for the series,
/// 2. weekly recurrence → class,
/// 3. all-day, or a keyword (due / submit / exam / quiz) → deadline,
/// 4. a course code in the title (`[A-Z]{2,4}\s?\d{3}`) → class,
/// 5. otherwise → other.
///
/// The course code is extracted independently of the category, so a deadline titled
/// "BIO 201 problem set due" still links to BIO 201.
public enum EventClassifier {
    public enum Reason: String, Sendable, Equatable {
        case userTag, weeklyRecurrence, allDay, keyword, courseCode, none
    }

    public struct Result: Sendable, Equatable {
        public var category: EventCategory
        public var courseCode: String?
        public var reason: Reason
    }

    static let deadlineKeywords = ["due", "submit", "exam", "quiz"]

    public static func classify(_ event: CalendarEvent, userTag: EventCategory? = nil) -> Result {
        let code = courseCode(in: event.title)
        if let userTag { return Result(category: userTag, courseCode: code, reason: .userTag) }
        if event.isWeeklyRecurring && !event.isAllDay { return Result(category: .classSession, courseCode: code, reason: .weeklyRecurrence) }
        if event.isAllDay { return Result(category: .deadline, courseCode: code, reason: .allDay) }
        if containsDeadlineKeyword(event.title) { return Result(category: .deadline, courseCode: code, reason: .keyword) }
        if code != nil { return Result(category: .classSession, courseCode: code, reason: .courseCode) }
        return Result(category: .other, courseCode: nil, reason: .none)
    }

    /// First course code in `text`, normalised to "ABC 123". Case-sensitive: codes are capitals.
    public static func courseCode(in text: String) -> String? {
        guard let match = text.firstMatch(of: #/\b([A-Z]{2,4})\s?(\d{3})\b/#) else { return nil }
        return "\(match.output.1) \(match.output.2)"
    }

    /// Whole-word, case-insensitive keyword match ("Due", "submitted" does not match "submit").
    static func containsDeadlineKeyword(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter }
        return words.contains { deadlineKeywords.contains(String($0)) }
    }
}
