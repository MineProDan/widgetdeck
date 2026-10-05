import CoreKit
import CryptoKit
import Foundation
import Observation
import os
import StudentFeatureWidgetKit

/// The Student section's state and sync pipeline (S-01…S-04).
///
/// Sync = read the rolling window from EventKit → classify → auto-create courses → publish widget
/// snapshots → reschedule reminders. Runs on appear, on `EKEventStoreChanged`, and from the app's
/// `BGAppRefreshTask` via `StudentBackgroundRefresh`.
@MainActor
@Observable
public final class StudentStore {
    public enum Mode: Equatable {
        /// First run: show the primer.
        case needsConnect
        /// Access denied or "Connect later": sample week + "Connect later" card.
        case demo(denied: Bool)
        /// Access granted but no school calendars chosen yet.
        case needsCalendars
        case live
    }

    public private(set) var mode: Mode = .needsConnect
    public private(set) var schedule: StudentSchedule = .empty
    public private(set) var calendars: [CalendarSource] = []
    public internal(set) var settings = StudentSettings()
    public private(set) var reminderRules: [ReminderRule] = []
    public var isSyncing: Bool { refreshGate.isRunning }
    @ObservationIgnored private let refreshGate = CoalescingGate()
    public internal(set) var errorMessage: String?
    /// Links, for the correction sheet.
    public private(set) var links: [CourseEventLink] = []
    /// The user's real courses (never the sample week's), for assignments and grades.
    public private(set) var courses: [Course] = []
    public private(set) var assignments: [Assignment] = []
    public internal(set) var gradeCategories: [GradeCategory] = []
    public internal(set) var gradeEntries: [GradeEntry] = []
    /// Reminders lists, filled after Reminders access is granted (S-05 import picker).
    public internal(set) var reminderLists: [ReminderListSource] = []

    public let permissions: PermissionManager
    /// Set by `showFocus()` (the app calls it for `FocusDeepLink` URLs); the view switches to the Focus tab.
    public var focusTabRequest = false
    /// The focus timer (S-08). Lives as long as the store, so it outlives tab switches.
    public let focus: FocusTimer
    @ObservationIgnored fileprivate let repository: any StudentRepository
    @ObservationIgnored private let provider: any CalendarProviding
    @ObservationIgnored private let reminders: ReminderScheduler
    @ObservationIgnored private let reloadCoordinator: WidgetReloadCoordinator
    @ObservationIgnored fileprivate let remindersProvider: any RemindersProviding
    @ObservationIgnored private let travel: any TravelTimeEstimating
    /// ETAs from recent syncs: (seconds or nil, when looked up), keyed by "mode|location".
    @ObservationIgnored fileprivate var etaCache: [String: (eta: TimeInterval?, at: Date)] = [:]
    @ObservationIgnored private let etaMemory = ETAMemory()
    @ObservationIgnored fileprivate let now: @Sendable () -> Date
    @ObservationIgnored private static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Student")

    public init(repository: any StudentRepository = FileStudentRepository(),
                provider: any CalendarProviding = EventKitCalendarProvider(),
                permissions: PermissionManager = PermissionManager(),
                reminders: ReminderScheduler = ReminderScheduler(),
                reloadCoordinator: WidgetReloadCoordinator = StudentStore.sharedReloadCoordinator,
                remindersProvider: any RemindersProviding = EventKitRemindersProvider(),
                travel: any TravelTimeEstimating = MapKitTravelTimeEstimator(),
                focus: FocusTimer? = nil,
                now: @escaping @Sendable () -> Date = { .now }) {
        self.focus = focus ?? FocusTimer()
        self.remindersProvider = remindersProvider
        self.travel = travel
        self.repository = repository
        self.provider = provider
        self.permissions = permissions
        self.reminders = reminders
        self.reloadCoordinator = reloadCoordinator
        self.now = now
    }

    /// One coordinator for the section so debouncing works across screens.
    public static let sharedReloadCoordinator = WidgetReloadCoordinator()

    public var globalRule: ReminderRule {
        reminderRules.first { $0.courseID == nil } ?? ReminderRule()
    }

    public func rule(for courseID: UUID) -> ReminderRule? {
        reminderRules.first { $0.courseID == courseID }
    }

    // MARK: Sync

    public func refresh() async {
        // A refresh requested mid-sync isn't dropped: it runs once more when the current one ends.
        // (The calendar permission alert makes the scene inactive; the refresh that starts when it
        // closes can read the old status, so the caller's refresh after granting must still run.)
        await refreshGate.run { [weak self] in await self?.refreshOnce() }
    }

    private func refreshOnce() async {
        settings = await repository.settings()
        permissions.refresh()
        await loadStudyData()
        let access = permissions.status(for: .calendar)

        if !access.isUsable {
            mode = access.canRequest && !settings.deferredConnect ? .needsConnect : .demo(denied: access.needsSettings || access == .restricted)
            await buildDemo()
            return
        }
        calendars = await provider.calendars()
        let known = Set(calendars.map(\.id))
        let selected = settings.schoolCalendarIDs.intersection(known)
        guard !selected.isEmpty else {
            mode = .needsCalendars
            await buildDemo()
            return
        }
        mode = .live
        await sync(calendarIDs: selected)
    }

    private func sync(calendarIDs: Set<String>) async {
        let date = now()
        let window = SyncWindow.range(now: date)
        let events = await provider.events(from: window.start, to: window.end, calendarIDs: calendarIDs)
        do {
            let courses = try await repository.courses()
            links = try await repository.links()
            reminderRules = try await repository.reminderRules()
            var built = ScheduleBuilder.build(events: events, links: links, courses: courses, now: date)
            for course in built.newCourses { try await repository.save(course) }
            // Corrections saved before titleKey existed: add it while the series is still recognisable.
            for index in links.indices where links[index].titleKey == nil && links[index].userCategory != nil {
                guard let key = built.titleKeyBySeries[links[index].seriesKey] else { continue }
                links[index].titleKey = key
                try await repository.save(links[index])
            }
            self.courses = built.courses
            built.deadlines = AssignmentPlanner.merged(calendar: built.deadlines,
                                                       assignments: AssignmentPlanner.deadlineItems(assignments, courses: built.courses))
            schedule = built
            errorMessage = nil
        } catch {
            Self.logger.error("Student sync failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "Couldn't load your courses. Your schedule may be incomplete.")
        }
        await publishWidgets(date: date)
        await publishAssignments(schedule.deadlines, date: date)
        await rescheduleReminders()
    }

    private func buildDemo() async {
        let date = now()
        links = []
        reminderRules = (try? await repository.reminderRules()) ?? []
        schedule = ScheduleBuilder.build(events: DemoSchedule.events(now: date), links: [], courses: DemoSchedule.courses, now: date)
        // The user's own assignments are real data, so they show (and remind) even with the sample week.
        let real = AssignmentPlanner.deadlineItems(assignments, courses: courses)
        schedule.deadlines = AssignmentPlanner.merged(calendar: schedule.deadlines, assignments: real)
        // Demo data never reaches widgets or notifications: clear anything from an earlier live sync.
        SnapshotStore().delete(NextClassSnapshot.self)
        SnapshotStore().delete(TodayScheduleSnapshot.self)
        await WidgetReloadCoordinator.widgetCenterReloader([WidgetKind.nextClass.kindIdentifier, WidgetKind.todaySchedule.kindIdentifier])
        await publishAssignments(real, date: date)
        await reminders.reschedule(await assignmentReminderPlan())
    }

    /// Courses, assignments (+ Reminders import) and grades. Works in every mode.
    private func loadStudyData() async {
        do {
            courses = try await repository.courses()
            assignments = try await repository.assignments()
            gradeCategories = try await repository.gradeCategories()
            gradeEntries = try await repository.gradeEntries()
        } catch {
            Self.logger.error("Student study data load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "Couldn't load your assignments and grades.")
        }
        await importReminders()
    }

    /// S-05: read-only import from the chosen Reminders list.
    private func importReminders() async {
        guard let listID = settings.remindersListID, permissions.status(for: .reminders).isUsable else { return }
        let items = await remindersProvider.reminders(inList: listID)
        let result = ReminderImporter.merge(items, listID: listID, into: assignments, courses: courses, now: now())
        guard !result.changed.isEmpty || !result.removed.isEmpty else { return }
        do {
            for assignment in result.changed {
                try await repository.save(assignment)
                assignments.upsert(assignment)
            }
            for id in result.removed {
                try await repository.deleteAssignment(id: id)
                assignments.removeAll { $0.id == id }
            }
        } catch {
            errorMessage = String(localized: "Couldn't import from Reminders. Try again later.")
        }
    }

    private func publishAssignments(_ deadlines: [DeadlineItem], date: Date) async {
        do {
            _ = try await reloadCoordinator.publish(AssignmentPlanner.widgetSnapshot(deadlines, now: date))
        } catch {
            Self.logger.error("Assignments snapshot publish failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func assignmentReminderPlan() async -> [PlannedReminder] {
        let plan = AssignmentPlanner.reminders(assignments, courses: courses, offset: settings.assignmentReminder, now: now())
        guard !plan.isEmpty else { return [] }
        return await permissions.request(.notifications).isUsable ? plan : []
    }

    private func publishWidgets(date: Date) async {
        do {
            let auto = Set(courses.filter { $0.leaveAuto == true }.map(\.id))
            var classes = schedule.classes
            if !auto.isEmpty {
                // One pass per travel mode: courses can be walked to, driven to or reached by transit.
                for (mode, ids) in groupedByMode(auto) {
                    let etas = await travelETAs(for: classes.filter { $0.courseID.map(ids.contains) ?? false }, now: date,
                                                mode: mode, lookahead: LeaveByPlanner.widgetLookahead)
                    classes = LeaveByPlanner.applyAuto(to: classes, autoCourseIDs: ids, etas: etas, bufferMinutes: settings.leaveBufferMinutes)
                }
            }
            _ = try await reloadCoordinator.publish(ScheduleBuilder.nextClassSnapshot(classes, now: date))
            _ = try await reloadCoordinator.publish(ScheduleBuilder.todayScheduleSnapshot(classes, now: date))
        } catch {
            Self.logger.error("Student snapshot publish failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rescheduleReminders() async {
        let date = now()
        let classPlan = ReminderPlanner.plan(classes: schedule.classes, rules: reminderRules, now: date)
        let duePlan = AssignmentPlanner.reminders(assignments, courses: courses, offset: settings.assignmentReminder, now: date)
        let leavePlan = await leaveByPlan(classPlan: classPlan, now: date)
        let plan = ReminderPlanner.combine(classPlan, duePlan, leavePlan)
        // A non-empty plan means the user turned reminders on (which already asked), so this
        // only reads the current status; it never prompts out of the blue.
        let allowed = plan.isEmpty ? false : await permissions.request(.notifications).isUsable
        await reminders.reschedule(allowed ? plan : [])
    }

    /// S-07: one ETA per upcoming place, only when the feature is on and location is allowed.
    private func leaveByPlan(classPlan: [PlannedReminder], now date: Date) async -> [PlannedReminder] {
        guard settings.leaveByEnabled else { return [] }
        let reminded = Set(classPlan.compactMap { reminder in
            schedule.classes.first { reminder.identifier.hasPrefix("\(ReminderPlanner.identifierPrefix)\($0.id).") }?.id
        })
        var plan: [PlannedReminder] = []
        for mode in TravelMode.allCases {
            let classes = schedule.classes.filter { slot in
                travelMode(forCourse: slot.courseID) == mode
                    && slot.courseID.flatMap { id in courses.first { $0.id == id }?.leaveAlerts } != false
            }
            guard !classes.isEmpty else { continue }
            let etas = await travelETAs(for: classes, now: date, mode: mode)
            plan += LeaveByPlanner.plan(classes: classes, etas: etas, bufferMinutes: settings.leaveBufferMinutes,
                                        mode: mode, remindedClassIDs: reminded, now: date)
        }
        return plan
    }

    // MARK: Class setup (first-run questions per course)

    /// One course in the setup flow, with what was pulled from the calendar.
    public struct SetupItem: Identifiable, Sendable, Equatable {
        public var course: Course
        /// "Mon · Wed · Fri"
        public var days: String
        /// Start time of the next class ("12:30 PM").
        public var time: String
        public var start: Date
        /// Shortened calendar location, if any.
        public var place: String?
        public var hasAddress: Bool
        public var roomSuggestion: String?
        public var id: UUID { course.id }
    }

    /// The setup answers for one course.
    public struct SetupAnswer: Sendable, Equatable {
        public enum HeadsUp: Sendable, Equatable { case leave, before15, none }
        public var room: String
        /// `nil` = no travel (online, or already there).
        public var travel: TravelMode?
        public var headsUp: HeadsUp
        public init(room: String = "", travel: TravelMode? = .walking, headsUp: HeadsUp = .leave) {
            self.room = room
            self.travel = travel
            self.headsUp = headsUp
        }
    }

    /// Courses with classes this fortnight that haven't been through setup, in first-class order.
    public var pendingSetup: [SetupItem] {
        guard mode == .live else { return [] }
        var seen: Set<UUID> = []
        var items: [SetupItem] = []
        for slot in schedule.classes.sorted(by: { $0.start < $1.start }) {
            guard let id = slot.courseID, !seen.contains(id),
                  let course = courses.first(where: { $0.id == id }), course.isSetUp != true else { continue }
            seen.insert(id)
            let weekdays = Set(schedule.classes.filter { $0.courseID == id }.map { Calendar.current.component(.weekday, from: $0.start) })
            let symbols = Calendar.current.shortWeekdaySymbols
            let ordered = (1...7).map { ($0 + Calendar.current.firstWeekday - 2) % 7 + 1 }
            let days = ordered.filter(weekdays.contains).map { symbols[$0 - 1] }.joined(separator: " · ")
            let upcoming = schedule.classes.first { $0.courseID == id && $0.start > now() } ?? slot
            items.append(SetupItem(course: course, days: days, time: ScheduleFormat.time(upcoming.start), start: upcoming.start,
                                   place: upcoming.location.flatMap(LocationFormat.short), hasAddress: upcoming.location?.nilIfBlank != nil,
                                   roomSuggestion: schedule.roomSuggestions[id]))
        }
        return items
    }

    /// Saves one course's answers: room, travel mode, Auto leave-by or a 15-minute reminder.
    public func applySetup(_ answer: SetupAnswer, to course: Course) async {
        var course = courses.first { $0.id == course.id } ?? course
        course.room = answer.room.nilIfBlank
        course.travelMode = answer.travel
        course.isSetUp = true
        switch answer.headsUp {
        case .leave where answer.travel != nil:
            course.leaveAuto = true
            course.leaveAlerts = nil
            course.leaveMinutesBefore = nil
        default:
            course.leaveAuto = nil
            course.leaveAlerts = false
        }
        course.updatedAt = now()
        do { try await repository.save(course) } catch { errorMessage = String(localized: "Couldn't save the course.") }

        var rule = rule(for: course.id) ?? ReminderRule(courseID: course.id)
        rule.offsets = answer.headsUp == .before15 ? [.fifteenMinutes] : []
        rule.isEnabled = answer.headsUp == .before15
        rule.updatedAt = now()
        do { try await repository.save(rule) } catch { errorMessage = String(localized: "Couldn't save reminders.") }
    }

    /// After the questions: turn on leave-by alerts if any course asked for them (asks for
    /// location and notifications once), then rebuild widgets and notifications.
    public func finishSetup(answers: [SetupAnswer]) async {
        if answers.contains(where: { $0.headsUp == .leave && $0.travel != nil }), !settings.leaveByEnabled {
            await setLeaveBy(enabled: true, mode: settings.travelMode, bufferMinutes: settings.leaveBufferMinutes)
        } else if answers.contains(where: { $0.headsUp == .before15 }) {
            _ = await permissions.request(.notifications)
            await refresh()
        } else {
            await refresh()
        }
    }

    /// "Skip": mark every pending course as set up with its current settings.
    public func skipSetup() async {
        for item in pendingSetup {
            var course = item.course
            course.isSetUp = true
            course.updatedAt = now()
            try? await repository.save(course)
        }
        await refresh()
    }

    /// "Set up my classes again": ask the questions for every current course.
    public func restartClassSetup() async {
        // From storage, not memory: Settings can be opened before the Student tab has synced.
        let stored = (try? await repository.courses()) ?? courses
        for var course in stored where course.isSetUp == true {
            course.isSetUp = nil
            course.updatedAt = now()
            try? await repository.save(course)
        }
        await refresh()
    }

    /// "Redo calendar setup": forget the chosen school calendars so the Student tab asks again.
    public func restartCalendarSetup() async {
        settings.schoolCalendarIDs = []
        settings.deferredConnect = false
        await repository.save(settings)
        await restartClassSetup()
    }

    /// The course's own travel mode, else the usual one from Leave-by alerts.
    func travelMode(forCourse id: UUID?) -> TravelMode {
        id.flatMap { id in courses.first { $0.id == id }?.travelMode } ?? settings.travelMode
    }

    private func groupedByMode(_ courseIDs: Set<UUID>) -> [(TravelMode, Set<UUID>)] {
        Dictionary(grouping: courseIDs) { travelMode(forCourse: $0) }.map { ($0.key, Set($0.value)) }
    }

    /// ETAs for the soonest places among `classes` (cached 20 min, remembered 12 h). Empty when
    /// location isn't allowed. Shared by leave-by alerts and the Auto widget leave time.
    private func travelETAs(for classes: [ClassSlot], now date: Date, mode: TravelMode,
                            lookahead: TimeInterval = LeaveByPlanner.lookahead) async -> [String: TimeInterval] {
        var etas: [String: TimeInterval] = [:]
        if permissions.status(for: .locationWhenInUse).isUsable {
            for location in LeaveByPlanner.locationsToLookUp(classes, now: date, lookahead: lookahead) {
                let key = "\(mode.rawValue)|\(location)"
                // Reuse an ETA from the last 20 minutes instead of asking MapKit on every sync.
                if let cached = etaCache[key], date.timeIntervalSince(cached.at) < 20 * 60 {
                    if let eta = cached.eta { etas[location] = eta }
                    continue
                }
                var eta = await travel.travelTime(to: location, mode: mode)
                if let eta {
                    etaMemory.remember(key: key, eta: eta, at: date)
                } else {
                    // No fix right now (e.g. a background refresh has no location): reuse the
                    // last ETA from the past 12 hours rather than dropping a good leave-by alert.
                    eta = etaMemory.recall(key: key, now: date, maxAge: 12 * 3600)
                }
                etaCache[key] = (eta, date)
                if let eta { etas[location] = eta }
            }
        }
        return etas
    }

    /// Push pending widget reloads now (call when the scene goes to the background).
    public func flushWidgets() async {
        await reloadCoordinator.flushNow()
    }

    // MARK: Permission + calendars

    public func connect() async {
        let status = await permissions.request(.calendar)
        if !status.isUsable {
            settings.deferredConnect = true
            await repository.save(settings)
        }
        await refresh()
    }

    public func connectLater() async {
        settings.deferredConnect = true
        await repository.save(settings)
        await refresh()
    }

    public func setSchoolCalendars(_ ids: Set<String>) async {
        settings.schoolCalendarIDs = ids
        await repository.save(settings)
        await refresh()
    }

    // MARK: Corrections

    public func link(forSeries seriesKey: String) -> CourseEventLink? {
        links.first { $0.seriesKey == seriesKey }
    }

    /// Applies a correction to the whole recurring series.
    public func correct(seriesKey: String, category: EventCategory?, courseID: UUID?) async {
        guard mode == .live else { return }
        var link = link(forSeries: seriesKey) ?? CourseEventLink(seriesKey: seriesKey)
        link.userCategory = category
        link.courseID = courseID
        link.titleKey = schedule.titleKeyBySeries[seriesKey]
        link.updatedAt = now()
        await persist(link)
    }

    public func toggleDone(_ deadline: DeadlineItem) async {
        if let id = deadline.assignmentID, var assignment = assignments.first(where: { $0.id == id }) {
            assignment.isDone.toggle()
            await save(assignment)
            return
        }
        guard mode == .live else { return }
        var link = link(forSeries: deadline.seriesKey) ?? CourseEventLink(seriesKey: deadline.seriesKey)
        if link.completedOccurrences.contains(deadline.id) {
            link.completedOccurrences.remove(deadline.id)
        } else {
            link.completedOccurrences.insert(deadline.id)
        }
        link.updatedAt = now()
        await persist(link)
    }

    private func persist(_ link: CourseEventLink) async {
        do {
            try await repository.save(link)
        } catch {
            errorMessage = String(localized: "Couldn't save that change. Try again.")
        }
        await refresh()
    }

    // MARK: Courses + reminders

    public func rename(_ course: Course, name: String) async {
        var course = course
        course.name = name.nilIfBlank
        course.updatedAt = now()
        do { try await repository.save(course) } catch { errorMessage = String(localized: "Couldn't save the course.") }
        await refresh()
    }

    /// Saves the course sheet's name and "leave by" choice in one write. Choosing Auto asks for
    /// location (when in use); if it's refused, Auto stays off.
    public func update(_ course: Course, name: String, room: String? = nil, travelMode: TravelMode? = nil,
                       leaveMinutesBefore: Int?, leaveAuto: Bool = false) async {
        var course = course
        course.travelMode = travelMode
        course.name = name.nilIfBlank
        course.room = room?.nilIfBlank
        course.leaveMinutesBefore = leaveMinutesBefore.flatMap { $0 > 0 ? $0 : nil }
        var auto = leaveAuto
        if auto, course.leaveAuto != true, await permissions.request(.locationWhenInUse).isUsable == false {
            errorMessage = String(localized: "Location is off for Widgetdeck, so it can't work out travel times. Turn on “While Using the App” in Settings.")
            auto = false
        }
        course.leaveAuto = auto ? true : nil
        course.updatedAt = now()
        do { try await repository.save(course) } catch { errorMessage = String(localized: "Couldn't save the course.") }
        await refresh()
    }

    /// Saves a reminder rule; turning reminders on asks for notification permission first.
    public func save(_ rule: ReminderRule) async {
        var rule = rule
        rule.updatedAt = now()
        if rule.isEnabled, await permissions.request(.notifications).isUsable == false {
            errorMessage = String(localized: "Notifications are off for Widgetdeck. Turn them on in Settings to get class reminders.")
        }
        do { try await repository.save(rule) } catch { errorMessage = String(localized: "Couldn't save reminders.") }
        await refresh()
    }

    /// Makes a course follow the global reminder rule again.
    public func useDefaultReminders(for courseID: UUID) async {
        guard let rule = rule(for: courseID) else { return }
        do { try await repository.deleteRule(id: rule.id) } catch { errorMessage = String(localized: "Couldn't save reminders.") }
        await refresh()
    }
}

// MARK: - S-05 / S-06 / S-07 actions

extension StudentStore {
    // MARK: Assignments

    public func save(_ assignment: Assignment) async {
        var assignment = assignment
        assignment.title = assignment.title.nilIfBlank ?? String(localized: "Assignment")
        assignment.updatedAt = now()
        do { try await repository.save(assignment) } catch { errorMessage = String(localized: "Couldn't save the assignment.") }
        await refresh()
    }

    public func delete(_ assignment: Assignment) async {
        do { try await repository.deleteAssignment(id: assignment.id) } catch { errorMessage = String(localized: "Couldn't delete the assignment.") }
        await refresh()
    }

    public func assignment(id: UUID?) -> Assignment? {
        id.flatMap { id in assignments.first { $0.id == id } }
    }

    /// Asks for Reminders access (after the primer) and loads the lists to pick from.
    /// - Returns: whether access is usable.
    @discardableResult
    public func connectReminders() async -> Bool {
        let status = await permissions.request(.reminders)
        guard status.isUsable else {
            errorMessage = String(localized: "Reminders access is off. Turn it on in Settings to import assignments.")
            return false
        }
        reminderLists = await remindersProvider.lists()
        return true
    }

    /// Picks the Reminders list to import (`nil` stops importing; already imported items stay).
    public func setRemindersList(_ id: String?) async {
        settings.remindersListID = id
        await repository.save(settings)
        await refresh()
    }

    /// Due-date reminders for assignments (`nil` = off). Turning them on asks for notifications.
    public func setAssignmentReminder(_ offset: ReminderOffset?) async {
        if offset != nil, await permissions.request(.notifications).isUsable == false {
            errorMessage = String(localized: "Notifications are off for Widgetdeck. Turn them on in Settings to get due reminders.")
        }
        settings.assignmentReminder = offset
        await repository.save(settings)
        await refresh()
    }

    // MARK: Leave by

    /// Turns "Leave by" alerts on or off. Turning on asks for location (when in use) and
    /// notifications; if location is refused the feature stays off.
    public func setLeaveBy(enabled: Bool, mode: TravelMode, bufferMinutes: Int) async {
        settings.travelMode = mode
        settings.leaveBufferMinutes = min(max(bufferMinutes, 0), 30)
        if enabled {
            let location = await permissions.request(.locationWhenInUse)
            if !location.isUsable {
                errorMessage = String(localized: "Location is off for Widgetdeck, so it can't work out travel times. Turn on “While Using the App” in Settings.")
                settings.leaveByEnabled = false
            } else {
                settings.leaveByEnabled = true
                if await permissions.request(.notifications).isUsable == false {
                    errorMessage = String(localized: "Notifications are off for Widgetdeck. Turn them on in Settings to get leave-by alerts.")
                }
            }
        } else {
            settings.leaveByEnabled = false
        }
        etaCache.removeAll()
        await repository.save(settings)
        await refresh()
    }

    /// Opens the Focus tab (from the Live Activity / Dynamic Island deep link).
    public func showFocus() {
        focusTabRequest = true
    }

    public func setFocusPreset(_ preset: FocusPreset) async {
        guard settings.focusPreset != preset else { return }
        settings.focusPreset = preset
        await repository.save(settings)
    }

    // MARK: Grades

    public func setGradeScale(_ scale: GradeScale) async {
        settings.gradeScale = scale
        await repository.save(settings)
    }

    public func setCredits(_ credits: Double?, for course: Course) async {
        var course = course
        course.credits = credits.flatMap { $0 > 0 ? $0 : nil }
        course.updatedAt = now()
        do { try await repository.save(course) } catch { errorMessage = String(localized: "Couldn't save the course.") }
        await refresh()
    }

    public func save(_ category: GradeCategory) async {
        var category = category
        category.weight = min(max(category.weight, 0), 100)
        category.updatedAt = now()
        do { try await repository.save(category) } catch { errorMessage = String(localized: "Couldn't save the category.") }
        await reloadGrades()
    }

    /// Deletes a category; its entries become uncategorised (they're kept).
    public func delete(_ category: GradeCategory) async {
        do {
            for var entry in gradeEntries where entry.categoryID == category.id {
                entry.categoryID = nil
                entry.updatedAt = now()
                try await repository.save(entry)
            }
            try await repository.deleteGradeCategory(id: category.id)
        } catch {
            errorMessage = String(localized: "Couldn't delete the category.")
        }
        await reloadGrades()
    }

    public func save(_ entry: GradeEntry) async {
        var entry = entry
        entry.updatedAt = now()
        do { try await repository.save(entry) } catch { errorMessage = String(localized: "Couldn't save the grade.") }
        await reloadGrades()
    }

    public func delete(_ entry: GradeEntry) async {
        do { try await repository.deleteGradeEntry(id: entry.id) } catch { errorMessage = String(localized: "Couldn't delete the grade.") }
        await reloadGrades()
    }

    /// Grades don't affect the schedule, widgets or reminders: reload just them.
    private func reloadGrades() async {
        do {
            gradeCategories = try await repository.gradeCategories()
            gradeEntries = try await repository.gradeEntries()
        } catch {
            errorMessage = String(localized: "Couldn't load your grades.")
        }
    }

    public func categories(for courseID: UUID) -> [GradeCategory] {
        gradeCategories.filter { $0.courseID == courseID }.sorted { ($0.weight, $0.name) > ($1.weight, $1.name) }
    }

    public func entries(for courseID: UUID) -> [GradeEntry] {
        gradeEntries.filter { $0.courseID == courseID }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func percent(for courseID: UUID) -> Double? {
        GradeMath.coursePercent(entries: entries(for: courseID), categories: categories(for: courseID))
    }

    /// Credit-weighted GPA over courses with grades.
    public var gpa: Double? {
        GradeMath.gpa(courses.compactMap { course in percent(for: course.id).map { ($0, course.credits ?? 1) } }, scale: settings.gradeScale)
    }
}

/// Entry point for the app's `BGAppRefreshTask` (opportunistic; no polling). Re-reads the window,
/// republishes snapshots, reschedules reminders.
public enum StudentBackgroundRefresh {
    @MainActor
    public static func run(repository: any StudentRepository = FileStudentRepository()) async {
        let store = StudentStore(repository: repository)
        await store.refresh()
        await store.flushWidgets()
    }
}

/// Runs one job at a time. A call that arrives while a job is running isn't dropped: it marks the
/// job dirty, so exactly one more pass runs afterwards, and the caller returns once that's done.
@MainActor
@Observable
final class CoalescingGate {
    private(set) var isRunning = false
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    func run(_ job: @MainActor () async -> Void) async {
        if isRunning {
            dirty = true
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        isRunning = true
        repeat {
            dirty = false
            await job()
        } while dirty
        isRunning = false
        let finished = waiters
        waiters.removeAll()
        finished.forEach { $0.resume() }
    }
}

/// Last known travel times, in the App Group (device-only, erased with the app's data). Lets a
/// background refresh, which has no location, keep a recent leave-by time.
struct ETAMemory: Sendable {
    private struct Item: Codable { var eta: TimeInterval; var at: Date }
    let url: URL

    init(appGroup: AppGroupContainer = .shared) {
        url = appGroup.applicationSupportURL.appending(path: "Student/eta.json")
    }

    private func read() -> [String: Item] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Item].self, from: data)) ?? [:]
    }

    /// Keys are hashed: event locations are calendar data and never stored in clear (S-02).
    static func hashed(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func remember(key: String, eta: TimeInterval, at date: Date) {
        let key = Self.hashed(key)
        var items = read().filter { date.timeIntervalSince($0.value.at) < 7 * 86_400 }
        items[key] = Item(eta: eta, at: date)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    func recall(key: String, now: Date, maxAge: TimeInterval) -> TimeInterval? {
        guard let item = read()[Self.hashed(key)], now.timeIntervalSince(item.at) <= maxAge else { return nil }
        return item.eta
    }
}
