import AppIntents
import CoreKit
import DesignSystem
import SwiftUI
import WidgetKit

// MARK: - Shared bits

/// The Wellness leaf from the tab bar (`M5 19c0-8 5-14 14-14 0 9-6 14-14 14z M5 19l8-8`), stroked.
public struct LeafGlyph: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(5, 19))
        path.addCurve(to: p(19, 5), control1: p(5, 11), control2: p(10, 5))
        path.addCurve(to: p(5, 19), control1: p(19, 14), control2: p(13, 19))
        path.closeSubpath()
        path.move(to: p(5, 19)); path.addLine(to: p(13, 11))
        return path
    }
}

/// Short copy shared by widgets and the app.
public enum WellnessCopy {
    /// "23-day streak" / "2-week streak".
    public static func streak(_ count: Int, unit: StreakUnit) -> String {
        switch unit {
        case .day: String(localized: "\(count)-day streak")
        case .week: String(localized: "\(count)-week streak")
        }
    }

    /// First word of a habit name for tight captions ("Water, 8 glasses" → "Water").
    public static func shortName(_ name: String) -> String {
        let word = name.split(separator: " ").first.map(String.init) ?? name
        return word.trimmingCharacters(in: .punctuationCharacters)
    }

    /// "2 of 3 today".
    public static func progress(done: Int, of total: Int) -> String { String(localized: "\(done) of \(total) today") }

    /// Caption candidates for the Habits widget, longest first: every name, then fewer names with a
    /// count of the rest ("Read · Water +1", "Read +2"), then "Habits". The widget shows the first
    /// one that fits on one line, so the caption never wraps.
    public static func habitCaptions(_ names: [String]) -> [String] {
        let short = names.map(shortName)
        var captions = short.indices.reversed().map { last in
            let shown = short[...last].joined(separator: " · ")
            let rest = short.count - last - 1
            return rest > 0 ? "\(shown) +\(rest)" : shown
        }
        captions.append(String(localized: "Habits"))
        return captions
    }
}

// MARK: - Habits (small, medium)

/// Habits widget: the mockup's Sage Noon chip with a CheckKey per habit. Each key is a
/// `Button(intent:)`, so ticking works right on the home screen (iOS 17 interactive widgets).
public struct HabitsWidgetView<Toggle: AppIntent>: View {
    @Environment(\.widgetFamily) private var family
    private let entry: HabitsEntry
    private let toggle: (UUID) -> Toggle

    /// - Parameter toggle: builds the intent that ticks a habit (defined in the widget extension).
    public init(entry: HabitsEntry, toggle: @escaping (UUID) -> Toggle) {
        self.entry = entry
        self.toggle = toggle
    }

    private var capacity: Int { family == .systemMedium ? 5 : 3 }
    private var items: [HabitWidgetItem] { Array((entry.snapshot?.dueItems ?? []).prefix(capacity)) }

    public var body: some View {
        PaintChipWidget(color: WXSection.wellness.color, field: .fixed(86)) {
            HStack(spacing: family == .systemMedium ? 12 : 8) {
                ForEach(items) { item in
                    Button(intent: toggle(item.id)) { CheckKey(isOn: item.isDone, size: 38) }
                        .buttonStyle(.plain)
                        .invalidatableContent()
                        .accessibilityLabel(item.name)
                        .accessibilityValue(item.isDone ? String(localized: "Done") : String(localized: "Not done"))
                }
            }
            .padding(.top, 8)
            .widgetAccentable()
        } label: {
            band
        }
        .widgetURL(WellnessDeepLink.url())
    }

    @ViewBuilder
    private var band: some View {
        if let snapshot = entry.snapshot, !snapshot.items.isEmpty {
            if items.isEmpty {
                ChipLabelBand(caption: String(localized: "Habits"), value: String(localized: "Rest day"), valueSize: 20)
            } else {
                // ViewThatFits compares each band's one-line (ideal) width, so it skips captions that would wrap.
                ViewThatFits(in: .horizontal) {
                    let captions = WellnessCopy.habitCaptions(items.map(\.name))
                    ForEach(captions.indices, id: \.self) { index in
                        let caption = captions[index]
                        ChipLabelBand(caption: caption,
                                      value: WellnessCopy.progress(done: snapshot.doneCount, of: snapshot.dueItems.count),
                                      trend: family == .systemMedium ? trend(snapshot) : nil,
                                      trendColor: WXColor.mossPositive, tabular: true)
                    }
                }
            }
        } else {
            ChipLabelBand(caption: String(localized: "Habits"), value: String(localized: "Add a habit"),
                          trend: String(localized: "Open Widgetdeck"), valueSize: 20)
        }
    }

    private func trend(_ snapshot: HabitsSnapshot) -> String? {
        snapshot.topStreak.map { "\($0.name) · \(WellnessCopy.streak($0.streak, unit: $0.unit))" }
    }
}

// MARK: - Streak (accessoryCircular, accessoryInline)

/// Lock Screen streak: the leaf over the longest current streak ("23"), or an inline line
/// ("Read 20 min · 23-day streak").
public struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    private let entry: HabitsEntry

    public init(entry: HabitsEntry) {
        self.entry = entry
    }

    private var top: HabitWidgetItem? { entry.snapshot?.topStreak }
    private var name: String { entry.isSample ? WellnessSamples.streakName : (top?.name ?? "") }

    public var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                if let top {
                    Text("\(name) · \(WellnessCopy.streak(top.streak, unit: top.unit))")
                } else {
                    Text("Start a streak today")
                }
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        LeafGlyph()
                            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .frame(width: 16, height: 16)
                        Text(top.map { "\($0.streak)" } ?? "0")
                            .font(WXFont.headline(22))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .padding(6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(top.map { "\(name), \(WellnessCopy.streak($0.streak, unit: $0.unit))" } ?? String(localized: "No streak yet"))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(WellnessDeepLink.url(habit: top?.id))
    }
}

// MARK: - Mood (small, accessoryCircular)

/// Mood widget: five rising Plum Dusk capsules (the mockup's MoodKeys `.capsules`), each a
/// `Button(intent:)` that logs today's mood.
public struct MoodWidgetView<Log: AppIntent>: View {
    @Environment(\.widgetFamily) private var family
    private let entry: MoodWidgetEntry
    private let log: (Mood) -> Log

    public init(entry: MoodWidgetEntry, log: @escaping (Mood) -> Log) {
        self.entry = entry
        self.log = log
    }

    public var body: some View {
        switch family {
        case .accessoryCircular: circular
        default: small
        }
    }

    private var small: some View {
        PaintChipWidget(color: WXSection.evening.color, field: .fixed(96)) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Mood.allCases) { mood in
                    Button(intent: log(mood)) {
                        Capsule(style: .continuous)
                            .fill(WXColor.moodTintsOnPlum[mood.rawValue])
                            .frame(width: 24, height: CGFloat(28 + mood.rawValue * 8))
                            .overlay {
                                if entry.mood == mood {
                                    Capsule(style: .continuous).strokeBorder(WXColor.labelIvory, lineWidth: 3).padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .invalidatableContent()
                    .accessibilityLabel(String(localized: "Log mood: \(mood.word)"))
                    .accessibilityAddTraits(entry.mood == mood ? .isSelected : [])
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 16)
            .widgetAccentable()
        } label: {
            ChipLabelBand(caption: caption,
                          value: entry.mood.map { String(localized: "Logged: \($0.word)") } ?? String(localized: "How was today?"),
                          valueSize: 20, padding: EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13))
        }
        .widgetURL(WellnessDeepLink.url(mood: true))
    }

    /// The paint name is only true while no theme recolours the field.
    private var caption: String {
        entry.isSample || ActiveThemeStore().read() == nil ? "\(WXSection.evening.paintName) · \(String(localized: "Mood"))" : String(localized: "Mood")
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let mood = entry.mood {
                Gauge(value: Double(mood.rawValue + 1), in: 0...5) {
                    Text("Mood")
                } currentValueLabel: {
                    Text(mood.word).font(WXFont.label(9)).minimumScaleFactor(0.6)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                VStack(spacing: 0) {
                    Text("Mood").font(WXFont.label(9))
                    Text("Log").font(WXFont.headline(18))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.mood.map { String(localized: "Mood today: \($0.word)") } ?? String(localized: "Log today's mood"))
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(WellnessDeepLink.url(mood: true))
    }
}

// MARK: - Daily Quote (small, medium, accessoryRectangular)

public struct QuoteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    private let entry: DailyContentEntry

    public init(entry: DailyContentEntry) {
        self.entry = entry
    }

    public var body: some View {
        content
            .widgetURL(WellnessDeepLink.url())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.quote.text) \(entry.quote.author)")
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.quote.text).font(WXFont.body(13, weight: .medium)).lineLimit(3).minimumScaleFactor(0.8)
                Text(entry.quote.author).wxLabel(9, color: .primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            PaintChipWidget(axis: .horizontal, color: WXSection.wellness.color, field: .fixed(96), punchHole: .medium) {
                LeafGlyph()
                    .stroke(WXColor.labelIvory, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 40, height: 40)
            } label: {
                quoteBand(textSize: 17, lines: 5)
            }
        default:
            PaintChipWidget(color: WXSection.wellness.color, field: .fixed(34), punchHole: .small) {
                Color.clear
            } label: {
                quoteBand(textSize: 14, lines: 5)
            }
        }
    }

    private func quoteBand(textSize: CGFloat, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.quote.text)
                .wxGrotesk(textSize)
                .lineLimit(lines)
                .minimumScaleFactor(0.7)
            Text(entry.quote.author).wxLabel(10).lineLimit(1)
        }
        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Affirmation (small, accessoryInline)

public struct AffirmationWidgetView: View {
    @Environment(\.widgetFamily) private var family
    private let entry: DailyContentEntry

    public init(entry: DailyContentEntry) {
        self.entry = entry
    }

    public var body: some View {
        Group {
            if family == .accessoryInline {
                Text(entry.affirmation.text)
                    .containerBackground(for: .widget) { Color.clear }
            } else {
                PaintChipWidget(color: WXSection.evening.color, field: .fixed(34), punchHole: .small) {
                    Color.clear
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Today").wxLabel(10)
                        Text(entry.affirmation.text).wxGrotesk(16).lineLimit(5).minimumScaleFactor(0.7)
                    }
                    .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .widgetURL(WellnessDeepLink.url())
    }
}

// MARK: - Breathe shortcut (small)

/// The Wellness screen's breathing chip as a widget; tap starts a box-breathing session.
public struct BreatheWidgetView: View {
    public init() {}

    public var body: some View {
        PaintChipWidget(color: WXSection.evening.color, field: .fixed(86)) {
            BoxBreathGlyph(size: 46).padding(.top, 6)
        } label: {
            ChipLabelBand(caption: String(localized: "Box breathing"), value: String(localized: "3 minutes"), trend: String(localized: "Tap to start"))
        }
        .widgetURL(WellnessDeepLink.url(breathe: .box))
    }
}
