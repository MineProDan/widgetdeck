import DesignSystem
import StudentFeatureWidgetKit
import SwiftUI

/// First-run class setup: a few friendly questions per course so the Next Class and Today's
/// Schedule widgets have everything (what to call the room, how the user gets there, and what kind
/// of heads-up they want). Titles, days, times and locations come from the calendar.
///
/// Flow: intro (the classes deal in) → per course: room, travel, heads-up → done ("You'll only have
/// to do this once."). Skip is always available; Settings can restart it.
struct ClassSetupFlow: View {
    let store: StudentStore
    let onClose: () -> Void

    private enum Step: Hashable { case intro, room(Int), travel(Int), headsUp(Int), done }

    @State private var items: [StudentStore.SetupItem] = []
    @State private var answers: [UUID: StudentStore.SetupAnswer] = [:]
    @State private var step: Step = .intro
    @State private var forward = true
    @State private var dealt = false
    @State private var isSaving = false
    @FocusState private var roomFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let index = classIndex {
                header(index, detail: headerDetail(index))
                    .id(items[index].id)
                    .transition(transition)
                    .padding(.horizontal, WXSpace.gutter)
                    .padding(.top, 8)
                    .animation(Self.ease, value: headerDetail(index))
            }
            ZStack {
                screen
                    .id(step)
                    .transition(transition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, WXSpace.gutter)
            footer
        }
        .background(WXColor.paperIvory.ignoresSafeArea())
        .onAppear {
            items = store.pendingSetup
            for item in items {
                answers[item.id] = StudentStore.SetupAnswer(room: item.course.room ?? item.roomSuggestion ?? "",
                                                            travel: item.hasAddress ? (item.course.travelMode ?? store.settings.travelMode) : nil,
                                                            headsUp: item.hasAddress ? .leave : .before15)
            }
            dealt = true
        }
        .sensoryFeedback(.selection, trigger: step)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            progressDots
            Spacer()
            if step != .done {
                Button(String(localized: "Skip")) {
                    Task {
                        await store.skipSetup()
                        onClose()
                    }
                }
                .wxLabel(color: WXColor.clayLink)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, WXSpace.gutter)
        .padding(.top, 8)
    }

    private var progressDots: some View {
        let total = items.count + 2
        let current: Int = switch step {
        case .intro: 0
        case .room(let i), .travel(let i), .headsUp(let i): i + 1
        case .done: total - 1
        }
        return HStack(spacing: 5) {
            ForEach(0..<max(total, 2), id: \.self) { index in
                Capsule()
                    .fill(index == current ? WXColor.ink : WXColor.rule)
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: current)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Step \(current + 1) of \(total)"))
    }

    /// Exponential ease-out used by every step change: quick to start, soft to land.
    static let ease = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.34)

    private var classIndex: Int? {
        switch step {
        case .room(let i), .travel(let i), .headsUp(let i): i
        default: nil
        }
    }

    private func headerDetail(_ index: Int) -> String {
        let item = items[index]
        switch step {
        case .room: return "\(item.days) · \(item.time)"
        case .travel: return displayPlace(index)
        default: return answers[item.id]?.travel.map { $0.title } ?? String(localized: "No travel")
        }
    }

    /// A short slide (not a full-screen push) plus a fade, so questions feel like cards being
    /// swapped in place. Reduce Motion: fade only.
    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        let distance: CGFloat = forward ? 36 : -36
        return .asymmetric(insertion: .offset(x: distance).combined(with: .opacity),
                           removal: .offset(x: -distance * 0.6).combined(with: .opacity))
    }

    private var footer: some View {
        VStack(spacing: 6) {
            WXPrimaryButton(primaryTitle) { advance() }
                .disabled(isSaving)
                .animation(.easeOut(duration: 0.2), value: primaryTitle)
            if case .headsUp(let index) = step, index < items.count - 1 {
                Button(String(localized: "Use these answers for the other \(items.count - index - 1)")) { copyRemaining(from: index) }
                    .wxLabel(color: WXColor.clayLink)
                    .frame(minHeight: 44)
            } else if case .room = step {
                backButton
            } else if case .travel = step {
                backButton
            } else if case .headsUp = step {
                backButton
            }
        }
        .padding(.horizontal, WXSpace.gutter)
        .padding(.bottom, WXSpace.md)
    }

    private var backButton: some View {
        Button(String(localized: "Back")) { back() }
            .wxLabel(color: WXColor.inkSecondary)
            .frame(minHeight: 44)
    }

    private var primaryTitle: String {
        switch step {
        case .intro: items.count == 1 ? String(localized: "Set up my class") : String(localized: "Set up my classes")
        case .headsUp(let index): index == items.count - 1 ? String(localized: "Finish") : String(localized: "Next class")
        case .done: String(localized: "Done")
        default: String(localized: "Next")
        }
    }

    // MARK: Screens

    @ViewBuilder
    private var screen: some View {
        switch step {
        case .intro: intro
        case .room(let i): roomScreen(i)
        case .travel(let i): travelScreen(i)
        case .headsUp(let i): headsUpScreen(i)
        case .done: doneScreen
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                Text(items.count == 1 ? String(localized: "We found your class.") : String(localized: "We found \(items.count) classes."))
                    .wxGrotesk(34)
                    .padding(.top, 24)
                Text("A few quick questions each, so your widgets show the right room and tell you when to leave.")
                    .wxBody(16, color: WXColor.inkBody)
            }
            .opacity(dealt ? 1 : 0)
            .offset(y: dealt || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? .none : Self.ease, value: dealt)
            deck.padding(.top, 28)
        }
    }

    /// The classes fanned like paint chips; they deal in from below on appear.
    private var deck: some View {
        let shown = Array(items.prefix(5))
        let mid = Double(shown.count - 1) / 2
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                let offset = Double(index) - mid
                classCard(item, width: 140)
                    .rotationEffect(.degrees(dealt ? offset * 10 : 0), anchor: .bottom)
                    .offset(x: dealt ? offset * 62 : 0, y: dealt ? abs(offset) * 14 : 240)
                    .opacity(dealt ? 1 : 0)
                    .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.78).delay(0.12 + Double(index) * 0.06), value: dealt)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map(\.course.code).joined(separator: ", "))
    }

    private func classCard(_ item: StudentStore.SetupItem, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(item.course.paint.color).frame(height: 76)
                .overlay(alignment: .topLeading) {
                    Circle().fill(WXColor.paperIvory).frame(width: 10, height: 10).padding(10)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.days).wxLabel(color: WXColor.inkSecondary).lineLimit(1)
                Text(item.course.code).wxGrotesk(16).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: width)
        .background(WXColor.labelIvory)
        .clipShape(RoundedRectangle(cornerRadius: WXRadius.chip, style: .continuous))
        .wxShadow(.chipRest, cornerRadius: WXRadius.chip)
    }

    /// The class being asked about, pinned above each question.
    private func header(_ index: Int, detail: String) -> some View {
        let item = items[index]
        return ListRowChip(color: item.course.paint.color, title: item.course.code,
                           meta: items.count > 1 ? String(localized: "Class \(index + 1) of \(items.count) · \(detail)") : detail) { EmptyView() }
            .fixedSize(horizontal: false, vertical: true)
    }

    private func question(_ title: String, _ subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).wxGrotesk(28).fixedSize(horizontal: false, vertical: true)
            if let subtitle { Text(subtitle).wxBody(15, color: WXColor.inkBody) }
        }
        .padding(.top, 10)
    }

    private func roomScreen(_ index: Int) -> some View {
        let item = items[index]
        return VStack(alignment: .leading, spacing: 16) {
            question(String(localized: "What do you call this room?"),
                     String(localized: "Your widgets show this. Directions still use the calendar address."))
            TextField(item.place ?? String(localized: "ICS 192"), text: binding(index, \.room))
                .focused($roomFocused)
                .submitLabel(.next)
                .onSubmit { advance() }
                .fieldWell()
            if let suggestion = item.roomSuggestion, answers[item.id]?.room != suggestion {
                suggestionPill(suggestion, note: String(localized: "from your calendar notes")) { answers[item.id]?.room = suggestion }
            } else if let place = item.place, answers[item.id]?.room.isEmpty == true {
                Text("Leave it blank to show “\(place)”.").wxBody(14, color: WXColor.inkSecondary)
            }
        }
    }

    private func suggestionPill(_ value: String, note: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(value).font(WXFont.body(15, weight: .semibold)).foregroundStyle(WXColor.labelIvory)
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(WXColor.ink, in: Capsule(style: .continuous))
                Text(note).wxBody(14, color: WXColor.inkSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func travelScreen(_ index: Int) -> some View {
        let item = items[index]
        let selected = answers[item.id]?.travel
        return VStack(alignment: .leading, spacing: 16) {
            question(String(localized: "How do you get there?"),
                     item.hasAddress ? nil : String(localized: "This class has no address in your calendar, so travel time can't be worked out."))
            HStack(spacing: 10) {
                ForEach(TravelMode.allCases) { mode in
                    travelTile(mode.title, systemImage: mode.symbol, isOn: selected == mode, enabled: item.hasAddress) {
                        answers[item.id]?.travel = mode
                    }
                }
            }
            travelTile(String(localized: "Already there or online"), systemImage: "laptopcomputer", isOn: selected == nil, enabled: true, compact: true) {
                answers[item.id]?.travel = nil
                if answers[item.id]?.headsUp == .leave { answers[item.id]?.headsUp = .before15 }
            }
        }
    }

    private func travelTile(_ title: String, systemImage: String, isOn: Bool, enabled: Bool, compact: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if compact {
                    HStack(spacing: 10) {
                        Image(systemName: systemImage).font(.system(size: 18, weight: .semibold))
                        Text(title).font(WXFont.body(15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: systemImage).font(.system(size: 26, weight: .semibold)).frame(height: 32)
                        Text(title).font(WXFont.body(14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 96)
                }
            }
            .foregroundStyle(isOn ? WXColor.labelIvory : WXColor.ink)
            .background(isOn ? WXSection.student.color : WXColor.labelIvory,
                        in: RoundedRectangle(cornerRadius: WXRadius.chip, style: .continuous))
            .wxShadow(isOn ? .chipLifted : .chipRest, cornerRadius: WXRadius.chip)
            .offset(y: isOn && !reduceMotion ? -4 : 0)
            .contentShape(RoundedRectangle(cornerRadius: WXRadius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func headsUpScreen(_ index: Int) -> some View {
        let item = items[index]
        let answer = answers[item.id] ?? .init()
        let canLeave = answer.travel != nil
        return VStack(alignment: .leading, spacing: 14) {
            question(String(localized: "Want a heads-up?"))
            VStack(spacing: 10) {
                if canLeave {
                    headsUpRow(String(localized: "When it's time to leave"), String(localized: "Uses travel time and your location"),
                               isOn: answer.headsUp == .leave) { answers[item.id]?.headsUp = .leave }
                }
                headsUpRow(String(localized: "15 min before class"), nil, isOn: answer.headsUp == .before15) { answers[item.id]?.headsUp = .before15 }
                headsUpRow(String(localized: "No thanks"), nil, isOn: answer.headsUp == .none) { answers[item.id]?.headsUp = .none }
            }
            if answer.headsUp != .none {
                example(item, answer: answer)
                    .id(answer.headsUp == .leave)
                    .transition(reduceMotion ? .opacity : .offset(y: 10).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: answer.headsUp)
    }

    private func headsUpRow(_ title: String, _ meta: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(WXFont.body(16, weight: .semibold))
                    if let meta { Text(meta).wxBody(13, color: isOn ? WXColor.labelIvory.opacity(0.8) : WXColor.inkSecondary) }
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(isOn ? WXColor.labelIvory : WXColor.ink)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(isOn ? WXColor.ink : WXColor.labelIvory, in: RoundedRectangle(cornerRadius: WXRadius.chip, style: .continuous))
            .wxShadow(isOn ? .chipLifted : .chipRest, cornerRadius: WXRadius.chip)
            .scaleEffect(isOn && !reduceMotion ? 1.0 : 0.985)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// What the heads-up will look like, with an illustrative 19-minute trip.
    private func example(_ item: StudentStore.SetupItem, answer: StudentStore.SetupAnswer) -> some View {
        let place = answer.room.nilIfBlank ?? item.place
        let title: String
        let meta: String
        switch answer.headsUp {
        case .leave:
            let leave = item.start.addingTimeInterval(-TimeInterval((19 + store.settings.leaveBufferMinutes) * 60))
            title = String(localized: "Leave by \(ScheduleFormat.time(leave)) for \(item.course.code)")
            meta = String(localized: "Example · about 19 min \(answer.travel?.phrase ?? "")")
        default:
            title = String(localized: "\(item.course.code) in 15 min")
            meta = [String(localized: "Example"), item.time, place].compactMap { $0 }.joined(separator: " · ")
        }
        return ListRowChip(color: item.course.paint.color, title: title, meta: meta, metaColor: WXColor.clayLink) { EmptyView() }
            .fixedSize(horizontal: false, vertical: true)
    }

    private var doneScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            deck.padding(.top, 20)
            Group {
                Text("All set.").wxGrotesk(36).padding(.top, 20)
                Text("You'll only have to do this once. Change anything later in a course, or run this again from Settings.")
                    .wxBody(16, color: WXColor.inkBody)
            }
            .opacity(dealt ? 1 : 0)
            .offset(y: dealt || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? .none : Self.ease.delay(0.22), value: dealt)
        }
        .onAppear {
            dealt = false
            withAnimation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.7)) { dealt = true }
        }
    }

    // MARK: Navigation

    private func displayPlace(_ index: Int) -> String {
        let item = items[index]
        return answers[item.id]?.room.nilIfBlank ?? item.place ?? item.time
    }

    private func binding(_ index: Int, _ keyPath: WritableKeyPath<StudentStore.SetupAnswer, String>) -> Binding<String> {
        let id = items[index].id
        return Binding(get: { answers[id]?[keyPath: keyPath] ?? "" }, set: { answers[id]?[keyPath: keyPath] = $0 })
    }

    private func move(to next: Step, forward isForward: Bool = true) {
        roomFocused = false
        forward = isForward
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Self.ease) { step = next }
    }

    private func advance() {
        switch step {
        case .intro: items.isEmpty ? move(to: .done) : move(to: .room(0))
        case .room(let i): move(to: .travel(i))
        case .travel(let i): move(to: .headsUp(i))
        case .headsUp(let i): i + 1 < items.count ? move(to: .room(i + 1)) : finish()
        case .done: onClose()
        }
    }

    private func back() {
        switch step {
        case .room(let i): i == 0 ? move(to: .intro, forward: false) : move(to: .headsUp(i - 1), forward: false)
        case .travel(let i): move(to: .room(i), forward: false)
        case .headsUp(let i): move(to: .travel(i), forward: false)
        default: break
        }
    }

    /// Copies travel and heads-up to the rest (rooms stay per class), then finishes.
    private func copyRemaining(from index: Int) {
        guard let source = answers[items[index].id] else { return }
        for item in items[(index + 1)...] {
            answers[item.id]?.travel = item.hasAddress ? source.travel : nil
            answers[item.id]?.headsUp = item.hasAddress || source.headsUp != .leave ? source.headsUp : .before15
        }
        finish()
    }

    private func finish() {
        isSaving = true
        Task {
            for item in items {
                if let answer = answers[item.id] { await store.applySetup(answer, to: item.course) }
            }
            await store.finishSetup(answers: Array(answers.values))
            isSaving = false
            move(to: .done)
        }
    }
}

extension TravelMode {
    /// SF Symbol for the travel tiles.
    var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .driving: "car.fill"
        case .transit: "tram.fill"
        }
    }
}
