import CoreKit
import DesignSystem
import StudentFeatureWidgetKit
import SwiftUI

/// "12.5" / "92.4" without trailing zeros.
func gradeNumber(_ value: Double, digits: Int = 1) -> String {
    value.formatted(.number.precision(.fractionLength(0...digits)))
}

/// Grades tab (S-06): GPA chip, courses with their current percentage and letter.
struct GradesContent: View {
    let store: StudentStore
    let openCourse: (Course) -> Void
    let openScale: () -> Void

    var body: some View {
        let scale = store.settings.gradeScale
        VStack(alignment: .leading, spacing: 8) {
            PaintChip(axis: .horizontal, color: WXSection.student.color, field: .fixed(68), punchHole: .small,
                      cornerRadius: WXRadius.chip, shadow: .rowChip) {
                VStack {
                    Spacer(minLength: 0)
                    FillBar(value: store.gpa.map { $0 / scale.maxPoints }, color: WXColor.labelIvory, height: 8, trackOpacity: 0.3)
                        .frame(height: 8)
                }
                .padding(12)
            } label: {
                HStack(spacing: 10) {
                    ChipLabelBand(caption: String(localized: "GPA · \(scale.title)"),
                                  value: store.gpa.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "—",
                                  trend: gpaTrend, valueSize: 28,
                                  padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 0), spacing: 4)
                    WXPillButton(String(localized: "Scale"), action: openScale).padding(.trailing, 12)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            WXSectionHeader("Courses").padding(.top, 16)
            if store.courses.isEmpty {
                Text("Courses appear here once your calendar is connected and classes are found.")
                    .wxBody(15, color: WXColor.inkSecondary)
            }
            ForEach(store.courses.sorted { $0.code < $1.code }) { course in
                Button { openCourse(course) } label: {
                    ListRowChip(color: course.paint.color, title: course.name ?? course.code, meta: meta(course, scale: scale)) { EmptyView() }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var gpaTrend: String {
        let graded = store.courses.filter { store.percent(for: $0.id) != nil }.count
        if store.courses.isEmpty {
            return store.mode == .needsCalendars ? String(localized: "Pick your school calendars first")
                : store.mode == .live ? String(localized: "No classes found yet") : String(localized: "Connect your calendar first")
        }
        if graded == 0 { return String(localized: "Add grades to a course") }
        return graded == 1 ? String(localized: "1 course graded") : String(localized: "\(graded) courses graded")
    }

    private func meta(_ course: Course, scale: GradeScale) -> String {
        let credits = String(localized: "\(gradeNumber(course.credits ?? 1)) cr")
        guard let percent = store.percent(for: course.id) else { return "\(course.code) · \(String(localized: "No grades yet")) · \(credits)" }
        let letter = GradeMath.grade(for: percent, scale: scale).letter
        return "\(course.code) · \(gradeNumber(percent))% · \(letter) · \(credits)"
    }
}

/// Picks the grade scale.
struct GradeScaleSheet: View {
    let onSave: (GradeScale) -> Void
    @State private var scale: GradeScale

    init(scale: GradeScale, onSave: @escaping (GradeScale) -> Void) {
        self.onSave = onSave
        _scale = State(initialValue: scale)
    }

    var body: some View {
        SheetScaffold(title: String(localized: "Grade scale"), subtitle: String(localized: "How percentages turn into letters and GPA points."),
                      actionTitle: String(localized: "Save")) {
            onSave(scale)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(GradeScale.allCases) { option in
                    SelectRow(color: WXSection.student.color, title: option.title,
                              meta: option.bands.prefix(4).map { "\($0.letter) \(gradeNumber($0.min))" }.joined(separator: " · "),
                              isOn: scale == option) { scale = option }
                }
            }
        }
    }
}

/// One course's grades: credits, weighted categories, graded items and the final-exam predictor.
struct CourseGradesSheet: View {
    let store: StudentStore
    let course: Course
    @Environment(\.dismiss) private var dismiss

    @State private var credits = ""
    @State private var newCategoryName = ""
    @State private var newCategoryWeight = ""
    @State private var newTitle = ""
    @State private var newScore = ""
    @State private var newMax = "100"
    @State private var newCategoryID: UUID?
    @State private var target = "90"
    @State private var finalWeight = "30"

    init(store: StudentStore, course: Course) {
        self.store = store
        self.course = course
        _credits = State(initialValue: course.credits.map { gradeNumber($0) } ?? "")
    }

    private var categories: [GradeCategory] { store.categories(for: course.id) }
    private var entries: [GradeEntry] { store.entries(for: course.id) }

    var body: some View {
        SheetScaffold(title: course.code, subtitle: summary, actionTitle: String(localized: "Done")) {
            let value = NumberInput.parse(credits, in: 0...100)
            if value != course.credits { Task { await store.setCredits(value, for: course) } }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                WXSectionHeader("Credits")
                TextField(String(localized: "1"), text: $credits).keyboardType(.decimalPad).fieldWell()
            }
            categoriesSection
            entriesSection
            predictorSection
        }
    }

    private var summary: String {
        guard let percent = store.percent(for: course.id) else { return String(localized: "No grades yet.") }
        let letter = GradeMath.grade(for: percent, scale: store.settings.gradeScale).letter
        return String(localized: "\(gradeNumber(percent))% so far · \(letter)")
    }

    // MARK: Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let total = categories.reduce(0) { $0 + $1.weight }
            WXSectionHeader("Weights", accessory: categories.isEmpty ? nil : String(localized: "\(gradeNumber(total))% of 100"),
                            accessoryColor: abs(total - 100) < 0.01 ? WXColor.mossPositive : WXColor.clayLink)
            if categories.isEmpty {
                Text("Optional. Without weights, the grade is total points earned out of total points possible.")
                    .wxBody(14, color: WXColor.inkSecondary)
            }
            ForEach(categories) { category in
                ListRowChip(color: course.paint.color, title: category.name, meta: String(localized: "\(gradeNumber(category.weight))% of the grade")) {
                    removeButton(String(localized: "Remove \(category.name)")) { Task { await store.delete(category) } }
                }
            }
            HStack(spacing: 8) {
                TextField(String(localized: "e.g. Exams"), text: $newCategoryName).fieldWell()
                TextField(String(localized: "%"), text: $newCategoryWeight).keyboardType(.decimalPad).fieldWell().frame(width: 76)
                WXPillButton(String(localized: "Add")) {
                    guard let name = newCategoryName.nilIfBlank, let weight = number(newCategoryWeight) else { return }
                    Task { await store.save(GradeCategory(courseID: course.id, name: name, weight: weight)) }
                    newCategoryName = ""
                    newCategoryWeight = ""
                }
            }
        }
    }

    // MARK: Entries

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            WXSectionHeader("Grades")
            ForEach(entries) { entry in
                let category = categories.first { $0.id == entry.categoryID }?.name
                ListRowChip(color: course.paint.color, title: entry.title,
                            meta: [String(localized: "\(gradeNumber(entry.score)) / \(gradeNumber(entry.maxScore))"), category]
                                .compactMap { $0 }.joined(separator: " · ")) {
                    removeButton(String(localized: "Remove \(entry.title)")) { Task { await store.delete(entry) } }
                }
            }
            TextField(String(localized: "e.g. Quiz 2"), text: $newTitle).fieldWell()
            HStack(spacing: 8) {
                TextField(String(localized: "Score"), text: $newScore).keyboardType(.decimalPad).fieldWell()
                Text("/").wxGrotesk(18)
                TextField(String(localized: "Out of"), text: $newMax).keyboardType(.decimalPad).fieldWell()
            }
            if !categories.isEmpty {
                Picker(String(localized: "Category"), selection: $newCategoryID) {
                    Text("No category").tag(UUID?.none)
                    ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                }
                .tint(WXColor.ink)
            }
            WXPillButton(String(localized: "Add grade")) {
                guard let score = number(newScore), let max = number(newMax), max > 0 else { return }
                let title = newTitle.nilIfBlank ?? String(localized: "Grade")
                Task { await store.save(GradeEntry(courseID: course.id, categoryID: newCategoryID, title: title, score: score, maxScore: max)) }
                newTitle = ""
                newScore = ""
            }
        }
    }

    // MARK: Predictor

    private var predictorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            WXSectionHeader("What do I need on the final?")
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target %").wxLabel()
                    TextField("90", text: $target).keyboardType(.decimalPad).fieldWell()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Final is worth %").wxLabel()
                    TextField("30", text: $finalWeight).keyboardType(.decimalPad).fieldWell()
                }
            }
            Text(prediction).wxGrotesk(18).fixedSize(horizontal: false, vertical: true)
            Text("Uses your grade so far as the score on everything except the final.")
                .wxBody(13, color: WXColor.inkSecondary)
        }
    }

    private var prediction: String {
        guard let current = store.percent(for: course.id) else { return String(localized: "Add a grade first.") }
        guard let goal = number(target), let weight = number(finalWeight) else { return String(localized: "Enter a target and the final's weight.") }
        switch GradeMath.neededOnFinal(current: current, target: goal, finalWeight: weight) {
        case .secured: return String(localized: "You've got \(gradeNumber(goal))% even with 0 on the final.")
        case .needs(let score): return String(localized: "You need \(gradeNumber(score))% on the final.")
        case .outOfReach(let score): return String(localized: "You'd need \(gradeNumber(score))%, so \(gradeNumber(goal))% is out of reach.")
        case .invalid: return String(localized: "The final's weight must be between 1 and 100%.")
        }
    }

    // MARK: Helpers

    private func number(_ text: String) -> Double? {
        NumberInput.parse(text, in: 0...100_000)
    }

    private func removeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WXColor.inkSecondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
