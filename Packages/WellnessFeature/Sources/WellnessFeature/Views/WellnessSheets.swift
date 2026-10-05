import CoreKit
import DesignSystem
import SwiftUI
import WellnessFeatureWidgetKit

/// Paper sheet: Cancel, a page header, scrolling content and an optional primary action.
struct WellnessSheet<Content: View>: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var isActionEnabled = true
    var action: () -> Void = {}
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Spacer()
                        Button(actionTitle == nil ? String(localized: "Done") : String(localized: "Cancel")) { dismiss() }
                            .wxLabel(color: WXColor.clayLink)
                            .frame(minHeight: 44)
                    }
                    WXPageHeader(title: title, subtitle: subtitle, titleSize: 36)
                    content
                }
                .padding(.horizontal, WXSpace.gutter)
                .padding(.bottom, WXSpace.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            if let actionTitle {
                WXPrimaryButton(actionTitle) {
                    action()
                    dismiss()
                }
                .disabled(!isActionEnabled)
                .opacity(isActionEnabled ? 1 : 0.4)
                .padding(.horizontal, WXSpace.gutter)
                .padding(.bottom, WXSpace.md)
            }
        }
        .background(WXColor.paperIvory.ignoresSafeArea())
    }
}

/// A Label Ivory text field.
struct WellnessField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var axis: Axis = .horizontal

    var body: some View {
        TextField(placeholder, text: $text, axis: axis)
            .keyboardType(keyboard)
            .font(WXFont.body(16))
            .foregroundStyle(WXColor.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .background(WXColor.labelIvory, in: RoundedRectangle(cornerRadius: WXRadius.chip, style: .continuous))
            .wxShadow(.contact, cornerRadius: WXRadius.chip)
    }
}

// MARK: - Habit editor

private enum ScheduleKind: Hashable { case daily, weekdays, perWeek }

struct HabitEditorSheet: View {
    let habit: Habit?
    let store: WellnessStore
    @State private var name: String
    @State private var kind: ScheduleKind
    @State private var days: Set<Int>
    @State private var perWeek: Int
    @Environment(\.dismiss) private var dismiss

    init(habit: Habit?, store: WellnessStore) {
        self.habit = habit
        self.store = store
        _name = State(initialValue: habit?.name ?? "")
        switch habit?.schedule ?? .daily {
        case .daily:
            _kind = State(initialValue: .daily); _days = State(initialValue: [2, 3, 4, 5, 6]); _perWeek = State(initialValue: 3)
        case let .weekdays(set):
            _kind = State(initialValue: .weekdays); _days = State(initialValue: set); _perWeek = State(initialValue: 3)
        case let .timesPerWeek(n):
            _kind = State(initialValue: .perWeek); _days = State(initialValue: [2, 3, 4, 5, 6]); _perWeek = State(initialValue: n)
        }
    }

    private var schedule: HabitSchedule {
        switch kind {
        case .daily: .daily
        case .weekdays: .weekdays(days.isEmpty ? [2, 3, 4, 5, 6] : days)
        case .perWeek: .timesPerWeek(perWeek)
        }
    }

    var body: some View {
        WellnessSheet(title: habit == nil ? String(localized: "New habit") : String(localized: "Edit habit"),
                      actionTitle: String(localized: "Save"),
                      isActionEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                      action: save) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Name").wxLabel()
                WellnessField(placeholder: String(localized: "Read 20 min"), text: $name)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("How often").wxLabel()
                WXSegmentedControl(selection: $kind, options: [(.daily, String(localized: "Daily")),
                                                               (.weekdays, String(localized: "Some days")),
                                                               (.perWeek, String(localized: "x a week"))])
                    .fixedSize(horizontal: false, vertical: true)
                switch kind {
                case .daily:
                    Text("Due every day. Missing a day resets the streak.").wxBody(14)
                case .weekdays:
                    weekdayPicker
                    Text("Days off don't break the streak.").wxBody(14)
                case .perWeek:
                    Stepper(value: $perWeek, in: 1...7) {
                        Text("\(perWeek) times a week").wxGrotesk(17)
                    }
                    Text("Any days you like. The streak counts weeks that hit the target.").wxBody(14)
                }
            }
            if let habit {
                Button(String(localized: "Delete habit"), role: .destructive) {
                    Task { await store.deleteHabit(habit) }
                    dismiss()
                }
                .wxLabel(color: WXColor.clayLink)
                .frame(minHeight: 44)
            }
        }
    }

    private var weekdayPicker: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let first = Calendar.current.firstWeekday
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let weekday = (first - 1 + offset) % 7 + 1
                let isOn = days.contains(weekday)
                Button {
                    if isOn { days.remove(weekday) } else { days.insert(weekday) }
                } label: {
                    Text(symbols[weekday - 1])
                        .wxLabel(11, color: isOn ? WXColor.labelIvory : WXColor.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? WXSection.wellness.color : WXColor.labelIvory,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .wxShadow(.contact, cornerRadius: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func save() {
        Task {
            if var habit {
                habit.name = name
                habit.schedule = schedule
                await store.updateHabit(habit)
            } else {
                await store.addHabit(name: name, schedule: schedule)
            }
        }
    }
}

// MARK: - Mood note

struct MoodNoteSheet: View {
    let store: WellnessStore
    @State private var note: String

    init(store: WellnessStore) {
        self.store = store
        _note = State(initialValue: store.todayMood?.note ?? "")
    }

    var body: some View {
        WellnessSheet(title: String(localized: "Today's note"),
                      subtitle: store.todayMood.map { String(localized: "Logged: \($0.mood.word)") },
                      actionTitle: String(localized: "Save")) {
            Task { await store.setNote(note) }
        } content: {
            WellnessField(placeholder: String(localized: "What made today feel this way?"), text: $note, axis: .vertical)
                .lineLimit(4...10)
            Text("Notes stay private: they sync end-to-end encrypted through your iCloud and never appear in widgets.").wxBody(14)
        }
    }
}

// MARK: - Goals

struct GoalEditorSheet: View {
    let store: WellnessStore
    @State private var title = ""
    @State private var target = ""
    @State private var unit = ""

    private var targetValue: Double? { NumberInput.parse(target) }

    var body: some View {
        WellnessSheet(title: String(localized: "New goal"), actionTitle: String(localized: "Save"),
                      isActionEnabled: !title.trimmingCharacters(in: .whitespaces).isEmpty && (targetValue ?? 0) > 0) {
            guard let value = targetValue else { return }
            Task { await store.addGoal(title: title, target: value, unit: unit) }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Goal").wxLabel()
                WellnessField(placeholder: String(localized: "Walk 20 km"), text: $title)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Target").wxLabel()
                    WellnessField(placeholder: "20", text: $target, keyboard: .decimalPad)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Unit").wxLabel()
                    WellnessField(placeholder: String(localized: "km"), text: $unit)
                }
            }
        }
    }
}

struct GoalProgressSheet: View {
    let goal: Goal
    let store: WellnessStore
    @State private var amount = ""

    private var value: Double? { NumberInput.parse(amount, in: -1_000_000...1_000_000) }

    var body: some View {
        WellnessSheet(title: goal.title,
                      subtitle: String(localized: "\(GoalFormat.number(GoalMath.total(goal))) of \(GoalFormat.number(goal.target)) \(goal.unit) so far"),
                      actionTitle: String(localized: "Log progress"), isActionEnabled: (value ?? 0) != 0) {
            guard let value else { return }
            Task { await store.logProgress(value, to: goal) }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Amount (\(goal.unit))").wxLabel()
                WellnessField(placeholder: "1", text: $amount, keyboard: .decimalPad)
            }
            FillBar(value: GoalMath.fraction(goal), color: WXSection.wellness.color)
                .accessibilityLabel(String(localized: "\(Int(GoalMath.fraction(goal) * 100)) percent"))
            if let eta = GoalMath.eta(goal, now: .now) {
                Text("At your pace over the last two weeks, you'll get there around \(eta.formatted(date: .abbreviated, time: .omitted)).").wxBody(14)
            }
        }
    }
}

// MARK: - Settings

struct WellnessSettingsSheet: View {
    let store: WellnessStore

    var body: some View {
        WellnessSheet(title: String(localized: "Wellness settings")) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Day starts at").wxLabel()
                Stepper(value: Binding(get: { store.settings.dayStartHour },
                                       set: { value in Task { await store.updateSettings { $0.dayStartHour = value } } }),
                        in: 0...12) {
                    Text(hourText(store.settings.dayStartHour)).wxGrotesk(17)
                }
                Text("Up late or on night shifts? Ticks before this hour count for the day before.").wxBody(14)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Mood reminder").wxLabel()
                Toggle(isOn: Binding(get: { store.settings.moodReminderEnabled },
                                     set: { value in Task { await store.updateSettings { $0.moodReminderEnabled = value } } })) {
                    Text("Remind me at \(hourText(store.settings.moodReminderHour))").wxBody(16, color: WXColor.ink)
                }
                .tint(WXColor.mossPositive)
                Text("Skipped on days you've already checked in.").wxBody(14)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Quotes and affirmations").wxLabel()
                FlowLayout(spacing: 6) {
                    categoryChip(nil)
                    ForEach(ContentCategory.allCases) { categoryChip($0) }
                }
                Text("Quotes are public-domain writing, credited to their authors.").wxBody(14)
            }
        }
    }

    private func categoryChip(_ category: ContentCategory?) -> some View {
        let isOn = store.settings.quoteCategory == category
        return Button {
            Task { await store.updateSettings { $0.quoteCategory = category } }
        } label: {
            Text(category?.title ?? String(localized: "All"))
                .wxLabel(11, color: isOn ? WXColor.labelIvory : WXColor.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(isOn ? WXColor.ink : WXColor.labelIvory, in: Capsule())
                .wxShadow(.contact, cornerRadius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func hourText(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
