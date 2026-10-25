import CoreKit
import DesignSystem
import EventKit
import StudentFeatureWidgetKit
import SwiftUI

/// Root view of the Student section (Student.png). The app shell draws the "Student" page header
/// and the scroll view; this view supplies everything below it.
public struct StudentSectionView: View {
    @State private var store: StudentStore
    @State private var segment: Segment = .schedule
    @State private var showsAllDue = false
    @State private var sheet: SheetKind?
    @State private var didPrompt = false
    /// A course to open, set by the app from a widget or reminder deep link; cleared once shown.
    @Binding private var requestedCourseID: UUID?
    @State private var showSetup = false
    @State private var setupDismissed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    enum Segment: Hashable { case schedule, due, grades, focus }

    enum SheetKind: Identifiable {
        case primer, calendars, reminders
        case correct(ClassSlot)
        case course(Course)
        case assignment(Assignment?)
        case dueSettings, remindersPrimer, leaveBy, gradeScale
        case courseGrades(Course)

        var id: String {
            switch self {
            case .primer: "primer"
            case .calendars: "calendars"
            case .reminders: "reminders"
            case .correct(let slot): "correct-\(slot.id)"
            case .course(let course): "course-\(course.id)"
            case .assignment(let assignment): "assignment-\(assignment?.id.uuidString ?? "new")"
            case .dueSettings: "dueSettings"
            case .remindersPrimer: "remindersPrimer"
            case .leaveBy: "leaveBy"
            case .gradeScale: "gradeScale"
            case .courseGrades(let course): "grades-\(course.id)"
            }
        }
    }

    public init() {
        _store = State(initialValue: StudentStore())
        _requestedCourseID = .constant(nil)
    }

    /// Injects a store (previews, tests, or an app-provided Core Data repository).
    /// - Parameter requestedCourseID: set by the app from `StudentDeepLink.courseID(from:)`; the
    ///   course sheet opens once the course is known, then the binding is reset to nil.
    public init(store: StudentStore, requestedCourseID: Binding<UUID?> = .constant(nil)) {
        _store = State(initialValue: store)
        _requestedCourseID = requestedCourseID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WXSegmentedControl(selection: $segment, options: [(Segment.schedule, String(localized: "Schedule")), (Segment.due, String(localized: "Due")),
                                                              (Segment.grades, String(localized: "Grades")), (Segment.focus, String(localized: "Focus"))])
                .frame(height: 36)
                .padding(.top, 2)

            switch segment {
            case .schedule: scheduleContent
            case .due: dueContent.padding(.top, 24)
            case .grades:
                GradesContent(store: store, openCourse: { sheet = .courseGrades($0) }, openScale: { sheet = .gradeScale })
                    .padding(.top, 24)
            case .focus: FocusContent(store: store).padding(.top, 24)
            }

            if segment == .schedule || segment == .due {
                statusCard.padding(.top, 24)
                if store.mode == .live { coursesSection.padding(.top, 24) }
            }
            if let message = store.errorMessage {
                Text(message).wxBody(13, color: WXColor.clayLink).padding(.top, 14)
            }
        }
        .task {
            await store.focus.restore()
            await store.refresh()
            if store.mode == .needsConnect && !didPrompt {
                didPrompt = true
                sheet = .primer
            }
            // S-02: re-sync whenever the calendar database changes. Ends with the view.
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                await store.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await store.focus.restore()
                    await store.refresh()
                }
            } else if phase == .background {
                Task { await store.flushWidgets() }
            }
        }
        .sheet(item: $sheet) { kind in sheetContent(kind) }
        .fullScreenCover(isPresented: $showSetup) {
            ClassSetupFlow(store: store) {
                // Only stay dismissed if questions were left (closing mid-way); a finished or
                // skipped flow clears them, so a later restart can open it again.
                setupDismissed = !store.pendingSetup.isEmpty
                showSetup = false
                // iOS drops a sheet presented while the cover is still closing.
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    openRequestedCourse()
                }
            }
        }
        // New classes (first calendar, a newly picked calendar, or "Set up my classes again")
        // open the setup questions once per app session; Skip marks them done.
        .onChange(of: store.pendingSetup.map(\.id)) { _, ids in
            if ids.isEmpty { setupDismissed = false }
            presentSetupIfNeeded()
        }
        .onChange(of: sheet == nil) { _, closed in if closed { presentSetupIfNeeded() } }
        .onAppear { presentSetupIfNeeded() }
        .onChange(of: requestedCourseID, initial: true) { openRequestedCourse() }
        .onChange(of: store.focusTabRequest, initial: true) {
            if store.focusTabRequest {
                segment = .focus
                store.focusTabRequest = false
            }
        }
        .onChange(of: store.schedule.courses.map(\.id)) { openRequestedCourse() }
    }

    /// Opens the class setup questions when courses are waiting for them. Waits a beat so another
    /// sheet (Settings, the calendar picker) can finish closing; iOS drops a cover presented mid-dismiss.
    private func presentSetupIfNeeded() {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if !store.pendingSetup.isEmpty, sheet == nil, !setupDismissed, !showSetup { showSetup = true }
        }
    }

    /// Opens the deep-linked course once it's loaded (links can arrive before the first sync ends).
    private func openRequestedCourse() {
        guard let id = requestedCourseID, store.mode == .live, !showSetup else { return }
        guard let course = store.schedule.courses.first(where: { $0.id == id }) else {
            // A link to a course that no longer exists (merged or deleted): just show the schedule.
            if !store.schedule.courses.isEmpty { requestedCourseID = nil }
            return
        }
        segment = .schedule
        sheet = .course(course)
        requestedCourseID = nil
    }

    // MARK: Schedule

    @ViewBuilder
    private var scheduleContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // The grid is a dense chart; at accessibility sizes the week reads as a list instead.
            classList.padding(.top, 24)
        } else {
            WeekGridView(classes: store.schedule.classes, now: .now) { slot in
                if store.mode == .live { sheet = .correct(slot) }
            }
            .padding(.top, 26)
        }
        VStack(alignment: .leading, spacing: 8) {
            let open = openDeadlines
            WXSectionHeader("Due soon", accessory: open.count > 3 ? String(localized: "All \(open.count)") : nil) {
                segment = .due
            }
            if open.isEmpty {
                Text("Nothing due in the next two weeks.").wxBody(15, color: WXColor.inkSecondary)
            }
            ForEach(open.prefix(3)) { deadlineRow($0) }
        }
        .padding(.top, 18)
    }

    private var classList: some View {
        VStack(alignment: .leading, spacing: 8) {
            WXSectionHeader("This week")
            let upcoming = store.schedule.classes.filter { $0.end > .now }.prefix(12)
            if upcoming.isEmpty {
                Text("No classes this week.").wxBody(15, color: WXColor.inkSecondary)
            }
            ForEach(Array(upcoming)) { slot in
                Button {
                    if store.mode == .live { sheet = .correct(slot) }
                } label: {
                    ListRowChip(color: slot.paint.color, title: slot.code,
                                meta: "\(ScheduleFormat.dayAndTime(slot.start, now: .now))\(slot.shortLocation.map { " · \($0)" } ?? "")") {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Due

    private var openDeadlines: [DeadlineItem] {
        store.schedule.deadlines.filter { !$0.isDone && $0.due > .now }
    }

    private var dueContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            let all = store.schedule.deadlines.filter { $0.due > .now.addingTimeInterval(-24 * 3600) }
            WXSectionHeader("Coming up", accessory: String(localized: "Add")) { sheet = .assignment(nil) }
            if all.isEmpty {
                Text("Nothing due yet. Add an assignment, or events with “due”, “submit”, “exam” or “quiz” in the title show up here.")
                    .wxBody(15, color: WXColor.inkSecondary)
            }
            ForEach(all) { item in
                if let assignment = store.assignment(id: item.assignmentID) {
                    deadlineRow(item) { sheet = .assignment(assignment) }
                } else {
                    deadlineRow(item)
                }
            }
            WXSectionHeader("Settings").padding(.top, 16)
            Button { sheet = .dueSettings } label: {
                ListRowChip(color: WXSection.student.color, title: String(localized: "Due reminders"),
                            meta: store.settings.assignmentReminder.map { String(localized: "\($0.title) before") } ?? String(localized: "Off")) {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
            Button {
                if store.permissions.status(for: .reminders).isUsable {
                    Task {
                        await store.connectReminders()
                        sheet = .dueSettings
                    }
                } else {
                    sheet = .remindersPrimer
                }
            } label: {
                ListRowChip(color: WXSection.student.color, title: String(localized: "Import from Reminders"),
                            meta: store.settings.remindersListID == nil ? String(localized: "Off") : String(localized: "On · read-only")) {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// - Parameter open: when set, tapping the row (outside the tick circle) opens the item. The two
    ///   are sibling buttons: a Button wrapping the whole row swallowed taps on the circle.
    private func deadlineRow(_ item: DeadlineItem, open: (() -> Void)? = nil) -> some View {
        let urgent = item.due.timeIntervalSinceNow < 36 * 3600 && !item.isDone
        let meta = [item.code, ScheduleFormat.dayAndTime(item.due, now: .now)].compactMap { $0 }.joined(separator: " · ")
        return ListRowChip(color: item.paint.color, title: item.title, meta: meta,
                           metaColor: urgent ? WXColor.clayLink : WXColor.inkSecondary, onTap: open) {
            // Sample-week deadlines can't be ticked, so they show no tick circle at all.
            if store.mode == .live || item.assignmentID != nil {
                Button {
                    Task { await store.toggleDone(item) }
                } label: {
                    CheckRing(isOn: item.isDone)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isDone ? "Mark \(item.title) not done" : "Mark \(item.title) done")
            }
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusCard: some View {
        switch store.mode {
        case .live:
            EmptyView()
        case .needsConnect, .demo:
            let denied = store.mode == .demo(denied: true)
            statusChip(caption: String(localized: "Sample week"),
                       value: String(localized: "Your classes go here"),
                       trend: denied ? String(localized: "Calendar access is off") : String(localized: "Read-only · stays on this iPhone"),
                       button: denied ? String(localized: "Settings") : String(localized: "Connect")) {
                if denied {
                    openURL(PermissionManager.settingsURL)
                } else {
                    sheet = .primer
                }
            }
        case .needsCalendars:
            statusChip(caption: String(localized: "Calendar connected"), value: String(localized: "Pick school calendars"),
                       trend: String(localized: "Only these are read"), button: String(localized: "Choose")) {
                sheet = .calendars
            }
        }
    }

    private func statusChip(caption: String, value: String, trend: String, button: String, action: @escaping () -> Void) -> some View {
        PaintChip(axis: .horizontal, color: WXSection.student.color, field: .fixed(68), punchHole: nil,
                  cornerRadius: WXRadius.chip, shadow: .rowChip) {
            ClockGlyph(size: 30, lineWidth: 2)
        } label: {
            HStack(spacing: 10) {
                ChipLabelBand(caption: caption, value: value, trend: trend, valueSize: 18,
                              padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 0), spacing: 4)
                WXPillButton(button, action: action).padding(.trailing, 12)
            }
        }
    }

    // MARK: Courses

    private var coursesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            WXSectionHeader("Courses", accessory: String(localized: "Calendars")) { sheet = .calendars }
            let courses = store.schedule.courses.sorted { $0.code < $1.code }
            if courses.isEmpty {
                Text("No courses found yet. Classes are found from weekly events and codes like “BIO 201”; tap a class to correct it.")
                    .wxBody(15, color: WXColor.inkSecondary)
            }
            ForEach(courses) { course in
                Button { sheet = .course(course) } label: {
                    ListRowChip(color: course.paint.color, title: course.name ?? course.code, meta: courseMeta(course)) { EmptyView() }
                }
                .buttonStyle(.plain)
            }
            Button { sheet = .reminders } label: {
                ListRowChip(color: WXSection.student.color, title: String(localized: "Class reminders"), meta: reminderSummary(store.globalRule)) {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
            Button { sheet = .leaveBy } label: {
                ListRowChip(color: WXSection.student.color, title: String(localized: "Leave-by alerts"),
                            meta: store.settings.leaveByEnabled ? String(localized: "On · \(store.settings.travelMode.title)") : String(localized: "Off")) {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func courseMeta(_ course: Course) -> String {
        let perWeek = store.schedule.classes.filter { $0.courseID == course.id }
        let weekEnd = Date.now.addingTimeInterval(7 * 86_400)
        let count = perWeek.filter { $0.start < weekEnd && $0.end > .now }.count
        let reminder = store.rule(for: course.id).map(reminderSummary) ?? String(localized: "Default reminders")
        return String(localized: "\(course.code) · \(count) this week · \(reminder)")
    }

    private func reminderSummary(_ rule: ReminderRule) -> String {
        guard rule.isEnabled, !rule.offsets.isEmpty else { return String(localized: "Off") }
        return rule.offsets.sorted().map(\.title).joined(separator: ", ") + String(localized: " before")
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ kind: SheetKind) -> some View {
        switch kind {
        case .primer:
            PermissionPrimer(
                title: String(localized: "See your classes at a glance"),
                message: String(localized: "Widgetdeck reads the calendars you choose to find classes and deadlines."),
                systemImage: "calendar",
                bullets: [String(localized: "Read-only: we never change your events"),
                          String(localized: "Events stay on this iPhone, never uploaded"),
                          String(localized: "You pick which calendars count as school")],
                continueTitle: String(localized: "Connect calendar"),
                onContinue: {
                    sheet = nil
                    Task {
                        await store.connect()
                        if store.mode == .needsCalendars { sheet = .calendars }
                    }
                },
                onNotNow: {
                    sheet = nil
                    Task { await store.connectLater() }
                })
            .presentationDetents([.large])
        case .calendars:
            CalendarPickerSheet(calendars: store.calendars, selected: store.settings.schoolCalendarIDs,
                                inferWeekly: store.settings.inferWeeklyPatterns) { ids, inferWeekly in
                Task { await store.setSchoolCalendars(ids, inferWeeklyPatterns: inferWeekly) }
            }
        case .reminders:
            ReminderSheet(rule: store.globalRule,
                          example: store.schedule.classes.first { $0.start > .now }.map { ($0.code, $0.start, $0.shortLocation) }) { rule in
                Task { await store.save(rule) }
            }
        case .correct(let slot):
            CorrectionSheet(slot: slot, courses: store.schedule.courses,
                            link: store.schedule.seriesByOccurrence[slot.id].flatMap(store.link(forSeries:))) { category, courseID in
                guard let series = store.schedule.seriesByOccurrence[slot.id] else { return }
                Task { await store.correct(seriesKey: series, category: category, courseID: courseID) }
            }
        case .assignment(let assignment):
            AssignmentSheet(assignment: assignment, courses: store.courses) { saved in
                Task { await store.save(saved) }
            } onDelete: { deleted in
                Task { await store.delete(deleted) }
            }
        case .dueSettings:
            DueSettingsSheet(offset: store.settings.assignmentReminder, lists: store.reminderLists,
                             listID: store.settings.remindersListID) { offset, listID in
                Task {
                    if offset != store.settings.assignmentReminder { await store.setAssignmentReminder(offset) }
                    if listID != store.settings.remindersListID { await store.setRemindersList(listID) }
                }
            }
        case .remindersPrimer:
            PermissionPrimer(
                title: String(localized: "Bring in your assignments"),
                message: String(localized: "Widgetdeck can copy to-dos with a due date from one Reminders list you choose."),
                systemImage: "checklist",
                bullets: [String(localized: "Read-only: we never change your reminders"),
                          String(localized: "You pick the list"),
                          String(localized: "Turn it off any time")],
                continueTitle: String(localized: "Connect Reminders"),
                onContinue: {
                    sheet = nil
                    Task {
                        if await store.connectReminders() { sheet = .dueSettings }
                    }
                },
                onNotNow: { sheet = nil })
            .presentationDetents([.large])
        case .leaveBy:
            LeaveBySheet(enabled: store.settings.leaveByEnabled, mode: store.settings.travelMode,
                         buffer: store.settings.leaveBufferMinutes,
                         example: store.schedule.classes.first { $0.start > .now && $0.location != nil }
                            .map { ($0.code, $0.start, $0.shortLocation ?? "") }) { enabled, mode, buffer in
                Task { await store.setLeaveBy(enabled: enabled, mode: mode, bufferMinutes: buffer) }
            }
        case .gradeScale:
            GradeScaleSheet(scale: store.settings.gradeScale) { scale in
                Task { await store.setGradeScale(scale) }
            }
        case .courseGrades(let course):
            CourseGradesSheet(store: store, course: course)
        case .course(let course):
            CourseSheet(course: course, rule: store.rule(for: course.id), fallback: store.globalRule,
                        roomSuggestion: store.schedule.roomSuggestions[course.id],
                        leaveBuffer: store.settings.leaveBufferMinutes,
                        usualMode: store.settings.travelMode) { name, room, mode, leave, auto, rule in
                Task {
                    if name != (course.name ?? "") || room != (course.room ?? "") || mode != course.travelMode
                        || leave != course.leaveMinutesBefore || auto != (course.leaveAuto == true) {
                        await store.update(course, name: name, room: room, travelMode: mode, leaveMinutesBefore: leave, leaveAuto: auto)
                    }
                    if let rule {
                        await store.save(rule)
                    } else {
                        await store.useDefaultReminders(for: course.id)
                    }
                }
            }
        }
    }
}

#Preview {
    ScrollView {
        StudentSectionView().padding(.horizontal, WXSpace.gutter)
    }
    .background(WXColor.paperIvory)
}
