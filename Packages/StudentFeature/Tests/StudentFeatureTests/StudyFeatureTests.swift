import CoreKit
import Foundation
import Testing
@testable import StudentFeature
@testable import StudentFeatureWidgetKit

private func cal(_ zone: String = "America/Toronto") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in calendar: Calendar = cal()) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func classSlot(_ id: String, _ start: Date, location: String? = "123 Main St", code: String = "BIO 201") -> ClassSlot {
    ClassSlot(id: id, courseID: nil, code: code, location: location, start: start, end: start.addingTimeInterval(3000), paint: .coral)
}

// MARK: - S-06 Grades

@Suite("GradeMath")
struct GradeMathTests {
    let course = UUID()

    func entry(_ score: Double, _ max: Double, _ category: UUID? = nil) -> GradeEntry {
        GradeEntry(courseID: course, categoryID: category, title: "x", score: score, maxScore: max)
    }

    @Test func noGradesIsNil() {
        #expect(GradeMath.coursePercent(entries: [], categories: []) == nil)
        #expect(GradeMath.coursePercent(entries: [entry(0, 0)], categories: []) == nil)
    }

    @Test func withoutCategoriesUsesTotalPoints() {
        // 18/20 + 70/100 = 88/120
        let percent = GradeMath.coursePercent(entries: [entry(18, 20), entry(70, 100)], categories: [])!
        #expect(abs(percent - 88.0 / 120 * 100) < 1e-9)
    }

    @Test func weightedCategoriesRenormaliseWhenSomeAreEmpty() {
        let exams = GradeCategory(courseID: course, name: "Exams", weight: 60)
        let homework = GradeCategory(courseID: course, name: "Homework", weight: 30)
        let labs = GradeCategory(courseID: course, name: "Labs", weight: 10) // nothing graded yet
        let entries = [entry(80, 100, exams.id), entry(9, 10, homework.id), entry(10, 10, homework.id)]
        // Exams 80% × 60 + Homework 95% × 30, over 90.
        let percent = GradeMath.coursePercent(entries: entries, categories: [exams, homework, labs])!
        #expect(abs(percent - (80.0 * 60 + 95.0 * 30) / 90) < 1e-9)
    }

    @Test func uncategorisedEntriesTakeTheUnassignedWeight() {
        let exams = GradeCategory(courseID: course, name: "Exams", weight: 75)
        let entries = [entry(60, 100, exams.id), entry(100, 100, nil), entry(50, 50, UUID())] // deleted category → loose
        let percent = GradeMath.coursePercent(entries: entries, categories: [exams])!
        #expect(abs(percent - (60.0 * 75 + 100.0 * 25) / 100) < 1e-9)
        // Weights already total 100: loose entries don't count.
        let full = GradeCategory(courseID: course, name: "All", weight: 100)
        #expect(GradeMath.coursePercent(entries: [entry(70, 100, full.id), entry(100, 100)], categories: [full]) == 70)
    }

    @Test(arguments: [
        (GradeScale.plusMinus, 93.0, "A", 4.0), (.plusMinus, 92.99, "A−", 3.7), (.plusMinus, 89.995, "A−", 3.7),
        (.plusMinus, 87, "B+", 3.3), (.plusMinus, 59.9, "F", 0), (.plusMinus, 100, "A", 4),
        (.simple, 89.9, "B", 3), (.simple, 90, "A", 4), (.simple, 60, "D", 1),
        (.plusMinus43, 97, "A+", 4.3), (.plusMinus43, 96, "A", 4)
    ])
    func letterBands(scale: GradeScale, percent: Double, letter: String, points: Double) {
        let grade = GradeMath.grade(for: percent, scale: scale)
        #expect(grade.letter == letter)
        #expect(grade.points == points)
    }

    @Test func gpaIsCreditWeighted() {
        // A (4.0) × 4 credits + B (3.0) × 2 credits = 22 / 6
        let gpa = GradeMath.gpa([(95, 4), (85, 2)], scale: .plusMinus)!
        #expect(abs(gpa - 22.0 / 6) < 1e-9)
        #expect(GradeMath.gpa([(95, 0), (85, -1)], scale: .plusMinus) == 3.5) // bad credits count as 1
        #expect(GradeMath.gpa([], scale: .simple) == nil)
    }

    @Test func finalPredictor() {
        // 85 now, final worth 30%, want 90 → (90 − 85 × 0.7) / 0.3 = 101.67
        #expect(GradeMath.neededOnFinal(current: 85, target: 90, finalWeight: 30) == .outOfReach(101.67))
        // 85 now, want 80 → (80 − 59.5) / 0.3 = 68.33
        #expect(GradeMath.neededOnFinal(current: 85, target: 80, finalWeight: 30) == .needs(68.33))
        // 95 now, final 20%, want 70 → (70 − 76) / 0.2 < 0
        #expect(GradeMath.neededOnFinal(current: 95, target: 70, finalWeight: 20) == .secured)
        #expect(GradeMath.neededOnFinal(current: 90, target: 90, finalWeight: 100) == .needs(90))
        #expect(GradeMath.neededOnFinal(current: 90, target: 90, finalWeight: 0) == .invalid)
        #expect(GradeMath.neededOnFinal(current: 90, target: 90, finalWeight: 120) == .invalid)
        // Exactly 100 is reachable.
        #expect(GradeMath.neededOnFinal(current: 80, target: 90, finalWeight: 50) == .needs(100))
    }
}

// MARK: - S-05 Assignments

@Suite("Assignments")
struct AssignmentTests {
    let bio = Course(code: "BIO 201", paint: .sand)

    @Test func becomeDeadlinesWithCoursePaint() {
        let a = Assignment(title: "Lab report", courseID: bio.id, due: at(2026, 10, 5, 23, 59))
        let item = AssignmentPlanner.deadlineItems([a], courses: [bio])[0]
        #expect(item.assignmentID == a.id)
        #expect(item.code == "BIO 201" && item.paint == .sand)
        #expect(item.id == a.occurrenceID)
        let loose = AssignmentPlanner.deadlineItems([Assignment(title: "x", courseID: UUID(), due: .now)], courses: [bio])[0]
        #expect(loose.courseID == nil && loose.paint == .coral)
    }

    @Test func mergedSortsByDue() {
        let items = AssignmentPlanner.deadlineItems([Assignment(title: "late", due: at(2026, 10, 9)), Assignment(title: "soon", due: at(2026, 10, 2))],
                                                    courses: [])
        let calendarItem = DeadlineItem(id: "c", seriesKey: "c", title: "cal", courseID: nil, code: nil, due: at(2026, 10, 4), paint: .tide, isDone: false)
        #expect(AssignmentPlanner.merged(calendar: [calendarItem], assignments: items).map(\.title) == ["soon", "cal", "late"])
    }

    @Test func widgetSnapshotKeepsOpenFutureItems() {
        let now = at(2026, 10, 3, 12)
        let items = AssignmentPlanner.deadlineItems([
            Assignment(title: "done", due: at(2026, 10, 4), isDone: true),
            Assignment(title: "past", due: at(2026, 10, 2)),
            Assignment(title: "open", due: at(2026, 10, 5))
        ], courses: [])
        #expect(AssignmentPlanner.widgetSnapshot(items, now: now).items.map(\.title) == ["open"])
    }

    @Test func snapshotIsCappedAndSmall() throws {
        let now = at(2026, 10, 1)
        let many = (0..<50).map { DueSlot(id: "\($0)", title: String(repeating: "x", count: 60), code: "BIO 201", courseID: UUID(),
                                          due: now.addingTimeInterval(Double($0) * 3600), paint: .coral) }
        let snapshot = AssignmentsSnapshot(items: many, generatedAt: now)
        #expect(snapshot.items.count == AssignmentsSnapshot.maxItems)
        #expect(snapshot.items.first?.id == "0")
        #expect(try JSONEncoder().encode(snapshot).count < 50_000)
    }

    @Test func providerDropsItemsAsTheyComeDue() {
        let now = at(2026, 10, 1, 9)
        let snapshot = AssignmentsSnapshot(items: [
            DueSlot(id: "a", title: "a", code: nil, courseID: nil, due: now.addingTimeInterval(3600), paint: .coral),
            DueSlot(id: "b", title: "b", code: nil, courseID: nil, due: now.addingTimeInterval(48 * 3600), paint: .coral)
        ], generatedAt: now)
        let entries = AssignmentsProvider.entries(snapshot: snapshot, now: now)
        #expect(entries.map(\.date) == [now, now.addingTimeInterval(3600)])
        #expect(entries.map { $0.items?.count } == [2, 1])
        #expect(AssignmentsProvider.entries(snapshot: nil, now: now).first?.items == nil)
    }

    @Test func dueRemindersRespectOffsetDoneAndPast() {
        let c = cal()
        let now = at(2026, 10, 30, 12, in: c)
        let open = Assignment(title: "Essay", courseID: bio.id, due: at(2026, 11, 1, 9, in: c)) // across DST fall-back
        let done = Assignment(title: "Done", due: at(2026, 11, 2, 9, in: c), isDone: true)
        let tooSoon = Assignment(title: "Soon", due: now.addingTimeInterval(1800))
        let plan = AssignmentPlanner.reminders([open, done, tooSoon], courses: [bio], offset: .oneDay, now: now, calendar: c)
        #expect(plan.count == 1)
        #expect(plan[0].fireDate == at(2026, 10, 31, 9, in: c)) // same wall-clock time, 25 h earlier
        #expect(plan[0].identifier.hasPrefix(AssignmentPlanner.identifierPrefix))
        #expect(plan[0].body.hasPrefix("BIO 201"))
        #expect(AssignmentPlanner.reminders([open], courses: [], offset: nil, now: now).isEmpty)
    }

    @Test func changedDueDateChangesIdentifier() {
        var a = Assignment(title: "Essay", due: at(2026, 11, 3, 9))
        let first = AssignmentPlanner.reminders([a], courses: [], offset: .oneHour, now: at(2026, 11, 1))[0].identifier
        a.due = at(2026, 11, 4, 9)
        let second = AssignmentPlanner.reminders([a], courses: [], offset: .oneHour, now: at(2026, 11, 1))[0].identifier
        #expect(first != second)
    }
}

@Suite("Reminders import")
struct ReminderImportTests {
    let bio = Course(code: "BIO 201", paint: .coral)
    let now = at(2026, 10, 1)

    @Test func importsNewDatedRemindersAndGuessesCourse() {
        let result = ReminderImporter.merge([
            ReminderItem(externalID: "r1", title: "BIO 201 problem set", due: at(2026, 10, 3), isCompleted: false),
            ReminderItem(externalID: "r2", title: "Buy milk", due: nil, isCompleted: false),
            ReminderItem(externalID: "r3", title: "Old thing", due: at(2026, 9, 1), isCompleted: true),
            ReminderItem(externalID: "r4", title: "  ", due: at(2026, 10, 3), isCompleted: false)
        ], listID: "L", into: [], courses: [bio], now: now)
        #expect(result.changed.count == 1)
        #expect(result.changed[0].courseID == bio.id)
        #expect(result.changed[0].reminderExternalID == "r1" && result.changed[0].reminderListID == "L")
        #expect(result.removed.isEmpty)
    }

    @Test func updatesKeepUserChoicesAndCompletionOnlyMarksDone() {
        let other = UUID()
        let existing = Assignment(title: "Old title", courseID: other, due: at(2026, 10, 3), isDone: false, reminderExternalID: "r1", reminderListID: "L")
        let result = ReminderImporter.merge([ReminderItem(externalID: "r1", title: "New title", due: at(2026, 10, 4), isCompleted: true)],
                                            listID: "L", into: [existing], courses: [bio], now: now)
        #expect(result.changed.count == 1)
        let updated = result.changed[0]
        #expect(updated.id == existing.id && updated.courseID == other)
        #expect(updated.title == "New title" && updated.due == at(2026, 10, 4) && updated.isDone)

        // Done here, not completed in Reminders: stays done (we never un-tick).
        var done = existing
        done.isDone = true
        let again = ReminderImporter.merge([ReminderItem(externalID: "r1", title: "Old title", due: at(2026, 10, 3), isCompleted: false)],
                                           listID: "L", into: [done], courses: [], now: now)
        #expect(again.changed.isEmpty)
    }

    @Test func removesImportsDeletedFromTheList() {
        let gone = Assignment(title: "Gone", due: at(2026, 10, 3), reminderExternalID: "r9", reminderListID: "L")
        let otherList = Assignment(title: "Other", due: at(2026, 10, 3), reminderExternalID: "r8", reminderListID: "M")
        let manual = Assignment(title: "Manual", due: at(2026, 10, 3))
        let result = ReminderImporter.merge([], listID: "L", into: [gone, otherList, manual], courses: [], now: now)
        #expect(result.removed == [gone.id])
    }
}

// MARK: - S-07 Leave by

@Suite("LeaveBy")
struct LeaveByTests {
    let now = at(2026, 10, 1, 7)

    @Test func leaveByTimeIsStartMinusTravelAndBufferRoundedDown() {
        let slot = classSlot("c1", at(2026, 10, 1, 9))
        let plan = LeaveByPlanner.plan(classes: [slot], etas: ["123 Main St": 1100], bufferMinutes: 5, mode: .walking,
                                       remindedClassIDs: [], now: now)
        #expect(plan.count == 1)
        // 9:00 − 18m20s − 5m = 8:36:40 → 8:36
        #expect(plan[0].fireDate == at(2026, 10, 1, 8, 36))
        #expect(plan[0].identifier.hasPrefix(LeaveByPlanner.identifierPrefix))
        #expect(plan[0].body.contains("19 min"))
    }

    @Test func unknownETAFallsBackOnlyWhenNoClassReminder() {
        let slot = classSlot("c1", at(2026, 10, 1, 9), location: "Room 3B")
        let fallback = LeaveByPlanner.plan(classes: [slot], etas: [:], bufferMinutes: 5, mode: .walking, remindedClassIDs: [], now: now)
        #expect(fallback.map(\.fireDate) == [at(2026, 10, 1, 8, 45)])
        #expect(LeaveByPlanner.plan(classes: [slot], etas: [:], bufferMinutes: 5, mode: .walking, remindedClassIDs: ["c1"], now: now).isEmpty)
        // An absurd ETA (bad geocode) counts as unknown.
        let absurd = LeaveByPlanner.plan(classes: [slot], etas: ["Room 3B": 18_000], bufferMinutes: 0, mode: .driving, remindedClassIDs: [], now: now)
        #expect(absurd.first?.identifier.hasSuffix(".fallback") == true)
    }

    @Test func skipsPastLeaveTimesAndFarClassesAndNoLocation() {
        let soon = classSlot("soon", now.addingTimeInterval(10 * 60))
        let far = classSlot("far", now.addingTimeInterval(30 * 3600))
        let nowhere = classSlot("nowhere", now.addingTimeInterval(3600), location: " ")
        let plan = LeaveByPlanner.plan(classes: [soon, far, nowhere], etas: ["123 Main St": 1200], bufferMinutes: 5, mode: .transit,
                                       remindedClassIDs: [], now: now)
        #expect(plan.isEmpty)
    }

    @Test func lookupsAreDistinctSoonestFirstAndCapped() {
        let classes = (0..<8).map { classSlot("c\($0)", now.addingTimeInterval(Double($0 + 1) * 3600), location: "Place \($0 % 6)") }
            + [classSlot("dup", now.addingTimeInterval(1800), location: "Place 0")]
        #expect(LeaveByPlanner.locationsToLookUp(classes, now: now) == ["Place 0", "Place 1", "Place 2", "Place 3"])
    }

    @Test func etaMemoryHashesKeysAndExpires() throws {
        let group = AppGroupContainer.temporary()
        let memory = ETAMemory(appGroup: group)
        memory.remember(key: "walking|123 Main St", eta: 600, at: now)
        #expect(memory.recall(key: "walking|123 Main St", now: now.addingTimeInterval(3600), maxAge: 12 * 3600) == 600)
        #expect(memory.recall(key: "walking|123 Main St", now: now.addingTimeInterval(13 * 3600), maxAge: 12 * 3600) == nil)
        let raw = try String(contentsOf: memory.url, encoding: .utf8)
        #expect(!raw.contains("Main"))
    }
}

// MARK: - Reminder window across sources

@Suite("Combined reminders")
struct CombinedReminderTests {
    @Test func combineSortsAndCaps() {
        func r(_ id: String, _ minutes: Double) -> PlannedReminder {
            PlannedReminder(identifier: id, fireDate: Date(timeIntervalSince1970: minutes * 60), title: "", body: "", courseID: nil)
        }
        let combined = ReminderPlanner.combine([r("student.class.b", 2), r("student.class.d", 4)], [r("student.due.a", 1)], [r("student.leave.c", 3)], budget: 3)
        #expect(combined.map(\.identifier) == ["student.due.a", "student.class.b", "student.leave.c"])
    }

    @Test func syncLeavesFocusNotificationsAlone() async {
        let center = FakeCenter(pending: ["studentfocus.0.1", "student.due.old", "student.leave.old", "wellness.mood.1"])
        await ReminderScheduler(center: center).reschedule([])
        #expect(Set(await center.pendingIdentifiers()) == ["studentfocus.0.1", "wellness.mood.1"])
    }
}

// MARK: - S-08 Focus

@Suite("Focus")
struct FocusTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func pomodoroLayout() {
        let plan = FocusPlan(preset: .pomodoro, start: start)
        #expect(plan.blocks.map(\.kind) == [.focus, .rest, .focus, .rest, .focus, .rest, .focus])
        #expect(plan.blocks.map(\.round) == [1, 1, 2, 2, 3, 3, 4])
        #expect(plan.end == start.addingTimeInterval((4 * 25 + 3 * 5) * 60))
        #expect(plan.block(at: start.addingTimeInterval(26 * 60))?.kind == .rest)
        #expect(plan.block(at: plan.end) == nil && plan.isFinished(at: plan.end))
        // No break minutes: back-to-back focus blocks.
        #expect(FocusPlan(preset: FocusPreset(focusMinutes: 10, breakMinutes: 0, rounds: 3), start: start).blocks.count == 3)
    }

    @Test func presetClamps() {
        let preset = FocusPreset(focusMinutes: 0, breakMinutes: 500, rounds: 99)
        #expect(preset.focusMinutes == 1 && preset.breakMinutes == 60 && preset.rounds == 8)
    }

    @Test func resumeShiftsRemainingBlocks() {
        let plan = FocusPlan(preset: .pomodoro, start: start)
        let pausedAt = start.addingTimeInterval(10 * 60)
        let resumed = plan.resumed(pausedAt: pausedAt, now: pausedAt.addingTimeInterval(7 * 60))
        #expect(resumed.blocks[0].end == plan.blocks[0].end.addingTimeInterval(7 * 60))
        #expect(resumed.end == plan.end.addingTimeInterval(7 * 60))
        // Remaining time in the running block is unchanged by the pause.
        #expect(resumed.blocks[0].end.timeIntervalSince(pausedAt.addingTimeInterval(7 * 60)) == 15 * 60)
    }

    @Test func pausedActivityStateShowsRemaining() {
        let session = FocusSessionState(plan: FocusPlan(preset: .pomodoro, start: start), title: "Lab", courseID: nil, paint: .coral,
                                        pausedAt: start.addingTimeInterval(5 * 60))
        let state = session.activityState(at: start.addingTimeInterval(3 * 3600))! // long after: still the paused block
        #expect(state.pausedRemaining == 20 * 60 && state.round == 1 && state.kind == .focus)
        #expect(focusClock(state.pausedRemaining!) == "20:00")
        #expect(!session.isFinished(at: start.addingTimeInterval(3 * 3600)))
    }

    @Test func notificationsAtEachRemainingBlockEnd() {
        let session = FocusSessionState(plan: FocusPlan(preset: .deepWork, start: start), title: "Essay", courseID: nil, paint: .sage)
        let plan = FocusNotifications.plan(session, now: start.addingTimeInterval(55 * 60)) // in the break
        #expect(plan.map(\.fireDate) == [start.addingTimeInterval(60 * 60), start.addingTimeInterval(110 * 60)])
        #expect(plan.map(\.title) == ["Back to focus", "Focus session done"])
        #expect(plan.allSatisfy { $0.identifier.hasPrefix(FocusNotifications.identifierPrefix) })
        var paused = session
        paused.pausedAt = start
        #expect(FocusNotifications.plan(paused, now: start).isEmpty)
    }

    @MainActor
    @Test func timerLifecycleSchedulesAndPersists() async {
        let group = AppGroupContainer.temporary()
        let center = FakeCenter(pending: ["student.class.x"])
        let clock = Clock(start)
        let timer = FocusTimer(appGroup: group, center: center, liveActivities: false, now: { clock.now })
        await timer.start(preset: .pomodoro, title: "Lab", courseID: nil, paint: .coral, permissions: nil)
        #expect(await center.pendingIdentifiers().filter { $0.hasPrefix("studentfocus.") }.count == 7)

        clock.now = start.addingTimeInterval(10 * 60)
        await timer.pause()
        #expect(timer.isPaused)
        #expect(await center.pendingIdentifiers() == ["student.class.x"])

        // A new instance (app relaunch) restores the paused session from the App Group.
        let reopened = FocusTimer(appGroup: group, center: center, liveActivities: false, now: { clock.now })
        #expect(reopened.state == timer.state)

        clock.now = start.addingTimeInterval(20 * 60)
        await timer.resume()
        #expect(timer.state?.plan.blocks[0].end == start.addingTimeInterval(35 * 60))
        #expect(await center.pendingIdentifiers().count == 8)

        clock.now = start.addingTimeInterval(5 * 3600)
        await timer.restore() // finished while away: cleared
        #expect(timer.state == nil)
        #expect(await center.pendingIdentifiers() == ["student.class.x"])
        #expect(FocusTimer(appGroup: group, center: center, liveActivities: false).state == nil)
    }

    @Test func deepLink() {
        #expect(FocusDeepLink.isFocus(FocusDeepLink.url))
        #expect(AppSection(deepLink: FocusDeepLink.url) == .student)
        #expect(!FocusDeepLink.isFocus(StudentDeepLink.url(course: UUID())))
    }
}

/// Mutable test clock.
final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ date: Date) { value = date }
    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

// MARK: - Persistence

@Suite("Study persistence")
struct StudyPersistenceTests {
    @Test func fileRepositoryRoundTripsAssignmentsAndGrades() async throws {
        let group = AppGroupContainer.temporary()
        let repo = FileStudentRepository(appGroup: group)
        let course = UUID()
        let assignment = Assignment(title: "Essay", courseID: course, due: at(2026, 10, 9))
        let category = GradeCategory(courseID: course, name: "Exams", weight: 50)
        let entry = GradeEntry(courseID: course, categoryID: category.id, title: "Midterm", score: 41, maxScore: 50)
        try await repo.save(assignment)
        try await repo.save(category)
        try await repo.save(entry)

        let reopened = FileStudentRepository(appGroup: group)
        #expect(await reopened.assignments() == [assignment])
        #expect(await reopened.gradeCategories() == [category])
        #expect(await reopened.gradeEntries() == [entry])
        try await reopened.deleteAssignment(id: assignment.id)
        try await reopened.deleteGradeCategory(id: category.id)
        try await reopened.deleteGradeEntry(id: entry.id)
        let empty = FileStudentRepository(appGroup: group)
        #expect(await empty.assignments().isEmpty)
        #expect(await empty.gradeCategories().isEmpty)
        #expect(await empty.gradeEntries().isEmpty)
    }

    @Test func olderFilesStillLoad() async throws {
        let group = AppGroupContainer.temporary()
        let course = Course(code: "BIO 201", paint: .tide)
        // A records file and settings file as written before S-05..S-08 (no new keys, no credits).
        var courseJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(course)) as! [String: Any]
        courseJSON.removeValue(forKey: "credits")
        let records: [String: Any] = ["courses": [courseJSON], "links": [], "rules": []]
        let dir = group.applicationSupportURL.appending(path: "Student")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: records).write(to: dir.appending(path: "records.json"))
        try Data(#"{"schoolCalendarIDs":["cal"],"deferredConnect":true}"#.utf8).write(to: dir.appending(path: "settings.json"))

        let repo = FileStudentRepository(appGroup: group)
        #expect(await repo.courses().map(\.code) == ["BIO 201"])
        #expect(await repo.courses().first?.credits == nil)
        #expect(await repo.assignments().isEmpty)
        let settings = await repo.settings()
        #expect(settings.schoolCalendarIDs == ["cal"] && settings.deferredConnect)
        #expect(settings.gradeScale == .plusMinus && !settings.leaveByEnabled && settings.assignmentReminder == nil)
        #expect(settings.focusPreset == .pomodoro)
    }

    @Test func settingsRoundTrip() throws {
        var settings = StudentSettings()
        settings.remindersListID = "L"
        settings.assignmentReminder = .oneDay
        settings.gradeScale = .plusMinus43
        settings.leaveByEnabled = true
        settings.travelMode = .transit
        settings.focusPreset = .deepWork
        let decoded = try JSONDecoder().decode(StudentSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func modelSyncsNewEntitiesAndEncryptsGrades() throws {
        #expect(StudentModel.syncedEntityNames.contains(StudentModel.Entity.assignment))
        #expect(StudentModel.syncedEntityNames.contains(StudentModel.Entity.gradeEntry))
        let cloud = StudentModel.makeEntities()[.cloud] ?? []
        let grade = try #require(cloud.first { $0.name == StudentModel.Entity.gradeEntry })
        #expect(grade.attributesByName[PersistenceModel.Attribute.payload]?.allowsCloudEncryption == true)
        let assignment = try #require(cloud.first { $0.name == StudentModel.Entity.assignment })
        #expect(assignment.attributesByName[PersistenceModel.Attribute.payload]?.allowsCloudEncryption == false)
    }
}

@Suite("Course merging (one course per code across iPhones)")
struct CourseMergerTests {
    let old = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func keepsSetUpCourseThenNewestAndFillsBlanks() {
        let a = Course(code: "ICS 31", paint: .coral, updatedAt: old.addingTimeInterval(100))
        var b = Course(code: "ICS31", name: "Intro", paint: .sage, updatedAt: old)
        b.isSetUp = true
        b.room = nil
        var c = Course(code: "ics 31", paint: .tide, updatedAt: old.addingTimeInterval(50))
        c.room = "ICS 192"
        let other = Course(code: "MATH 2A", paint: .sand, updatedAt: old)
        let plan = CourseMerger.plan([a, b, c, other])
        #expect(plan.keepers.count == 2)
        let kept = plan.keepers.first { $0.id == b.id }
        #expect(kept?.room == "ICS 192")
        #expect(kept?.name == "Intro")
        #expect(plan.replacements == [a.id: b.id, c.id: b.id])
    }

    @Test func noDuplicatesNoChanges() {
        let plan = CourseMerger.plan([Course(code: "A 1", paint: .coral), Course(code: "B 2", paint: .sage)])
        #expect(plan.replacements.isEmpty)
    }
}
