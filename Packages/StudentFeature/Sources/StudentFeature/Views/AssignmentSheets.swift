import DesignSystem
import StudentFeatureWidgetKit
import SwiftUI

/// Label Ivory input well used by every Student form (same as the course name field).
struct FieldWell: ViewModifier {
    func body(content: Content) -> some View {
        content
            .wxBody(16, color: WXColor.ink)
            .padding(.horizontal, WXSpace.md)
            .frame(minHeight: 48)
            .background(WXColor.labelIvory, in: RoundedRectangle(cornerRadius: WXRadius.chip, style: .continuous))
    }
}

extension View {
    func fieldWell() -> some View { modifier(FieldWell()) }
}

/// Course choice rows: "No course" plus every course.
struct CoursePickerRows: View {
    let courses: [Course]
    @Binding var courseID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WXSectionHeader("Course")
            SelectRow(color: WXColor.inkInactive, title: String(localized: "No course"), meta: "", isOn: courseID == nil) { courseID = nil }
            ForEach(courses.sorted { $0.code < $1.code }) { course in
                SelectRow(color: course.paint.color, title: course.code, meta: course.name ?? "", isOn: courseID == course.id) {
                    courseID = course.id
                }
            }
        }
    }
}

// MARK: - Assignment

/// Add or edit an assignment (S-05).
struct AssignmentSheet: View {
    let isNew: Bool
    let courses: [Course]
    let onSave: (Assignment) -> Void
    let onDelete: (Assignment) -> Void
    @State private var assignment: Assignment
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    init(assignment: Assignment?, courses: [Course], onSave: @escaping (Assignment) -> Void, onDelete: @escaping (Assignment) -> Void) {
        isNew = assignment == nil
        self.courses = courses
        self.onSave = onSave
        self.onDelete = onDelete
        let tomorrow = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: .now.addingTimeInterval(86_400)) ?? .now
        _assignment = State(initialValue: assignment ?? Assignment(title: "", due: tomorrow))
    }

    var body: some View {
        SheetScaffold(title: isNew ? String(localized: "New assignment") : String(localized: "Assignment"),
                      subtitle: assignment.isImported ? String(localized: "From Reminders. Changes here stay in Widgetdeck.") : nil,
                      actionTitle: String(localized: "Save")) {
            onSave(assignment)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                WXSectionHeader("Title")
                TextField(String(localized: "e.g. Lab report"), text: $assignment.title).fieldWell()
            }
            VStack(alignment: .leading, spacing: 8) {
                WXSectionHeader("Due")
                DatePicker(String(localized: "Due"), selection: $assignment.due, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(WXColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !courses.isEmpty { CoursePickerRows(courses: courses, courseID: $assignment.courseID) }
            if !isNew {
                SelectRow(color: WXSection.student.color, title: String(localized: "Done"), meta: "", isOn: assignment.isDone) {
                    assignment.isDone.toggle()
                }
                if assignment.isImported {
                    Text("Imported from Reminders. Delete it there and it goes from here too.")
                        .wxBody(14, color: WXColor.inkSecondary)
                } else {
                Button(String(localized: "Delete assignment")) { confirmDelete = true }
                    .wxLabel(color: WXColor.clayLink)
                    .frame(minHeight: 44)
                    .confirmationDialog(String(localized: "Delete this assignment?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button(String(localized: "Delete"), role: .destructive) {
                            onDelete(assignment)
                            dismiss()
                        }
                    } message: {
                        Text("This can't be undone.")
                    }
                }
            }
        }
    }
}

// MARK: - Due settings

/// Due reminders + the Reminders import list (S-05).
struct DueSettingsSheet: View {
    let lists: [ReminderListSource]
    let onSave: (ReminderOffset?, String?) -> Void
    @State private var offset: ReminderOffset?
    @State private var listID: String?

    init(offset: ReminderOffset?, lists: [ReminderListSource], listID: String?, onSave: @escaping (ReminderOffset?, String?) -> Void) {
        self.lists = lists
        self.onSave = onSave
        _offset = State(initialValue: offset)
        _listID = State(initialValue: listID)
    }

    var body: some View {
        SheetScaffold(title: String(localized: "Assignments"),
                      subtitle: String(localized: "Reminders before things are due, and an optional import from Apple Reminders."),
                      actionTitle: String(localized: "Save")) {
            onSave(offset, listID)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                WXSectionHeader("Remind me before it's due")
                SelectRow(color: WXColor.inkInactive, title: String(localized: "Off"), meta: "", isOn: offset == nil) { offset = nil }
                ForEach([ReminderOffset.oneHour, .oneDay]) { option in
                    SelectRow(color: WXSection.student.color, title: option.title, meta: String(localized: "Before each assignment"),
                              isOn: offset == option) { offset = option }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                WXSectionHeader("Import from Reminders")
                Text("Read-only: Widgetdeck never changes your reminders. Items with a due date are copied in.")
                    .wxBody(14, color: WXColor.inkSecondary)
                SelectRow(color: WXColor.inkInactive, title: String(localized: "Don't import"), meta: "", isOn: listID == nil) { listID = nil }
                ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                    SelectRow(color: CoursePaint.rotating(index).color, title: list.title, meta: list.sourceTitle, isOn: listID == list.id) {
                        listID = list.id
                    }
                }
            }
        }
    }
}

// MARK: - Leave by

/// S-07 settings.
struct LeaveBySheet: View {
    /// The next class with an address, for the live preview (code, start, place).
    var example: (code: String, start: Date, place: String)? = nil
    let onSave: (Bool, TravelMode, Int) -> Void
    @State private var enabled: Bool
    @State private var mode: TravelMode
    @State private var buffer: Int

    init(enabled: Bool, mode: TravelMode, buffer: Int, example: (code: String, start: Date, place: String)? = nil,
         onSave: @escaping (Bool, TravelMode, Int) -> Void) {
        self.example = example
        self.onSave = onSave
        _enabled = State(initialValue: enabled)
        _mode = State(initialValue: mode)
        _buffer = State(initialValue: buffer)
    }

    var body: some View {
        SheetScaffold(title: String(localized: "Leave-by alerts"),
                      subtitle: String(localized: "A heads-up when it's time to head to class, from the trip time Apple Maps gives."),
                      actionTitle: String(localized: "Save")) {
            onSave(enabled, mode, buffer)
        } content: {
            WXSegmentedControl(selection: $enabled, options: [(false, String(localized: "Off")), (true, String(localized: "On"))])
            if enabled {
                preview
                SheetSection(title: "Usually I get there by",
                             note: String(localized: "A course can use its own: open it and set Leave by to Auto.")) {
                    WXSegmentedControl(selection: $mode, options: TravelMode.allCases.map { ($0, $0.title) })
                }
                SheetSection(title: "Extra time") {
                    OptionPills(options: [0, 5, 10, 15].map { ($0, $0 == 0 ? String(localized: "None") : String(localized: "+\($0) min")) },
                                columns: 4, isSelected: { $0 == buffer }) { buffer = $0 }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Worked out when Widgetdeck syncs, from where your iPhone is then. It isn't live.")
                    Text("Places Maps can't find, like “Room 3B”, get a plain reminder 15 min before class.")
                }
                .wxBody(14, color: WXColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Turn on to get a notification when it's time to leave for a class with an address.")
                    .wxBody(14, color: WXColor.inkSecondary)
            }
        }
        .animation(.easeOut(duration: 0.2), value: enabled)
    }

    /// What the notification will say, updated as the options change. Uses the user's next class
    /// when it has an address; otherwise a sample with an illustrative 19-minute trip.
    private var preview: some View {
        let trip = 19
        let start = example?.start ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
        let leave = start.addingTimeInterval(-TimeInterval((trip + buffer) * 60))
        let code = example?.code ?? "BIO 201"
        let place = example?.place ?? String(localized: "Science Hall")
        return VStack(alignment: .leading, spacing: 6) {
            ListRowChip(color: WXSection.student.color,
                        title: String(localized: "Leave by \(ScheduleFormat.time(leave)) for \(code)"),
                        meta: String(localized: "About \(trip) min \(mode.phrase) · \(place)"),
                        metaColor: WXColor.clayLink) { EmptyView() }
            Text("Example with a \(trip)-minute trip. Real times come from Maps.").wxBody(13, color: WXColor.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
