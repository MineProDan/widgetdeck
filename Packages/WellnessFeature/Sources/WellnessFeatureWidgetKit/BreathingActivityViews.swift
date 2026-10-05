import ActivityKit
import DesignSystem
import SwiftUI
import WidgetKit

/// Lavender used on the black Dynamic Island (the lightest plum tint in the mockup).
private let islandPlum = WXColor.moodTints[0]

/// "BOX BREATHING · 2:10 LEFT": the countdown is `Text(timerInterval:)`, so it ticks by itself.
private func remainingCaption(_ attributes: BreathingActivityAttributes, _ state: BreathingActivityAttributes.ContentState) -> Text {
    Text("\(attributes.pattern.title) · \(Text(timerInterval: Date.now...max(state.sessionEnd, .now), countsDown: true, showsHours: false)) left")
}

/// "Hold · 4". Hidden when the activity is stale (the app stopped updating phases).
private func phaseText(_ state: BreathingActivityAttributes.ContentState, isStale: Bool) -> String? {
    guard !isStale, let phase = state.phase, state.phaseEnd > .now else { return nil }
    return "\(phase.title) · \(state.phaseSeconds)"
}

/// Lock Screen banner: a Plum Dusk Paint Chip, like the mockup's focus timer chip.
public struct BreathingLockScreenView: View {
    private let context: ActivityViewContext<BreathingActivityAttributes>

    public init(context: ActivityViewContext<BreathingActivityAttributes>) {
        self.context = context
    }

    public var body: some View {
        PaintChip(axis: .horizontal, color: WXColor.plumDusk, field: .fixed(108), punchHole: .medium, cornerRadius: 0, shadow: nil) {
            VStack {
                Spacer()
                ProgressView(timerInterval: context.attributes.sessionStart...max(context.state.sessionEnd, context.attributes.sessionStart.addingTimeInterval(1)),
                             countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(WXColor.labelIvory)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                remainingCaption(context.attributes, context.state)
                    .wxLabel(color: WXColor.inkSecondary)
                    .monospacedDigit()
                Text(phaseText(context.state, isStale: context.isStale) ?? String(localized: "Keep breathing"))
                    .wxGrotesk(28)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 116)
        .activityBackgroundTint(WXColor.labelIvory)
        .activitySystemActionForegroundColor(WXColor.ink)
    }
}

/// Dynamic Island: compact (plum key + countdown), minimal (plum key) and expanded (glyph,
/// "BOX BREATHING · 2:10 LEFT" and the phase in large type), per LockScreen.png.
public enum BreathingIsland {
    public static func make(context: ActivityViewContext<BreathingActivityAttributes>) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                IslandBoxGlyph()
                    .frame(width: 58, height: 58)
                    .padding(.leading, 6)
                    .padding(.top, 6)
            }
            DynamicIslandExpandedRegion(.center) {
                IslandExpandedCenter(attributes: context.attributes, state: context.state, isStale: context.isStale)
            }
        } compactLeading: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(WXColor.plumDusk)
                .frame(width: 18, height: 18)
        } compactTrailing: {
            IslandCountdown(sessionEnd: context.state.sessionEnd)
        } minimal: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(WXColor.plumDusk)
                .frame(width: 18, height: 18)
        }
        .keylineTint(islandPlum)
        .widgetURL(WellnessDeepLink.url(breathe: context.attributes.pattern))
    }
}

private struct IslandExpandedCenter: View {
    let attributes: BreathingActivityAttributes
    let state: BreathingActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            remainingCaption(attributes, state)
                .wxLabel(color: Color(white: 0.75))
                .monospacedDigit()
                .lineLimit(1)
            Text(phaseText(state, isStale: isStale) ?? String(localized: "Keep breathing"))
                .font(WXFont.headline(30))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

private struct IslandCountdown: View {
    let sessionEnd: Date

    var body: some View {
        Text(timerInterval: Date.now...max(sessionEnd, .now), countsDown: true, showsHours: false)
            .font(WXFont.title(15))
            .monospacedDigit()
            .foregroundStyle(islandPlum)
            .frame(width: 44)
    }
}

/// The mockup's island glyph: a dim square with the traced edge and dot in lavender.
private struct IslandBoxGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 54
            let square = Path(roundedRect: CGRect(x: 5 * s, y: 5 * s, width: 44 * s, height: 44 * s), cornerRadius: 6 * s)
            context.stroke(square, with: .color(Color(white: 0.25)), lineWidth: 3 * s)
            var trace = Path()
            trace.move(to: CGPoint(x: 11 * s, y: 5 * s))
            trace.addLine(to: CGPoint(x: 43 * s, y: 5 * s))
            trace.addArc(tangent1End: CGPoint(x: 49 * s, y: 5 * s), tangent2End: CGPoint(x: 49 * s, y: 11 * s), radius: 6 * s)
            trace.addLine(to: CGPoint(x: 49 * s, y: 31 * s))
            context.stroke(trace, with: .color(islandPlum), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: 45 * s, y: 27 * s, width: 8 * s, height: 8 * s)), with: .color(islandPlum))
        }
        .accessibilityHidden(true)
    }
}
