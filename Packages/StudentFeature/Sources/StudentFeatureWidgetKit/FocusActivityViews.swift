import ActivityKit
import DesignSystem
import SwiftUI
import WidgetKit

/// "18:20" for a paused block (static, no ticking).
public func focusClock(_ seconds: TimeInterval) -> String {
    Duration.seconds(max(0, seconds.rounded())).formatted(.time(pattern: .minuteSecond))
}

/// "FOCUS · SESSION 2 OF 4" / "BREAK · AFTER SESSION 2" / "PAUSED · SESSION 2 OF 4".
public func focusCaption(_ attributes: FocusActivityAttributes, _ state: FocusActivityAttributes.ContentState, isStale: Bool, short: Bool = false) -> String {
    if isStale || state.blockEnd <= .now {
        return state.kind == .focus ? String(localized: "Focus block done") : String(localized: "Break over")
    }
    let session = short ? String(localized: "\(state.round) of \(attributes.rounds)")
                        : String(localized: "Session \(state.round) of \(attributes.rounds)")
    if state.pausedRemaining != nil { return String(localized: "Paused · \(session)") }
    return state.kind == .focus ? String(localized: "Focus · \(session)") : String(localized: "Break · \(session)")
}

/// The ticking countdown, a static time while paused, or "Open Widgetdeck" once the block is over.
public struct FocusCountdown: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    public init(state: FocusActivityAttributes.ContentState, isStale: Bool) {
        self.state = state
        self.isStale = isStale
    }

    public var body: some View {
        if let paused = state.pausedRemaining {
            Text(focusClock(paused))
        } else if isStale || state.blockEnd <= .now {
            Text("Done")
        } else {
            Text(timerInterval: Date.now...state.blockEnd, countsDown: true, showsHours: false)
        }
    }
}

/// Flat progress bar that fills as the block runs (`ProgressView(timerInterval:)`).
public struct FocusProgressBar: View {
    let state: FocusActivityAttributes.ContentState
    let fill: Color
    let track: Color

    public init(state: FocusActivityAttributes.ContentState, fill: Color, track: Color) {
        self.state = state
        self.fill = fill
        self.track = track
    }

    public var body: some View {
        Group {
            if let paused = state.pausedRemaining {
                let total = max(state.blockEnd.timeIntervalSince(state.blockStart), 1)
                ProgressView(value: min(max(1 - paused / total, 0), 1))
            } else if state.blockEnd > state.blockStart {
                ProgressView(timerInterval: state.blockStart...state.blockEnd, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: 1)
            }
        }
        .progressViewStyle(.linear)
        .tint(fill)
        .background(track, in: Capsule())
    }
}

/// Lock Screen banner: the mockup's focus Paint Chip (course paint field, ivory label band).
public struct FocusLockScreenView: View {
    private let context: ActivityViewContext<FocusActivityAttributes>

    public init(context: ActivityViewContext<FocusActivityAttributes>) {
        self.context = context
    }

    public var body: some View {
        let state = context.state
        PaintChip(axis: .horizontal, color: context.attributes.paint.color, field: .fixed(108), punchHole: .medium,
                  cornerRadius: 0, shadow: nil) {
            VStack {
                Spacer()
                FocusProgressBar(state: state, fill: WXColor.labelIvory, track: WXColor.labelIvory.opacity(0.3))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(focusCaption(context.attributes, state, isStale: context.isStale))
                    .wxLabel(color: WXColor.inkSecondary)
                    .lineLimit(1)
                FocusCountdown(state: state, isStale: context.isStale)
                    .wxGrotesk(32, tabular: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(context.isStale ? String(localized: "Open Widgetdeck for the next block") : context.attributes.title)
                    .wxLabel(color: WXColor.inkSecondary)
                    .lineLimit(1)
            }
            .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 116)
        .accessibilityElement(children: .combine)
        .activityBackgroundTint(WXColor.labelIvory)
        .activitySystemActionForegroundColor(WXColor.ink)
        .widgetURL(FocusDeepLink.url)
    }
}

/// Dynamic Island: compact (paint key + countdown), minimal (paint key) and expanded
/// (key, "FOCUS · 2 OF 4", the task, a large countdown and the progress bar), per LockScreen.png.
public enum FocusIsland {
    @MainActor
    public static func make(context: ActivityViewContext<FocusActivityAttributes>) -> DynamicIsland {
        let paint = islandColor(context.attributes.paint)
        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                PaintKey(color: paint, size: 44)
                    .padding(.leading, 6)
                    .padding(.top, 6)
            }
            DynamicIslandExpandedRegion(.center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(focusCaption(context.attributes, context.state, isStale: context.isStale, short: true))
                        .wxLabel(color: Color(white: 0.75))
                        .lineLimit(1)
                    Text(context.attributes.title)
                        .font(WXFont.title(17))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            DynamicIslandExpandedRegion(.trailing) {
                FocusCountdown(state: context.state, isStale: context.isStale)
                    .font(WXFont.headline(34))
                    .monospacedDigit()
                    .foregroundStyle(paint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 110, alignment: .trailing)
                    .padding(.top, 6)
            }
            DynamicIslandExpandedRegion(.bottom) {
                FocusProgressBar(state: context.state, fill: paint, track: Color(white: 0.25))
                    .padding(.horizontal, 6)
                    .padding(.top, 10)
            }
        } compactLeading: {
            PaintKey(color: paint, size: 18)
        } compactTrailing: {
            FocusCountdown(state: context.state, isStale: context.isStale)
                .font(WXFont.title(15))
                .monospacedDigit()
                .foregroundStyle(paint)
                .frame(width: 48)
        } minimal: {
            PaintKey(color: paint, size: 18)
        }
        .keylineTint(paint)
        .widgetURL(FocusDeepLink.url)
    }

    /// Deep Tide is too dark on the black island; it reads as Label Ivory there instead.
    static func islandColor(_ paint: CoursePaint) -> Color {
        paint == .tide ? WXColor.labelIvory : paint.color
    }
}

/// A rounded paint square with a punch hole (the mockup's island key).
private struct PaintKey: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color)
            .overlay(alignment: .topLeading) {
                if size > 30 {
                    Circle().fill(Color.black).frame(width: size * 0.18, height: size * 0.18)
                        .padding(size * 0.18)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
