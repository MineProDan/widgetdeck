import CoreKit
import DesignSystem
import SwiftUI
import WellnessFeatureWidgetKit

/// Something a deep link, widget or notification asked the Wellness section to open.
public enum WellnessRequest: Equatable, Sendable {
    case habit(UUID)
    case breathe(BreathingPattern)
    case mood

    /// Parses `widgetx://section/wellness?…` links (see `WellnessDeepLink`).
    public init?(url: URL) {
        if let pattern = WellnessDeepLink.breathingPattern(from: url) { self = .breathe(pattern) }
        else if WellnessDeepLink.opensMood(url) { self = .mood }
        else if let id = WellnessDeepLink.habitID(from: url) { self = .habit(id) }
        else { return nil }
    }
}

/// The Wellness tab (Wellness.png): habit chips, the 14-day mood strip with today's mood keys, the
/// breathing chip, then goals, today's quote and settings below the fold.
public struct WellnessSectionView: View {
    @State private var store: WellnessStore
    @State private var breathing = BreathingSession()
    @Binding private var request: WellnessRequest?
    @Environment(\.scenePhase) private var scenePhase

    @State private var editingHabit: Habit?
    @State private var isAddingHabit = false
    @State private var isEditingNote = false
    @State private var breathingPattern: BreathingPattern?
    @State private var isAddingGoal = false
    @State private var progressGoal: Goal?
    @State private var isShowingSettings = false
    @State private var highlightedHabit: UUID?

    /// Standalone: local storage in the App Group (until the app passes a synced store).
    public init() {
        _store = State(initialValue: WellnessStore())
        _request = .constant(nil)
    }

    public init(store: WellnessStore, request: Binding<WellnessRequest?> = .constant(nil)) {
        _store = State(initialValue: store)
        _request = request
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = store.errorMessage {
                Text(message).wxBody(14, color: WXColor.clayLink).padding(.bottom, 12)
            }
            habitsSection
            moodSection.padding(.top, store.habits.isEmpty ? 14 : 4)
            breathingChip.padding(.top, 40)
            goalsSection.padding(.top, 36)
            quoteSection.padding(.top, 28)
            Button(String(localized: "Wellness settings")) { isShowingSettings = true }
                .wxLabel(color: WXColor.clayLink)
                .frame(minHeight: 44)
                .padding(.top, 18)
        }
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshDay() } }
        }
        .onChange(of: request, initial: true) { _, value in handle(value) }
        .sheet(isPresented: $isAddingHabit) { HabitEditorSheet(habit: nil, store: store) }
        .sheet(item: $editingHabit) { HabitEditorSheet(habit: $0, store: store) }
        .sheet(isPresented: $isEditingNote) { MoodNoteSheet(store: store) }
        .sheet(item: $breathingPattern) { BreathingSessionSheet(store: store, session: breathing, initialPattern: $0) }
        .sheet(isPresented: $isAddingGoal) { GoalEditorSheet(store: store) }
        .sheet(item: $progressGoal) { GoalProgressSheet(goal: $0, store: store) }
        .sheet(isPresented: $isShowingSettings) { WellnessSettingsSheet(store: store) }
    }

    private func handle(_ value: WellnessRequest?) {
        guard let value else { return }
        switch value {
        case let .breathe(pattern): breathingPattern = pattern
        case .mood: break // The mood keys are on this screen.
        case let .habit(id): highlightedHabit = id
        }
        request = nil
    }

    // MARK: Habits

    @ViewBuilder
    private var habitsSection: some View {
        if store.habits.isEmpty {
            if store.isLoaded { HabitSuggestions(store: store) } else { ShimmerLoader().frame(height: 236) }
        } else {
            VStack(spacing: 10) {
                ForEach(store.habits) { habit in
                    HabitRow(habit: habit, store: store, isHighlighted: highlightedHabit == habit.id,
                             edit: { editingHabit = habit })
                }
                // Keep offering the other starters after the first tap, until the user has three habits.
                if store.habits.count < 3 {
                    HabitSuggestions(store: store, excluding: Set(store.habits.map(\.name)), showsIntro: false)
                }
                HStack {
                    Spacer()
                    Button(String(localized: "Add habit")) { isAddingHabit = true }
                        .wxLabel(color: WXColor.clayLink)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.vertical, -6)
                }
            }
        }
    }

    // MARK: Mood

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WXSectionHeader(String(localized: "Mood · last 14 days"), accessory: store.trend14.summary, accessoryColor: WXColor.plumDusk)
            let history = store.history14
            if history.isEmpty {
                Text("Tap how today went. Your last two weeks show up here.")
                    .wxBody(14)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            } else {
                MoodHistoryBars(values: history)
                    .accessibilityElement()
                    .accessibilityLabel(String(localized: "Mood over the last 14 days: \(store.trend14.summary)"))
            }
            MoodKeys(selection: store.todayMood?.mood.rawValue) { index in
                guard let mood = Mood(rawValue: index) else { return }
                Task { await store.logMood(mood) }
            }
            .padding(.top, 4)
            if store.todayMood != nil {
                HStack {
                    Text(trendLine).wxLabel(10)
                    Spacer()
                    Button(store.todayMood?.note == nil ? String(localized: "Add a note") : String(localized: "Edit note")) { isEditingNote = true }
                        .wxLabel(color: WXColor.clayLink)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private var trendLine: String {
        String(localized: "7 days: \(store.trend7.summary.lowercased()) · 30 days: \(store.trend30.summary.lowercased())")
    }

    // MARK: Breathing

    private var breathingChip: some View {
        PaintChip(axis: .horizontal, color: WXColor.plumDusk, field: .fixed(112), shadow: .actionCard) {
            BoxBreathGlyph()
        } label: {
            HStack(spacing: 0) {
                ChipLabelBand(caption: store.settings.breathingPattern.title,
                              value: String(localized: "\(store.settings.breathingMinutes) minutes"),
                              padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14), spacing: 5)
                WXPillButton(String(localized: "Start"), horizontalPadding: 18) {
                    breathingPattern = store.settings.breathingPattern
                }
                .padding(.trailing, 14)
            }
        }
        .frame(minHeight: 112)
    }

    // MARK: Goals

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WXSectionHeader(String(localized: "Goals"), accessory: String(localized: "Add")) { isAddingGoal = true }
            if store.goals.isEmpty {
                Text("Set a target, like 20 km walked or 5 books, and log progress as you go.").wxBody(14)
            }
            ForEach(store.goals) { goal in
                GoalRow(goal: goal, now: .now) { progressGoal = goal }
                    .contextMenu {
                        Button(String(localized: "Delete goal"), role: .destructive) { Task { await store.deleteGoal(goal) } }
                    }
            }
        }
    }

    // MARK: Quote

    private var quoteSection: some View {
        let quote = store.todaysQuote
        return VStack(alignment: .leading, spacing: 10) {
            WXSectionHeader(String(localized: "Today's quote"))
            PaintChip(axis: .horizontal, color: WXSection.wellness.color, field: .fixed(14), punchHole: nil,
                      cornerRadius: WXRadius.chip, shadow: .rowChip) {
                Color.clear
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(quote.text).wxGrotesk(18).fixedSize(horizontal: false, vertical: true)
                    Text("\(quote.author) · \(quote.source)").wxLabel(10).fixedSize(horizontal: false, vertical: true)
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            Text(store.todaysAffirmation.text).wxBody(14).padding(.top, 2)
        }
    }
}

// MARK: - Habit row

/// A habit chip: Sage Noon field with a CheckKey, the name, and the streak line.
struct HabitRow: View {
    let habit: Habit
    let store: WellnessStore
    let isHighlighted: Bool
    let edit: () -> Void

    var body: some View {
        let done = store.isDone(habit)
        let due = habit.schedule.isDue(on: store.today)
        PaintChip(axis: .horizontal, color: WXSection.wellness.color, field: .fixed(68), punchHole: nil,
                  cornerRadius: WXRadius.chip, shadow: .rowChip) {
            Button { Task { await store.toggle(habit) } } label: { CheckKey(isOn: done) }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(habit.name)
                .accessibilityValue(done ? String(localized: "Done") : String(localized: "Not done"))
                .accessibilityHint(String(localized: "Double-tap to tick off today"))
                .accessibilityAddTraits(done ? .isSelected : [])
        } label: {
            ChipLabelBand(value: habit.name, trend: trend(done: done, due: due), trendColor: WXColor.mossPositive, valueSize: 18,
                          padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14), spacing: 5)
                .contentShape(Rectangle())
                .onTapGesture(perform: edit)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(String(localized: "Edit habit"))
        }
        .frame(minHeight: 76)
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: WXRadius.chip + 3, style: .continuous).strokeBorder(WXColor.ink, lineWidth: 2).padding(-3)
            }
        }
        .contextMenu {
            Button(String(localized: "Edit")) { edit() }
            Button(String(localized: "Move up")) { Task { await store.moveHabit(habit, by: -1) } }
            Button(String(localized: "Move down")) { Task { await store.moveHabit(habit, by: 1) } }
            Button(String(localized: "Delete"), role: .destructive) { Task { await store.deleteHabit(habit) } }
        }
    }

    /// "23-day streak · +1 today" / "3-day streak · open today" / "7-day milestone".
    private func trend(done: Bool, due: Bool) -> String {
        let info = store.streak(for: habit)
        let streak = WellnessCopy.streak(info.current, unit: info.unit)
        if done, let milestone = store.milestone, milestone.habitID == habit.id {
            return String(localized: "\(WellnessCopy.streak(milestone.count, unit: info.unit)) · milestone")
        }
        switch habit.schedule {
        case let .timesPerWeek(target):
            let count = info.weekCountBeforeToday + (done ? 1 : 0)
            return String(localized: "\(streak) · \(min(count, target)) of \(target) this week")
        default:
            if !due { return String(localized: "\(streak) · not due today") }
            if info.current == 0 { return String(localized: "Open today") }
            return done ? String(localized: "\(streak) · +1 today") : String(localized: "\(streak) · open today")
        }
    }
}

/// First run: three one-tap suggestions from the mockup.
struct HabitSuggestions: View {
    let store: WellnessStore
    var excluding: Set<String> = []
    var showsIntro = true
    static let all = [String(localized: "Read 20 min"), String(localized: "Water, 8 glasses"), String(localized: "Stretch")]

    private var suggestions: [String] { Self.all.filter { !excluding.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsIntro {
                Text("Pick a habit to start. You can rename it or add your own.").wxBody(15)
            }
            ForEach(suggestions, id: \.self) { name in
                Button { Task { await store.addHabit(name: name, schedule: .daily) } } label: {
                    PaintChip(axis: .horizontal, color: WXSection.wellness.color, field: .fixed(68), punchHole: nil,
                              cornerRadius: WXRadius.chip, shadow: .rowChip) {
                        CheckKey(isOn: false)
                    } label: {
                        ChipLabelBand(value: name, trend: String(localized: "Tap to add · every day"), trendColor: WXColor.mossPositive,
                                      valueSize: 18, padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14), spacing: 5)
                    }
                    .frame(minHeight: 76)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Add habit: \(name)"))
            }
        }
    }
}

/// A goal row: title, progress and trend-based estimate, with a "+" to log progress.
struct GoalRow: View {
    let goal: Goal
    let now: Date
    let log: () -> Void

    var body: some View {
        ListRowChip(color: WXSection.wellness.color, title: goal.title, meta: meta,
                    metaColor: GoalMath.fraction(goal) >= 1 ? WXColor.mossPositive : WXColor.inkSecondary) {
            Button(action: log) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WXColor.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Log progress for \(goal.title)"))
        }
    }

    private var meta: String {
        let total = GoalMath.total(goal)
        let percent = Int((GoalMath.fraction(goal) * 100).rounded())
        let amount = "\(GoalFormat.number(total)) of \(GoalFormat.number(goal.target)) \(goal.unit)"
        if percent >= 100 { return String(localized: "\(amount) · done") }
        if let eta = GoalMath.eta(goal, now: now) {
            return String(localized: "\(amount) · \(percent)% · est. \(eta.formatted(.dateTime.month(.abbreviated).day()))")
        }
        return "\(amount) · \(percent)%"
    }
}

enum GoalFormat {
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
