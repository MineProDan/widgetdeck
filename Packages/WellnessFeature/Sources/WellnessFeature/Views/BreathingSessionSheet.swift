import DesignSystem
import SwiftUI
import WellnessFeatureWidgetKit

/// W-04: pick a pattern and length, then breathe along. The dot traces the square once per cycle;
/// with Reduce Motion it stays still and the words carry the rhythm.
struct BreathingSessionSheet: View {
    let store: WellnessStore
    let session: BreathingSession
    @State private var pattern: BreathingPattern
    @State private var minutes: Int
    @State private var sound: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: WellnessStore, session: BreathingSession, initialPattern: BreathingPattern) {
        self.store = store
        self.session = session
        _pattern = State(initialValue: initialPattern)
        _minutes = State(initialValue: store.settings.breathingMinutes)
        _sound = State(initialValue: store.settings.breathingSound)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(session.isRunning ? String(localized: "End") : String(localized: "Close")) {
                    session.stop()
                    dismiss()
                }
                .wxLabel(color: WXColor.clayLink)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, WXSpace.gutter)

            if let plan = session.plan, session.isRunning {
                running(plan)
            } else {
                setup
            }
        }
        .background(WXColor.paperIvory.ignoresSafeArea())
        .interactiveDismissDisabled(session.isRunning)
    }

    // MARK: Setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 22) {
            WXPageHeader(title: String(localized: "Breathe"), subtitle: String(localized: "A few slow minutes, at your pace"), titleSize: 36)
            PaintChip(axis: .horizontal, color: WXColor.plumDusk, field: .fixed(112), shadow: .actionCard) {
                BoxBreathGlyph()
            } label: {
                ChipLabelBand(caption: pattern.title, value: String(localized: "\(minutes) minutes"),
                              padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14), spacing: 5)
            }
            .frame(height: 112)
            VStack(alignment: .leading, spacing: 10) {
                Text("Pattern").wxLabel()
                WXSegmentedControl(selection: $pattern, options: BreathingPattern.allCases.map { ($0, $0.shortTitle) })
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Length").wxLabel()
                WXSegmentedControl(selection: $minutes, options: BreathingDuration.allCases.map { ($0.rawValue, $0.title) })
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(isOn: $sound) {
                Text("Soft chime at each breath").wxBody(16, color: WXColor.ink)
            }
            .tint(WXColor.mossPositive)
            Spacer(minLength: 0)
            WXPrimaryButton(String(localized: "Start")) {
                Task {
                    await store.updateSettings {
                        $0.breathingPattern = pattern
                        $0.breathingMinutes = minutes
                        $0.breathingSound = sound
                    }
                }
                session.start(pattern: pattern, minutes: minutes, sound: sound)
            }
        }
        .padding(.horizontal, WXSpace.gutter)
        .padding(.bottom, WXSpace.md)
    }

    // MARK: Running

    private func running(_ plan: BreathingPlan) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let now = reduceMotion ? (session.plan?.phases[safe: session.phaseIndex]?.start ?? context.date) : context.date
            let phase = plan.phase(at: max(now, plan.start)) ?? plan.phases.first
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                BreathSquare(plan: plan, date: now, animated: !reduceMotion)
                    .frame(width: 220, height: 220)
                VStack(spacing: 8) {
                    Text(phase?.kind.title ?? "").wxGrotesk(40)
                    Text(phase.map { "\($0.seconds)" } ?? "").wxLabel(13)
                }
                .accessibilityElement(children: .combine)
                Text("\(Text(timerInterval: Date.now...max(plan.end, .now), countsDown: true, showsHours: false)) left")
                    .wxLabel(color: WXColor.inkSecondary)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, WXSpace.gutter)
        .padding(.bottom, WXSpace.gutter)
    }
}

/// The breathing square: a faint Plum Dusk track with the traced edge and a dot that goes once
/// around per cycle (the in-app, animated version of `BoxBreathGlyph`).
private struct BreathSquare: View {
    let plan: BreathingPlan
    let date: Date
    let animated: Bool

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 12
            let rect = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
            let square = Self.square(in: rect, radius: 28)
            context.stroke(square, with: .color(WXColor.plumDusk.opacity(0.2)), lineWidth: 10)
            let progress = cycleProgress
            guard progress > 0 else { return }
            let traced = square.trimmedPath(from: 0, to: progress)
            context.stroke(traced, with: .color(WXColor.plumDusk), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            if let point = traced.currentPoint {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)), with: .color(WXColor.plumDusk))
            }
        }
        .accessibilityHidden(true)
    }

    /// A rounded square that starts at the top-left and runs clockwise: in along the top, hold down
    /// the right, out along the bottom, hold up the left (box breathing).
    static func square(in rect: CGRect, radius r: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
        path.closeSubpath()
        return path
    }

    private var cycleProgress: Double {
        let cycle = Double(plan.pattern.cycleSeconds)
        let elapsed = max(date.timeIntervalSince(plan.start), 0)
        return animated ? (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle : 0.25
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
