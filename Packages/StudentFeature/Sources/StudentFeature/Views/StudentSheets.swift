import DesignSystem
import StudentFeatureWidgetKit
import SwiftUI

/// Paper sheet with a page header, scrolling content and a primary action.
struct SheetScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    let actionTitle: String
    let action: () -> Void
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Spacer()
                        Button(String(localized: "Cancel")) { dismiss() }
                            .wxLabel(color: WXColor.clayLink)
                            .frame(minHeight: 44)
                    }
                    WXPageHeader(title: title, subtitle: subtitle, titleSize: 36)
                    content
                }
                .padding(.horizontal, WXSpace.gutter)
                .padding(.bottom, WXSpace.gutter)
            }
            WXPrimaryButton(actionTitle) {
                action()
                dismiss()
            }
            .padding(.horizontal, WXSpace.gutter)
            .padding(.bottom, WXSpace.md)
        }
        .background(WXColor.paperIvory.ignoresSafeArea())
    }
}

/// A selectable row: a paint chip with a check ring.
struct SelectRow: View {
    let color: Color
    let title: String
    let meta: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ListRowChip(color: color, title: title, meta: meta) { CheckRing(isOn: isOn) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Calendars

/// S-01: the user picks which calendars count as "school". Only those are ever read.
struct CalendarPickerSheet: View {
    let calendars: [CalendarSource]
    @State var selected: Set<String>
    let onSave: (Set<String>) -> Void

    init(calendars: [CalendarSource], selected: Set<String>, onSave: @escaping (Set<String>) -> Void) {
        self.calendars = calendars
        _selected = State(initialValue: selected)
        self.onSave = onSave
    }

    var body: some View {
        SheetScaffold(title: String(localized: "School calendars"),
                      subtitle: String(localized: "Widgetdeck reads only these, and never changes them."),
                      actionTitle: String(localized: "Save")) {
            onSave(selected)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if calendars.isEmpty {
                    Text("No calendars found on this iPhone. Add your school calendar in the Calendar app first.")
                        .wxBody(15, color: WXColor.inkSecondary)
                }
                ForEach(Array(calendars.enumerated()), id: \.element.id) { index, calendar in
                    SelectRow(color: CoursePaint.rotating(index).color, title: calendar.title, meta: calendar.sourceTitle,
                              isOn: selected.contains(calendar.id)) {
                        if selected.contains(calendar.id) { selected.remove(calendar.id) } else { selected.insert(calendar.id) }
                    }
                }
            }
        }
    }
}

// MARK: - Correction

/// Fixes the classifier for a whole recurring series: category and course.
struct CorrectionSheet: View {
    let slot: ClassSlot
    let courses: [Course]
    let onSave: (EventCategory?, UUID?) -> Void
    @State private var category: EventCategory?
    @State private var courseID: UUID?

    init(slot: ClassSlot, courses: [Course], link: CourseEventLink?, onSave: @escaping (EventCategory?, UUID?) -> Void) {
        self.slot = slot
        self.courses = courses.sorted { $0.code < $1.code }
        self.onSave = onSave
        _category = State(initialValue: link?.userCategory)
        _courseID = State(initialValue: link?.courseID ?? slot.courseID)
    }

    var body: some View {
        SheetScaffold(title: slot.code,
                      subtitle: String(localized: "Changes apply to every event in this series."),
                      actionTitle: String(localized: "Save")) {
            onSave(category, courseID)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                WXSectionHeader("This event is")
                SelectRow(color: WXColor.inkInactive, title: String(localized: "Automatic"), meta: String(localized: "Let Widgetdeck decide"),
                          isOn: category == nil) { category = nil }
                ForEach(EventCategory.allCases) { option in
                    SelectRow(color: WXSection.student.color, title: option.title, meta: meta(for: option),
                              isOn: category == option) { category = option }
                }
            }
            if !courses.isEmpty && category != .other {
                VStack(alignment: .leading, spacing: 8) {
                    WXSectionHeader("Course")
                    ForEach(courses) { course in
                        SelectRow(color: course.paint.color, title: course.code, meta: course.name ?? "",
                                  isOn: courseID == course.id) { courseID = course.id }
                    }
                }
            }
        }
    }

    private func meta(for category: EventCategory) -> String {
        switch category {
        case .classSession: String(localized: "Shows in the week grid and widgets")
        case .deadline: String(localized: "Shows in Due soon")
        case .other: String(localized: "Hidden from Schedule")
        }
    }
}

// MARK: - Compact controls

/// A row of ink pills for picking one or several short values (minutes, offsets). Replaces a
/// stack of full-width rows when the options are just numbers.
struct OptionPills<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    /// Equal-width columns (e.g. 3 → six options sit 3 and 3); `nil` wraps by content.
    var columns: Int? = nil
    let isSelected: (Value) -> Bool
    let onTap: (Value) -> Void

    var body: some View {
        if let columns {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) { pills(fill: true) }
                .sensoryFeedback(.selection, trigger: options.map { isSelected($0.value) })
        } else {
            FlowLayout(spacing: 8) { pills(fill: false) }
                .sensoryFeedback(.selection, trigger: options.map { isSelected($0.value) })
        }
    }

    @ViewBuilder
    private func pills(fill: Bool) -> some View {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = isSelected(option.value)
                Button { onTap(option.value) } label: {
                    Text(option.title)
                        .font(WXFont.body(15, weight: .semibold))
                        .foregroundStyle(selected ? WXColor.labelIvory : WXColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, fill ? 6 : 16)
                        .frame(maxWidth: fill ? .infinity : nil, minHeight: 44)
                        .background(selected ? WXColor.ink : WXColor.labelIvory, in: Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
    }
}

/// One settings group: caps header, then its controls, then an optional plain note.
struct SheetSection<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WXSectionHeader(String(localized: String.LocalizationValue(title)))
            content
            if let note {
                Text(note).wxBody(14, color: WXColor.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Reminders

private struct ReminderOptions: View {
    @Binding var rule: ReminderRule

    var body: some View {
        OptionPills(options: ReminderOffset.allCases.map { ($0, $0.title) }, columns: 4,
                    isSelected: { rule.isEnabled && rule.offsets.contains($0) }) { offset in
            if rule.isEnabled && rule.offsets.contains(offset) {
                rule.offsets.remove(offset)
            } else {
                if !rule.isEnabled { rule.offsets = [] }
                rule.offsets.insert(offset)
                rule.isEnabled = true
            }
            if rule.offsets.isEmpty { rule.isEnabled = false }
        }
    }
}

/// S-04 global reminder settings.
struct ReminderSheet: View {
    /// The next class, for the example notification (code, start, place).
    var example: (code: String, start: Date, place: String?)? = nil
    @State private var rule: ReminderRule
    let onSave: (ReminderRule) -> Void

    init(rule: ReminderRule, example: (code: String, start: Date, place: String?)? = nil, onSave: @escaping (ReminderRule) -> Void) {
        _rule = State(initialValue: rule)
        self.example = example
        self.onSave = onSave
    }

    private var isOn: Bool { rule.isEnabled && !rule.offsets.isEmpty }

    var body: some View {
        SheetScaffold(title: String(localized: "Class reminders"),
                      subtitle: String(localized: "A nudge before each class, on this iPhone."),
                      actionTitle: String(localized: "Save")) {
            onSave(rule)
        } content: {
            WXSegmentedControl(selection: Binding(get: { isOn }, set: { on in
                if on {
                    if rule.offsets.isEmpty { rule.offsets = [.fifteenMinutes] }
                    rule.isEnabled = true
                } else {
                    rule.isEnabled = false
                }
            }), options: [(false, String(localized: "Off")), (true, String(localized: "On"))])
            if isOn {
                preview
                SheetSection(title: "Remind me",
                             note: String(localized: "Pick as many as you like. A course can use its own: open it and set Reminders to Custom.")) {
                    ReminderOptions(rule: $rule)
                }
            } else {
                Text("Turn on to get a notification before each class.").wxBody(14, color: WXColor.inkSecondary)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isOn)
    }

    /// The soonest notification the current choice would send, using the user's next class.
    private var preview: some View {
        let offset = rule.offsets.sorted().first ?? .fifteenMinutes
        let code = example?.code ?? "BIO 201"
        let start = example?.start ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
        let place = example == nil ? String(localized: "Science Hall") : example?.place
        let extra = rule.offsets.count > 1 ? String(localized: " · +\(rule.offsets.count - 1) more") : ""
        return ListRowChip(color: WXSection.student.color,
                           title: String(localized: "\(code) in \(offset.title)"),
                           meta: [ScheduleFormat.time(start), place].compactMap { $0 }.joined(separator: " · ") + extra) { EmptyView() }
            .accessibilityLabel(String(localized: "Example reminder: \(code) in \(offset.title)"))
    }
}

/// Course name, room, "leave by" and per-course reminders. Three short groups, each one control
/// deep: segmented choices reveal only the options that apply.
struct CourseSheet: View {
    enum LeaveChoice: Hashable { case off, auto, fixed }
    enum ReminderChoice: Hashable { case followDefault, custom }

    /// Minutes-before-class choices for "Leave by".
    static let leaveOptions = [10, 15, 20, 30, 45, 60]

    let course: Course
    let fallback: ReminderRule
    let roomSuggestion: String?
    let leaveBuffer: Int
    /// The usual travel mode (Leave-by alerts), used when the course doesn't set its own.
    let usualMode: TravelMode
    /// (name, room, travel mode or `nil` for usual, leave minutes before class or `nil`, auto, rule).
    /// `nil` rule = follow the global reminders.
    let onSave: (String, String, TravelMode?, Int?, Bool, ReminderRule?) -> Void
    @State private var mode: TravelMode
    @State private var name: String
    @State private var room: String
    @State private var leaveChoice: LeaveChoice
    @State private var leaveMinutes: Int
    @State private var reminderChoice: ReminderChoice
    @State private var rule: ReminderRule

    init(course: Course, rule: ReminderRule?, fallback: ReminderRule, roomSuggestion: String? = nil, leaveBuffer: Int = 0,
         usualMode: TravelMode = .walking, onSave: @escaping (String, String, TravelMode?, Int?, Bool, ReminderRule?) -> Void) {
        self.usualMode = usualMode
        _mode = State(initialValue: course.travelMode ?? usualMode)
        self.course = course
        self.fallback = fallback
        self.roomSuggestion = roomSuggestion
        self.leaveBuffer = leaveBuffer
        self.onSave = onSave
        _name = State(initialValue: course.name ?? "")
        _room = State(initialValue: course.room ?? "")
        _leaveChoice = State(initialValue: course.leaveAuto == true ? .auto : (course.leaveMinutesBefore == nil ? .off : .fixed))
        _leaveMinutes = State(initialValue: course.leaveMinutesBefore ?? 15)
        _reminderChoice = State(initialValue: rule == nil ? .followDefault : .custom)
        _rule = State(initialValue: rule ?? ReminderRule(courseID: course.id, offsets: fallback.offsets, isEnabled: fallback.isEnabled))
    }

    var body: some View {
        SheetScaffold(title: course.code, subtitle: nil, actionTitle: String(localized: "Save")) {
            onSave(name, room, mode == usualMode && course.travelMode == nil ? nil : mode,
                   leaveChoice == .fixed ? leaveMinutes : nil,
                   leaveChoice == .auto,
                   reminderChoice == .custom ? rule : nil)
        } content: {
            detailsSection
            leaveSection
            remindersSection
        }
    }

    // MARK: Details

    private var detailsSection: some View {
        SheetSection(title: "Details") {
            VStack(spacing: 0) {
                field(String(localized: "Name"), text: $name, prompt: String(localized: "e.g. Cell Biology"))
                Rectangle().fill(WXColor.rule).frame(height: 1).padding(.leading, WXSpace.md)
                field(String(localized: "Room"), text: $room, prompt: String(localized: "e.g. ICS 192"))
                    .onChange(of: room) { _, new in if new.count > Course.roomMaxLength { room = Course.limitedRoom(new) } }
            }
            .background(WXColor.labelIvory, in: RoundedRectangle(cornerRadius: WXRadius.chip, style: .continuous))
            if let roomSuggestion, room.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { room = roomSuggestion } label: {
                    HStack(spacing: 6) {
                        Text("Use “\(roomSuggestion)”").font(WXFont.body(15, weight: .semibold)).foregroundStyle(WXColor.clayLink)
                        Text("from your calendar notes").wxBody(14, color: WXColor.inkSecondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("The room shows on widgets. Directions still use the calendar address.")
                .wxBody(14, color: WXColor.inkSecondary)
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 12) {
            Text(label).wxLabel(color: WXColor.inkSecondary).frame(width: 52, alignment: .leading)
            TextField(prompt, text: text)
                .wxBody(16, color: WXColor.ink)
                .submitLabel(.done)
        }
        .padding(.horizontal, WXSpace.md)
        .frame(minHeight: 48)
    }

    // MARK: Leave by

    private var leaveSection: some View {
        SheetSection(title: "Leave by", note: leaveNote) {
            WXSegmentedControl(selection: $leaveChoice, options: [(.off, String(localized: "Off")),
                                                                  (.auto, String(localized: "Auto")),
                                                                  (.fixed, String(localized: "Set time"))])
            if leaveChoice == .auto {
                WXSegmentedControl(selection: $mode, options: TravelMode.allCases.map { ($0, $0.title) })
            }
            if leaveChoice == .fixed {
                OptionPills(options: Self.leaveOptions.map { ($0, String(localized: "\($0) min")) }, columns: 3,
                            isSelected: { $0 == leaveMinutes }) { leaveMinutes = $0 }
            }
        }
        .animation(.easeOut(duration: 0.2), value: leaveChoice)
    }

    private var leaveNote: String {
        switch leaveChoice {
        case .off: String(localized: "Nothing extra on the Next Class widget.")
        case .auto: leaveBuffer > 0
            ? String(localized: "\(mode.title) time to the class address, plus \(leaveBuffer) min. Shown as an estimate. Uses your location.")
            : String(localized: "\(mode.title) time to the class address. Shown as an estimate. Uses your location.")
        case .fixed: String(localized: "Shown on the Next Class widget, \(leaveMinutes) min before each class.")
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        SheetSection(title: "Reminders", note: reminderNote) {
            WXSegmentedControl(selection: $reminderChoice, options: [(.followDefault, String(localized: "Default")),
                                                                     (.custom, String(localized: "Custom"))])
            if reminderChoice == .custom { ReminderOptions(rule: $rule) }
        }
        .animation(.easeOut(duration: 0.2), value: reminderChoice)
    }

    private var reminderNote: String {
        let source = reminderChoice == .custom ? rule : fallback
        guard source.isEnabled, !source.offsets.isEmpty else {
            return reminderChoice == .custom ? String(localized: "No reminders for this course.") : String(localized: "Same as Class reminders: off.")
        }
        let times = source.offsets.sorted().map(\.title).joined(separator: ", ")
        return reminderChoice == .custom ? String(localized: "\(times) before each class.") : String(localized: "Same as Class reminders: \(times) before.")
    }
}
