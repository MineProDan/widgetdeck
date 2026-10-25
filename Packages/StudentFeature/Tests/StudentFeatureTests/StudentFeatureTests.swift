import CoreKit
import Foundation
import Testing
@testable import StudentFeature
@testable import StudentFeatureWidgetKit

// MARK: - Helpers

private func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in cal: Calendar = calendar("America/Toronto")) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func event(_ title: String, start: Date = date(2026, 10, 1, 9), minutes: Double = 60, allDay: Bool = false,
                   weekly: Bool = false, series: String? = nil, id: String? = nil) -> CalendarEvent {
    CalendarEvent(id: id ?? "\(title)@\(start.timeIntervalSince1970)", seriesKey: series ?? title, calendarID: "school", title: title,
                  start: start, end: start.addingTimeInterval(minutes * 60), isAllDay: allDay, isWeeklyRecurring: weekly)
}

private func slot(_ code: String, _ start: Date, minutes: Double = 60, courseID: UUID? = nil) -> ClassSlot {
    ClassSlot(id: "\(code)@\(start.timeIntervalSince1970)", courseID: courseID, code: code, location: "Room 3B",
              start: start, end: start.addingTimeInterval(minutes * 60), paint: .coral)
}

@Suite("Module")
struct ModuleTests {
    @Test func belongsToSection() {
        #expect(StudentWidgetModule.section == .student)
    }

    @Test func deepLinkRoundTrip() {
        let id = UUID()
        let url = StudentDeepLink.url(course: id)
        #expect(AppSection(deepLink: url) == .student)
        #expect(StudentDeepLink.courseID(from: url) == id)
        #expect(StudentDeepLink.courseID(from: StudentDeepLink.url(course: nil)) == nil)
    }
}

// MARK: - Classifier (table-driven)

@Suite("EventClassifier")
struct EventClassifierTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let title: String
        let allDay: Bool
        let weekly: Bool
        let tag: EventCategory?
        let category: EventCategory
        let code: String?
        let reason: EventClassifier.Reason
        var testDescription: String { title }
    }

    static let cases: [Case] = [
        // 1. User tag beats everything.
        Case(title: "BIO 201 Lecture", allDay: false, weekly: true, tag: .other, category: .other, code: "BIO 201", reason: .userTag),
        Case(title: "Dentist", allDay: false, weekly: false, tag: .classSession, category: .classSession, code: nil, reason: .userTag),
        Case(title: "Quiz review", allDay: true, weekly: false, tag: .classSession, category: .classSession, code: nil, reason: .userTag),
        // 2. Weekly recurrence = class (even with a keyword).
        Case(title: "Yoga", allDay: false, weekly: true, tag: nil, category: .classSession, code: nil, reason: .weeklyRecurrence),
        Case(title: "ENG 110 quiz", allDay: false, weekly: true, tag: nil, category: .classSession, code: "ENG 110", reason: .weeklyRecurrence),
        // 3. All-day or keyword = deadline.
        Case(title: "Essay", allDay: true, weekly: false, tag: nil, category: .deadline, code: nil, reason: .allDay),
        Case(title: "Weekly all-day thing", allDay: true, weekly: true, tag: nil, category: .deadline, code: nil, reason: .allDay),
        Case(title: "Lab report due", allDay: false, weekly: false, tag: nil, category: .deadline, code: nil, reason: .keyword),
        Case(title: "SUBMIT portfolio", allDay: false, weekly: false, tag: nil, category: .deadline, code: nil, reason: .keyword),
        Case(title: "CHEM150 Exam", allDay: false, weekly: false, tag: nil, category: .deadline, code: "CHEM 150", reason: .keyword),
        Case(title: "Pop quiz!", allDay: false, weekly: false, tag: nil, category: .deadline, code: nil, reason: .keyword),
        // Whole words only.
        Case(title: "Submitted forms pickup", allDay: false, weekly: false, tag: nil, category: .other, code: nil, reason: .none),
        Case(title: "Residue lab tour", allDay: false, weekly: false, tag: nil, category: .other, code: nil, reason: .none),
        // 4. Course code = class.
        Case(title: "PSY 101 guest lecture", allDay: false, weekly: false, tag: nil, category: .classSession, code: "PSY 101", reason: .courseCode),
        Case(title: "MATH241 tutorial", allDay: false, weekly: false, tag: nil, category: .classSession, code: "MATH 241", reason: .courseCode),
        // Lowercase or too-long prefixes are not codes.
        Case(title: "bio 201 study", allDay: false, weekly: false, tag: nil, category: .other, code: nil, reason: .none),
        Case(title: "ABCDE 123", allDay: false, weekly: false, tag: nil, category: .other, code: nil, reason: .none),
        // 5. Everything else.
        Case(title: "Coffee with Sam", allDay: false, weekly: false, tag: nil, category: .other, code: nil, reason: .none)
    ]

    @Test(arguments: cases)
    func classify(_ c: Case) {
        let result = EventClassifier.classify(event(c.title, allDay: c.allDay, weekly: c.weekly), userTag: c.tag)
        #expect(result.category == c.category)
        #expect(result.reason == c.reason)
        if c.reason != .userTag || c.code != nil {
            #expect(result.courseCode == c.code)
        }
    }

    @Test func correctionAppliesToWholeSeries() {
        let first = event("Yoga", start: date(2026, 10, 1, 9), weekly: true, series: "S1", id: "a")
        let second = event("Yoga", start: date(2026, 10, 8, 9), weekly: true, series: "S1", id: "b")
        let link = CourseEventLink(seriesKey: "S1", userCategory: .other)
        let schedule = ScheduleBuilder.build(events: [first, second], links: [link], courses: [])
        #expect(schedule.classes.isEmpty)
    }
}

// MARK: - Schedule builder + snapshots

@Suite("ScheduleBuilder")
struct ScheduleBuilderTests {
    @Test func autoCreatesCoursesWithRotatingPaint() {
        let events = [event("BIO 201", weekly: true), event("ENG 110", start: date(2026, 10, 1, 10), weekly: true),
                      event("CHEM 150", start: date(2026, 10, 1, 11), weekly: true), event("PSY 101", start: date(2026, 10, 1, 13), weekly: true),
                      event("BIO 201", start: date(2026, 10, 2, 9), weekly: true, series: "BIO 201")]
        let schedule = ScheduleBuilder.build(events: events, links: [], courses: [])
        #expect(schedule.newCourses.map(\.code) == ["BIO 201", "ENG 110", "CHEM 150", "PSY 101"])
        #expect(schedule.newCourses.map(\.paint) == [.coral, .sand, .tide, .sage])
        #expect(schedule.classes.count == 5)
        #expect(Set(schedule.classes.filter { $0.code == "BIO 201" }.compactMap(\.courseID)).count == 1)
    }

    @Test func userCourseAssignmentWins() {
        let course = Course(code: "CHEM 150", paint: .tide)
        let link = CourseEventLink(seriesKey: "Lab", courseID: course.id, userCategory: .classSession)
        let schedule = ScheduleBuilder.build(events: [event("Lab", series: "Lab")], links: [link], courses: [course])
        #expect(schedule.classes.first?.courseID == course.id)
        #expect(schedule.classes.first?.code == "CHEM 150")
        #expect(schedule.newCourses.isEmpty)
    }

    @Test(arguments: [
        ("School of Engineering, 4100 Maple Hall, Springfield, IL 62704, United States", "4100 Maple Hall"),
        ("Room 3B", "Room 3B"),
        ("Science Library, Springfield, IL 62704", "Science Library"),
        ("Main Campus\nEngineering Building 201", "Engineering Building 201"),
        ("Starbucks, 123 Main St, Springfield, IL 62701", "Starbucks"),
    ])
    func shortLocation(full: String, short: String) {
        #expect(LocationFormat.short(full) == short)
    }

    @Test func autoLeaveLooksPastAlertWindow() {
        // Saturday 3 PM; the next class is Monday 12:30 (45 h away, outside the 18 h alert window).
        let monday = slot("ICS 31", date(2026, 10, 5, 12, 30))
        let now = date(2026, 10, 3, 15)
        #expect(LeaveByPlanner.locationsToLookUp([monday], now: now).isEmpty)
        #expect(LeaveByPlanner.locationsToLookUp([monday], now: now, lookahead: LeaveByPlanner.widgetLookahead) == ["Room 3B"])
    }

    @Test func leaveAlertNamesTheBuildingNotTheStreetAddress() {
        // Alerts show on the Lock Screen, so the full calendar address must not appear.
        let now = date(2026, 10, 1, 8)
        var lecture = slot("BIO 201", date(2026, 10, 1, 10, 30))
        let full = "School of Engineering, 4100 Maple Hall, Springfield, IL 62704, United States"
        lecture.location = full
        let alerts = LeaveByPlanner.plan(classes: [lecture], etas: [full: 19 * 60], bufferMinutes: 0, mode: .walking,
                                         remindedClassIDs: [], now: now)
        let body = try? #require(alerts.first?.body)
        #expect(body?.contains("4100 Maple Hall") == true)
        #expect(body?.contains("Springfield") == false)
        #expect(body?.contains("62704") == false)
    }

    @Test func roomSuggestionFromNotes() {
        #expect(LocationFormat.roomSuggestion(in: "Lecture in ICS 192 with Prof. Lee", excluding: nil) == "ICS 192")
        #expect(LocationFormat.roomSuggestion(in: "BIO 201 meets in Rm 3B", excluding: "BIO 201") == "Rm 3B")
        #expect(LocationFormat.roomSuggestion(in: "Bring a laptop", excluding: nil) == nil)
    }

    @Test func courseRoomShowsOnlyAtUsualLocation() {
        let course = Course(code: "BIO 201", paint: .coral, room: "ICS 192")
        var usual1 = event("BIO 201", start: date(2026, 10, 5, 9), weekly: true, series: "bio", id: "a")
        var usual2 = event("BIO 201", start: date(2026, 10, 7, 9), weekly: true, series: "bio", id: "b")
        var moved = event("BIO 201", start: date(2026, 10, 9, 9), weekly: true, series: "bio", id: "c")
        usual1.location = "Maple Hall, Springfield"; usual2.location = "Maple Hall, Springfield"; moved.location = "Science Library"
        let classes = ScheduleBuilder.build(events: [usual1, usual2, moved], links: [], courses: [course]).classes
        #expect(classes.map(\.shortLocation) == ["ICS 192", "ICS 192", "Science Library"])
    }

    @Test func correctionSurvivesNewSeriesIdentifier() {
        let old = event("Lecture", series: "old-series")
        var link = CourseEventLink(seriesKey: "old-series", userCategory: .classSession)
        link.titleKey = ScheduleBuilder.titleKey(for: old)
        // iOS split the series ("edit all future events"): same title, new identifier.
        let schedule = ScheduleBuilder.build(events: [event("Lecture", series: "new-series")], links: [link], courses: [])
        #expect(schedule.classes.count == 1)
    }

    @Test func classWithoutCodeGetsACourse() {
        let link = CourseEventLink(seriesKey: "Lecture", courseID: nil, userCategory: .classSession)
        let schedule = ScheduleBuilder.build(events: [event("Lecture", series: "Lecture")], links: [link], courses: [])
        #expect(schedule.newCourses.map(\.code) == ["Lecture"])
        #expect(schedule.classes.first?.courseID == schedule.newCourses.first?.id)
    }

    @Test func courseLeaveByComesFromMinutesBefore() {
        let course = Course(code: "CHEM 150", paint: .tide, leaveMinutesBefore: 20)
        let link = CourseEventLink(seriesKey: "Lab", courseID: course.id, userCategory: .classSession)
        let schedule = ScheduleBuilder.build(events: [event("Lab", series: "Lab")], links: [link], courses: [course])
        #expect(schedule.classes.first?.leaveBy == date(2026, 10, 1, 8, 40))
        let unset = ScheduleBuilder.build(events: [event("Lab", series: "Lab")], links: [link], courses: [Course(id: course.id, code: "CHEM 150", paint: .tide)])
        #expect(unset.classes.first?.leaveBy == nil)
    }

    @Test func autoLeaveByUsesETAAndFallsBack() {
        let auto = UUID(), fixed = UUID()
        var a = slot("BIO 201", date(2026, 10, 1, 9), courseID: auto)
        var b = slot("ENG 110", date(2026, 10, 1, 10), courseID: auto)
        b.location = "Unknown place"
        b.leaveBy = date(2026, 10, 1, 9, 45)
        let c = slot("PSY 101", date(2026, 10, 1, 11), courseID: fixed)
        a.leaveBy = nil
        let out = LeaveByPlanner.applyAuto(to: [a, b, c], autoCourseIDs: [auto], etas: ["Room 3B": 1170.0], bufferMinutes: 5)
        #expect(out[0].leaveBy == date(2026, 10, 1, 8, 35)) // 9:00 − 19.5 min − 5 min = 8:35:30 → 8:35
        #expect(out[0].leaveByIsEstimate == true)
        #expect(out[1].leaveBy == date(2026, 10, 1, 9, 45)) // no ETA: keeps the fixed time
        #expect(out[1].leaveByIsEstimate == nil)
        #expect(out[2].leaveByIsEstimate == nil) // not an Auto course
    }

    @Test func relevanceRisesAnHourBeforeClass() {
        let bio = slot("BIO 201", date(2026, 10, 1, 9))
        let moments = ScheduleTimeline.moments(classes: [bio], now: date(2026, 10, 1, 7))
        let at8 = try! #require(moments.first { $0.date == date(2026, 10, 1, 8) })
        #expect(ScheduleTimeline.relevanceScore(at8) == 100)
        #expect(ScheduleTimeline.relevanceScore(moments[0]) == 10)
        let during = try! #require(moments.first { $0.date == date(2026, 10, 1, 9) })
        #expect(ScheduleTimeline.relevanceScore(during) == 60)
    }

    @Test func timelineHasLeaveByBoundary() {
        var bio = slot("BIO 201", date(2026, 10, 1, 9))
        bio.leaveBy = date(2026, 10, 1, 8, 40)
        let moments = ScheduleTimeline.moments(classes: [bio], now: date(2026, 10, 1, 8))
        #expect(moments.contains { $0.date == date(2026, 10, 1, 8, 40) })
    }

    @Test func slotWithoutLeaveByDecodesFromOlderSnapshot() throws {
        let data = try JSONEncoder().encode(slot("BIO 201", date(2026, 10, 1, 9)))
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "leaveBy")
        let decoded = try JSONDecoder().decode(ClassSlot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.leaveBy == nil)
    }

    @Test func deadlinesSortedWithDoneState() {
        let late = event("BIO 201 Problem set 4 due", start: date(2026, 10, 5, 9), id: "late")
        let soon = event("Essay", start: date(2026, 10, 2), minutes: 24 * 60, allDay: true, id: "soon")
        let link = CourseEventLink(seriesKey: late.seriesKey, completedOccurrences: ["late"])
        let schedule = ScheduleBuilder.build(events: [late, soon], links: [link], courses: [])
        #expect(schedule.deadlines.map(\.id) == ["soon", "late"])
        #expect(schedule.deadlines[1].isDone)
        #expect(schedule.deadlines[1].title == "Problem set 4")
        #expect(schedule.deadlines[1].code == "BIO 201")
        // All-day: due at the end of the day.
        #expect(schedule.deadlines[0].due == date(2026, 10, 3).addingTimeInterval(-1))
    }

    @Test func snapshotsKeepTodayAndDropPast() throws {
        let cal = calendar("America/Toronto")
        let now = date(2026, 10, 1, 12)
        let classes = [slot("OLD", date(2026, 9, 30, 9)), slot("MORN", date(2026, 10, 1, 9)),
                       slot("AFT", date(2026, 10, 1, 14)), slot("TMRW", date(2026, 10, 2, 9))]
        let today = ScheduleBuilder.todayScheduleSnapshot(classes, now: now, calendar: cal)
        #expect(today.classes.map(\.code) == ["MORN", "AFT", "TMRW"])
        let next = ScheduleBuilder.nextClassSnapshot(classes, now: now, calendar: cal)
        #expect(next.classes.map(\.code) == ["AFT", "TMRW"])
        #expect(next.generatedAt == now)
        #expect(try SnapshotStore.encode(next).count < SnapshotStore.maxSize)
    }

    @Test func snapshotCapsSizeAndSorts() throws {
        let start = date(2026, 10, 1, 8)
        let many = (0..<200).reversed().map { slot("C\($0)", start.addingTimeInterval(Double($0) * 3600)) }
        let snapshot = NextClassSnapshot(classes: many, generatedAt: start)
        #expect(snapshot.classes.count == NextClassSnapshot.maxClasses)
        #expect(snapshot.classes.first?.code == "C0")
        #expect(try SnapshotStore.encode(snapshot).count < SnapshotStore.maxSize)
    }

    @Test func snapshotRoundTripThroughStore() throws {
        let store = SnapshotStore(appGroup: .temporary())
        let snapshot = TodayScheduleSnapshot(classes: [slot("BIO 201", date(2026, 10, 1, 9))], generatedAt: date(2026, 10, 1, 8))
        _ = try store.write(snapshot)
        #expect(store.read(TodayScheduleSnapshot.self) == snapshot)
    }

    @Test func demoScheduleMatchesMockupWeek() {
        let now = date(2026, 9, 24, 8, 46) // Thursday in the mockup
        let schedule = ScheduleBuilder.build(events: DemoSchedule.events(now: now, calendar: calendar("America/Toronto")), links: [], courses: [], now: now)
        let thisWeek = schedule.classes.filter { $0.start < date(2026, 9, 28) }
        #expect(thisWeek.count == 10)
        #expect(Set(schedule.courses.map(\.code)) == ["BIO 201", "ENG 110", "CHEM 150", "PSY 101"])
        #expect(schedule.deadlines.count == 3)
    }
}

extension NextClassSnapshot: Equatable {
    public static func == (a: Self, b: Self) -> Bool { a.classes == b.classes && a.generatedAt == b.generatedAt }
}

extension TodayScheduleSnapshot: Equatable {
    public static func == (a: Self, b: Self) -> Bool { a.classes == b.classes && a.generatedAt == b.generatedAt }
}

// MARK: - Timeline

@Suite("Weekly patterns")
struct WeeklyPatternTests {
    private let toronto = calendar("America/Toronto")

    /// One-off events (no repeat rule), each its own series, like an imported timetable.
    private func oneOff(_ title: String, _ start: Date) -> CalendarEvent {
        event(title, start: start, minutes: 80, series: "\(title)-\(start.timeIntervalSince1970)")
    }

    @Test func sameTimeEveryWeekCountsAsClass() {
        // Mondays 5:30 PM, a week apart: past 4 PM and not set to repeat.
        let events = [oneOff("Calculus", date(2026, 10, 5, 17, 30)), oneOff("Calculus", date(2026, 10, 12, 17, 30))]
        let on = ScheduleBuilder.build(events: events, links: [], courses: [], inferWeeklyPatterns: true, calendar: toronto)
        #expect(on.classes.map(\.code) == ["Calculus", "Calculus"])
        #expect(Set(on.classes.compactMap(\.courseID)).count == 1)
        let off = ScheduleBuilder.build(events: events, links: [], courses: [], inferWeeklyPatterns: false, calendar: toronto)
        #expect(off.classes.isEmpty)
    }

    @Test func needsTheSameWeekdayAndTime() {
        let once = [oneOff("Seminar", date(2026, 10, 5, 19))]
        let moved = [oneOff("Seminar", date(2026, 10, 5, 19)), oneOff("Seminar", date(2026, 10, 12, 20))]
        let otherDay = [oneOff("Seminar", date(2026, 10, 5, 19)), oneOff("Seminar", date(2026, 10, 13, 19))]
        for events in [once, moved, otherDay] {
            #expect(ScheduleBuilder.weeklyPatternIDs(in: events, calendar: toronto).isEmpty)
        }
    }

    @Test func titleMustMatchInTheSameCalendar() {
        var other = oneOff("Calculus", date(2026, 10, 12, 17, 30))
        other.calendarID = "personal"
        let events = [oneOff("Calculus", date(2026, 10, 5, 17, 30)), other]
        #expect(ScheduleBuilder.weeklyPatternIDs(in: events, calendar: toronto).isEmpty)
    }

    @Test func weeklyDeadlinesAndAllDayEventsStayAsTheyAre() {
        let events = [oneOff("Problem set due", date(2026, 10, 5, 23, 59)), oneOff("Problem set due", date(2026, 10, 12, 23, 59)),
                      event("Reading week", start: date(2026, 10, 5), minutes: 1440, allDay: true, series: "a"),
                      event("Reading week", start: date(2026, 10, 12), minutes: 1440, allDay: true, series: "b")]
        let schedule = ScheduleBuilder.build(events: events, links: [], courses: [], inferWeeklyPatterns: true, calendar: toronto)
        #expect(schedule.classes.isEmpty)
        #expect(schedule.deadlines.count == 4)
    }

    @Test func settingDefaultsOnForOlderSettingsFiles() throws {
        let old = try JSONDecoder().decode(StudentSettings.self, from: Data(#"{"schoolCalendarIDs":["cal"]}"#.utf8))
        #expect(old.inferWeeklyPatterns)
        var off = StudentSettings()
        off.inferWeeklyPatterns = false
        let roundTrip = try JSONDecoder().decode(StudentSettings.self, from: JSONEncoder().encode(off))
        #expect(!roundTrip.inferWeeklyPatterns)
    }
}

@Suite("ScheduleTimeline")
struct ScheduleTimelineTests {
    @Test func entriesAtEveryBoundary() {
        let cal = calendar("America/Toronto")
        let now = date(2026, 10, 1, 8)
        let a = slot("A", date(2026, 10, 1, 9))
        let b = slot("B", date(2026, 10, 1, 11), minutes: 90)
        let moments = ScheduleTimeline.moments(classes: [b, a], now: now, calendar: cal)
        let dates = moments.map(\.date)
        #expect(dates.contains(now))
        #expect(dates.contains(a.start) && dates.contains(a.end) && dates.contains(b.start) && dates.contains(b.end))
        #expect(dates.contains(date(2026, 10, 2)))
        #expect(dates == dates.sorted())

        let atA = moments.first { $0.date == a.start }!
        #expect(atA.current == a && atA.next == b && atA.featured == a)
        let afterA = moments.first { $0.date == a.end }!
        #expect(afterA.current == nil && afterA.featured == b)
        let midnight = moments.first { $0.date == date(2026, 10, 2) }!
        #expect(midnight.today.isEmpty)
    }

    @Test func noSnapshotMeansConnectState() {
        let moments = ScheduleTimeline.moments(classes: nil, now: .now)
        #expect(moments.count == 1 && moments[0].hasData == false)
    }

    @Test func reloadDateBounded() {
        let now = date(2026, 10, 1, 8)
        #expect(ScheduleTimeline.reloadDate(classes: [], now: now) == now.addingTimeInterval(6 * 3600))
        let a = slot("A", date(2026, 10, 1, 9))
        #expect(ScheduleTimeline.reloadDate(classes: [a], now: now) == a.end)
        let far = slot("F", date(2026, 10, 9, 9))
        #expect(ScheduleTimeline.reloadDate(classes: [far], now: now) == now.addingTimeInterval(ScheduleTimeline.horizon))
    }

    @Test func dstFallBackMidnightIsCalendarMidnight() {
        // Toronto falls back on 2026-11-01 (a 25-hour day).
        let cal = calendar("America/Toronto")
        let now = date(2026, 11, 1, 0, 30, in: cal)
        let moments = ScheduleTimeline.moments(classes: [], now: now, calendar: cal, horizon: 30 * 3600)
        let midnights = moments.map(\.date).filter { cal.component(.hour, from: $0) == 0 && cal.component(.minute, from: $0) == 0 }
        #expect(midnights.contains(date(2026, 11, 2, in: cal)))
        #expect(date(2026, 11, 2, in: cal).timeIntervalSince(date(2026, 11, 1, in: cal)) == 25 * 3600)
    }

    @Test func todayUsesCalendarTimeZone() {
        // 23:30 in Toronto is already tomorrow in London: "today" must follow the given calendar.
        let toronto = calendar("America/Toronto")
        let london = calendar("Europe/London")
        let late = slot("LATE", date(2026, 10, 1, 23, 30, in: toronto))
        let at = date(2026, 10, 1, 18, in: toronto) // 23:00 in London
        #expect(ScheduleTimeline.moment(at: at, sorted: [late], calendar: toronto).today == [late])
        #expect(ScheduleTimeline.moment(at: at, sorted: [late], calendar: london).today.isEmpty)
    }
}

// MARK: - Reminders

@Suite("Reminders")
struct ReminderTests {
    let now = date(2026, 10, 1, 8)

    @Test func globalRuleOffsetsAndFutureOnly() {
        let a = slot("A", date(2026, 10, 1, 8, 20)) // 15 min fires 8:05, 30 min would be 7:50 (past)
        let rule = ReminderRule(offsets: [.fifteenMinutes, .thirtyMinutes], isEnabled: true)
        let plan = ReminderPlanner.plan(classes: [a], rules: [rule], now: now)
        #expect(plan.map(\.fireDate) == [date(2026, 10, 1, 8, 5)])
        #expect(plan[0].identifier.hasPrefix(ReminderPlanner.identifierPrefix))
        #expect(plan[0].title.contains("A"))
    }

    @Test func courseRuleOverridesGlobal() {
        let bio = UUID(), chem = UUID()
        let classes = [slot("BIO", date(2026, 10, 2, 9), courseID: bio), slot("CHEM", date(2026, 10, 2, 11), courseID: chem)]
        let rules = [ReminderRule(offsets: [.oneHour], isEnabled: true),
                     ReminderRule(courseID: bio, offsets: [.oneDay], isEnabled: true),
                     ReminderRule(courseID: chem, offsets: [.oneHour], isEnabled: false)]
        let plan = ReminderPlanner.plan(classes: classes, rules: rules, now: now)
        #expect(plan.count == 1)
        #expect(plan[0].fireDate == date(2026, 10, 1, 9))
        #expect(plan[0].courseID == bio)
    }

    @Test func disabledGlobalMeansNothing() {
        let plan = ReminderPlanner.plan(classes: [slot("A", date(2026, 10, 2, 9))], rules: [ReminderRule(isEnabled: false)], now: now)
        #expect(plan.isEmpty)
        #expect(ReminderPlanner.plan(classes: [slot("A", date(2026, 10, 2, 9))], rules: [], now: now).isEmpty)
    }

    @Test func rollingWindowKeepsSoonestUnderCap() {
        let classes = (0..<60).map { slot("C\($0)", now.addingTimeInterval(Double($0 + 1) * 7200)) }
        let rule = ReminderRule(offsets: Set(ReminderOffset.allCases), isEnabled: true)
        let plan = ReminderPlanner.plan(classes: classes, rules: [rule], now: now, budget: 500)
        #expect(plan.count == ReminderPlanner.systemLimit)
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted())
        #expect(Set(plan.map(\.identifier)).count == plan.count)
        let defaultPlan = ReminderPlanner.plan(classes: classes, rules: [rule], now: now)
        #expect(defaultPlan.count == ReminderPlanner.defaultBudget)
        #expect(defaultPlan.last!.fireDate <= plan.last!.fireDate)
    }

    @Test func schedulerRespectsOtherSectionsAndReplacesOurs() async {
        let center = FakeCenter(pending: (0..<30).map { "wellness.\($0)" } + ["student.class.stale.15"])
        let classes = (0..<50).map { slot("C\($0)", now.addingTimeInterval(Double($0 + 1) * 3600)) }
        let plan = ReminderPlanner.plan(classes: classes, rules: [ReminderRule(offsets: [.fifteenMinutes], isEnabled: true)], now: now)
        let scheduled = await ReminderScheduler(center: center).reschedule(plan)
        let pending = await center.pendingIdentifiers()
        #expect(scheduled == 34)
        #expect(pending.count == ReminderPlanner.systemLimit)
        #expect(!pending.contains("student.class.stale.15"))
        #expect(pending.filter { $0.hasPrefix("wellness.") }.count == 30)
    }

    @Test func oneDayReminderKeepsWallClockAcrossDST() {
        // Toronto falls back on Sunday 1 Nov 2026: Sat 9:00 → Sun 9:00 is 25 hours.
        let cal = calendar("America/Toronto")
        let classStart = date(2026, 11, 1, 9, in: cal)
        let plan = ReminderPlanner.plan(classes: [slot("A", classStart)], rules: [ReminderRule(offsets: [.oneDay, .oneHour], isEnabled: true)],
                                        now: date(2026, 10, 30, 12, in: cal), calendar: cal)
        #expect(plan.map(\.fireDate) == [date(2026, 10, 31, 9, in: cal), date(2026, 11, 1, 8, in: cal)])
        #expect(classStart.timeIntervalSince(plan[0].fireDate) == 25 * 3600)
    }
}

actor FakeCenter: NotificationScheduling {
    private var pending: [String]
    init(pending: [String]) { self.pending = pending }
    func pendingIdentifiers() -> [String] { pending }
    func removePending(_ identifiers: [String]) { pending.removeAll { identifiers.contains($0) } }
    func add(_ reminder: PlannedReminder) throws {
        guard pending.count < ReminderPlanner.systemLimit else { throw CancellationError() }
        pending.append(reminder.identifier)
    }
}

// MARK: - Repository + week layout

@Suite("Repository")
struct RepositoryTests {
    @Test func fileRepositoryPersists() async throws {
        let group = AppGroupContainer.temporary()
        let repo = FileStudentRepository(appGroup: group)
        let course = Course(code: "BIO 201", paint: .coral)
        try await repo.save(course)
        let rule = ReminderRule(courseID: course.id, offsets: [.oneHour], isEnabled: true)
        try await repo.save(rule)
        try await repo.save(CourseEventLink(seriesKey: "S", userCategory: .deadline))
        await repo.save(StudentSettings(schoolCalendarIDs: ["cal"]))

        let reopened = FileStudentRepository(appGroup: group)
        #expect(await reopened.courses() == [course])
        #expect(await reopened.reminderRules() == [rule])
        #expect(await reopened.links().first?.userCategory == .deadline)
        #expect(await reopened.settings().schoolCalendarIDs == ["cal"])
        try await reopened.deleteRule(id: rule.id)
        #expect(await FileStudentRepository(appGroup: group).reminderRules().isEmpty)
    }

    @Test func persistenceModelPassesCloudKitRules() throws {
        _ = try PersistenceModel.make(contributors: [StudentModel.self])
    }
}

@Suite("WeekGrid")
struct WeekGridTests {
    @Test func weekdayLayoutWithToday() {
        let cal = calendar("America/Toronto")
        let now = date(2026, 9, 24, 8, 46, in: cal) // Thursday
        let classes = DemoSchedule.events(now: now, calendar: cal).filter(\.isWeeklyRecurring).map { slot($0.title, $0.start, minutes: $0.end.timeIntervalSince($0.start) / 60) }
        let layout = WeekGridLayout.make(classes: classes, now: now, calendar: cal)
        #expect(layout.days == [0, 1, 2, 3, 4])
        #expect(layout.todayIndex == 3)
        #expect(layout.firstHour == 8 && layout.lastHour == 16)
        #expect(layout.monday == date(2026, 9, 21, in: cal))
    }

    @Test func weekendLooksAhead() {
        let cal = calendar("America/Toronto")
        let saturday = date(2026, 9, 26, 10, in: cal)
        let layout = WeekGridLayout.make(classes: [slot("A", date(2026, 9, 28, 9, in: cal))], now: saturday, calendar: cal)
        #expect(layout.monday == date(2026, 9, 28, in: cal))
        #expect(layout.todayIndex == nil)
    }
}

@Suite("SyncWindow")
struct SyncWindowTests {
    /// The bug: the window started at yesterday, so on Wednesday Monday's classes were never read
    /// and vanished from the week grid.
    @Test(arguments: [(2026, 9, 21), (2026, 9, 22), (2026, 9, 23), (2026, 9, 24), (2026, 9, 25), (2026, 9, 26), (2026, 9, 27)])
    func coversTheWholeDisplayedWeek(day: (Int, Int, Int)) {
        let cal = calendar("America/Toronto")
        let now = date(day.0, day.1, day.2, 13, in: cal)
        let window = SyncWindow.range(now: now, calendar: cal)
        let layout = WeekGridLayout.make(classes: [], now: now, calendar: cal)
        #expect(window.start <= layout.monday)
        #expect(window.start <= date(2026, 9, 21, in: cal))
        #expect(window.end == date(day.0, day.1, day.2 + 15, in: cal))
    }

    @Test func mondayStillIncludesYesterday() {
        let cal = calendar("America/Toronto")
        let window = SyncWindow.range(now: date(2026, 9, 21, 9, in: cal), calendar: cal)
        #expect(window.start == date(2026, 9, 20, in: cal))
    }

    @Test func wednesdayKeepsMondaysClasses() {
        let cal = calendar("America/Toronto")
        let wednesday = date(2026, 9, 23, 13, in: cal)
        let window = SyncWindow.range(now: wednesday, calendar: cal)
        let monday = event("BIO 201", start: date(2026, 9, 21, 9, in: cal), weekly: true)
        #expect(monday.start >= window.start && monday.start < window.end)
        let built = ScheduleBuilder.build(events: [monday], links: [], courses: [], now: wednesday, calendar: cal)
        let layout = WeekGridLayout.make(classes: built.classes, now: wednesday, calendar: cal)
        #expect(built.classes.count == 1)
        #expect(built.classes[0].start >= layout.monday)
    }
}

@MainActor
private final class PassCounter { var passes = 0 }

@MainActor
@Suite("Refresh coalescing")
struct CoalescingGateTests {
    /// Models the bug: the refresh started when the permission alert closes is mid-flight when
    /// connect() asks for its own. The second request must cause one more pass, not be dropped.
    @Test func callDuringRunTriggersExactlyOneMorePass() async {
        let gate = CoalescingGate()
        let counter = PassCounter()
        async let first: Void = gate.run {
            counter.passes += 1
            try? await Task.sleep(for: .milliseconds(150))
        }
        try? await Task.sleep(for: .milliseconds(30))
        await gate.run { counter.passes += 1 }  // arrives mid-run; returns after the extra pass
        await first
        #expect(counter.passes == 2)
        #expect(gate.isRunning == false)
    }

    @Test func manyCallsDuringOneRunCollapseIntoOnePass() async {
        let gate = CoalescingGate()
        let counter = PassCounter()
        async let first: Void = gate.run {
            counter.passes += 1
            try? await Task.sleep(for: .milliseconds(150))
        }
        try? await Task.sleep(for: .milliseconds(30))
        async let a: Void = gate.run { counter.passes += 1 }
        async let b: Void = gate.run { counter.passes += 1 }
        _ = await (first, a, b)
        #expect(counter.passes == 2)
    }
}
