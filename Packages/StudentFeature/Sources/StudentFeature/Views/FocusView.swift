import DesignSystem
import StudentFeatureWidgetKit
import SwiftUI

/// Focus tab (S-08): pick a preset and what you're working on, then a running timer chip that
/// matches the Lock Screen Live Activity. Countdown and bar are `Text(timerInterval:)` /
/// `ProgressView(timerInterval:)`; no timers run in the app either.
struct FocusContent: View {
    let store: StudentStore
    @State private var choice: Choice = .pomodoro
    @State private var custom = FocusPreset(focusMinutes: 40, breakMinutes: 8, rounds: 3)
    @State private var title = ""
    @State private var courseID: UUID?
    @State private var didLoad = false

    enum Choice: Hashable { case pomodoro, deepWork, custom }

    private var timer: FocusTimer { store.focus }

    private var preset: FocusPreset {
        switch choice {
        case .pomodoro: .pomodoro
        case .deepWork: .deepWork
        case .custom: custom
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let session = timer.state {
                RunningFocusChip(session: session)
                HStack(spacing: 10) {
                    if timer.isPaused {
                        WXPillButton(String(localized: "Resume")) { Task { await timer.resume() } }
                    } else {
                        WXPillButton(String(localized: "Pause")) { Task { await timer.pause() } }
                    }
                    WXPillButton(String(localized: "Stop")) { Task { await timer.stop() } }
                }
                .padding(.top, 10)
                Text("You'll get a notification when each block ends, even if Widgetdeck is closed.")
                    .wxBody(14, color: WXColor.inkSecondary)
                    .padding(.top, 6)
            } else {
                setup
            }
            if let message = timer.message {
                Text(message).wxBody(13, color: WXColor.clayLink).padding(.top, 6)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            let saved = store.settings.focusPreset
            choice = saved == .pomodoro ? .pomodoro : saved == .deepWork ? .deepWork : .custom
            if choice == .custom { custom = saved }
        }
    }

    @ViewBuilder
    private var setup: some View {
        WXSectionHeader("Timer")
        SelectRow(color: WXSection.student.color, title: String(localized: "Pomodoro"), meta: String(localized: "4 × 25 min focus · 5 min breaks"),
                  isOn: choice == .pomodoro) { choice = .pomodoro }
        SelectRow(color: WXSection.student.color, title: String(localized: "Deep work"), meta: String(localized: "2 × 50 min focus · 10 min break"),
                  isOn: choice == .deepWork) { choice = .deepWork }
        SelectRow(color: WXSection.student.color, title: String(localized: "Custom"),
                  meta: String(localized: "\(custom.rounds) × \(custom.focusMinutes) min focus · \(custom.breakMinutes) min breaks"),
                  isOn: choice == .custom) { choice = .custom }
        if choice == .custom {
            VStack(spacing: 4) {
                Stepper(value: $custom.focusMinutes, in: 5...180, step: 5) { Text("Focus \(custom.focusMinutes) min").wxBody(15, color: WXColor.ink) }
                Stepper(value: $custom.breakMinutes, in: 0...60) { Text("Break \(custom.breakMinutes) min").wxBody(15, color: WXColor.ink) }
                Stepper(value: $custom.rounds, in: 1...8) { Text("Rounds \(custom.rounds)").wxBody(15, color: WXColor.ink) }
            }
            .padding(.horizontal, 4)
        }

        WXSectionHeader("Working on").padding(.top, 16)
        TextField(String(localized: "e.g. Chem lab report"), text: $title).fieldWell()
        // Only real items: the sample week's deadlines aren't the user's work.
        let open = store.schedule.deadlines.filter { !$0.isDone && $0.due > .now && (store.mode == .live || $0.assignmentID != nil) }.prefix(3)
        ForEach(Array(open)) { item in
            SelectRow(color: item.paint.color, title: item.title,
                      meta: [item.code, ScheduleFormat.dayAndTime(item.due, now: .now)].compactMap { $0 }.joined(separator: " · "),
                      isOn: title == item.title && courseID == item.courseID) {
                title = item.title
                courseID = item.courseID
            }
        }
        if !store.courses.isEmpty {
            CoursePickerRows(courses: store.courses, courseID: $courseID).padding(.top, 16)
        }

        WXPrimaryButton(String(localized: "Start \(preset.focusMinutes) min focus")) {
            let course = store.courses.first { $0.id == courseID }
            let label = title.nilIfBlank ?? course?.name ?? course?.code ?? String(localized: "Focus")
            let chosen = preset
            Task {
                await store.setFocusPreset(chosen)
                await timer.start(preset: chosen, title: label, courseID: course?.id, paint: course?.paint ?? .coral,
                                  permissions: store.permissions)
            }
        }
        .padding(.top, 18)
    }
}

/// The in-app version of the Lock Screen focus chip.
struct RunningFocusChip: View {
    let session: FocusSessionState

    var body: some View {
        // Re-renders at each block end so the chip moves on to the break / next round by itself.
        // The schedule starts at the plan start: with only future dates, TimelineView would
        // render the first (future) date straight away and show the wrong block.
        TimelineView(.explicit([session.plan.start] + session.plan.blocks.map(\.end))) { context in
            chip(at: context.date)
        }
    }

    @ViewBuilder
    private func chip(at date: Date) -> some View {
        if let state = session.activityState(at: date) {
            let attributes = FocusActivityAttributes(title: session.title, courseID: session.courseID, paint: session.paint,
                                                     rounds: session.plan.preset.rounds)
            PaintChip(axis: .horizontal, color: session.paint.color, field: .fixed(108), punchHole: .medium,
                      cornerRadius: WXRadius.card, shadow: .chipRest) {
                VStack {
                    Spacer()
                    FocusProgressBar(state: state, fill: WXColor.labelIvory, track: WXColor.labelIvory.opacity(0.3))
                        .padding(.horizontal, 14)
                        .padding(.bottom, 16)
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(focusCaption(attributes, state, isStale: false)).wxLabel().lineLimit(1)
                    FocusCountdown(state: state, isStale: false)
                        .wxGrotesk(40, tabular: true)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(session.title).wxLabel().lineLimit(1)
                }
                .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 124)
            .accessibilityElement(children: .combine)
        } else {
            ListRowChip(color: session.paint.color, title: String(localized: "Session done"), meta: session.title) { EmptyView() }
        }
    }
}
