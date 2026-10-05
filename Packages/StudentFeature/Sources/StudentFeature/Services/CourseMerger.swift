import Foundation

/// Each iPhone creates its own course for a class code it finds in the calendar, so after iCloud sync
/// the same class can exist twice with different ids. Settings saved on one copy then don't reach
/// the copy the schedule (and widgets) happen to use. This picks one course per code to keep.
public enum CourseMerger {
    public struct Plan: Equatable, Sendable {
        /// The course to keep for each code, with blank fields filled from its duplicates.
        public var keepers: [Course]
        /// Duplicate course id → the id of the course that replaces it.
        public var replacements: [UUID: UUID]
    }

    /// Keeps the course that has been through setup, then the most recently edited one.
    public static func plan(_ courses: [Course]) -> Plan {
        var keepers: [Course] = []
        var replacements: [UUID: UUID] = [:]
        let groups = Dictionary(grouping: courses) { $0.code.uppercased().filter { !$0.isWhitespace } }
        for group in groups.values {
            let ranked = group.sorted { a, b in
                if (a.isSetUp == true) != (b.isSetUp == true) { return a.isSetUp == true }
                if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
                return a.id.uuidString < b.id.uuidString
            }
            var keeper = ranked[0]
            for other in ranked.dropFirst() {
                replacements[other.id] = keeper.id
                keeper.name = keeper.name ?? other.name
                keeper.credits = keeper.credits ?? other.credits
                keeper.room = keeper.room ?? other.room
            }
            keepers.append(keeper)
        }
        return Plan(keepers: keepers.sorted { $0.code < $1.code }, replacements: replacements)
    }
}
