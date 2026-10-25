import CoreKit
import DesignSystem
import SwiftUI
import WidgetKit

// MARK: - Paint

extension CoursePaint {
    /// The DesignSystem paint for this course.
    public var color: Color {
        switch self {
        case .coral: WXColor.coralHour
        case .sand: WXColor.beachSand
        case .tide: WXColor.deepTide
        case .sage: WXColor.sageNoon
        }
    }
}

// MARK: - Formatting

/// Short, locale-aware strings shared by the widgets and the app.
public enum ScheduleFormat {
    /// "9:00 AM" / "09:00".
    public static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "9:00 – 10:00 AM".
    public static func range(_ start: Date, _ end: Date) -> String {
        (start..<max(end, start)).formatted(.interval.hour().minute())
    }

    /// "Thu" (abbreviated weekday).
    public static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// "Tomorrow 9:00 AM" / "Mon 9:00 AM" for dates beyond today.
    public static func dayAndTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return time(date) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow \(time(date))")
        }
        return "\(weekday(date)) \(time(date))"
    }
}

/// Countdown that the system keeps current ("in 14 min"). Uses the iOS 18 reference format when
/// available (hours and minutes only) and falls back to the iOS 17 `.relative` style.
///
/// `sampleNow` is set only for the widget-gallery sample: its times are a fixed morning, so a live
/// countdown against the real clock would read "11 hours ago". It renders static text instead.
struct CountdownText: View {
    let target: Date
    var sampleNow: Date? = nil

    var body: some View {
        if let sampleNow {
            Text("in \(max(0, Int(target.timeIntervalSince(sampleNow) / 60))) min")
        } else if #available(iOS 18, *) {
            Text(.currentDate, format: .reference(to: target, allowedFields: [.hour, .minute]))
        } else {
            Text("in \(Text(target, style: .relative))")
        }
    }
}

// MARK: - Timeline

public struct StudentScheduleEntry: TimelineEntry, Sendable {
    public var date: Date
    public var moment: ScheduleMoment
    public var isStale: Bool
    /// Gallery / placeholder sample (fixed times); countdowns render statically.
    public var isSample: Bool

    public init(date: Date, moment: ScheduleMoment, isStale: Bool = false, isSample: Bool = false) {
        self.date = date
        self.moment = moment
        self.isStale = isStale
        self.isSample = isSample
    }

    /// Smart Stack hint: near and during class (see `ScheduleTimeline.relevanceScore`).
    public var relevance: TimelineEntryRelevance? {
        isSample ? nil : TimelineEntryRelevance(score: ScheduleTimeline.relevanceScore(moment))
    }
}

/// Timeline provider shared by both Student widgets. Reads the App Group snapshot only (Platform
/// Reality Rule 6); never touches EventKit or the network.
public struct StudentScheduleProvider<Snapshot: ClassScheduleSnapshot>: TimelineProvider {
    private let read: @Sendable () -> Snapshot?

    public init(read: @escaping @Sendable () -> Snapshot? = { SnapshotStore().read(Snapshot.self) }) {
        self.read = read
    }

    public func placeholder(in context: Context) -> StudentScheduleEntry {
        Self.sampleEntry(now: .now)
    }

    public func getSnapshot(in context: Context, completion: @escaping (StudentScheduleEntry) -> Void) {
        if context.isPreview, read() == nil {
            completion(Self.sampleEntry(now: .now))
        } else {
            completion(entries(now: .now).first ?? Self.sampleEntry(now: .now))
        }
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<StudentScheduleEntry>) -> Void) {
        let now = Date.now
        let snapshot = read()
        let age = snapshot.map { Int(now.timeIntervalSince($0.generatedAt) / 60) }
        let leaveBys = snapshot?.classes.filter { $0.leaveBy != nil && $0.end > now }.count ?? 0
        SyncTrace.log("timeline \(Snapshot.kind.rawValue) snapshot=\(age.map { "\($0)m old" } ?? "missing") leaveBy=\(leaveBys)")
        completion(Timeline(entries: entries(now: now, snapshot: snapshot),
                            policy: .after(ScheduleTimeline.reloadDate(classes: snapshot?.classes, now: now))))
    }

    func entries(now: Date) -> [StudentScheduleEntry] { entries(now: now, snapshot: read()) }

    func entries(now: Date, snapshot: Snapshot?) -> [StudentScheduleEntry] {
        ScheduleTimeline.moments(classes: snapshot?.classes, now: now).map {
            StudentScheduleEntry(date: $0.date, moment: $0, isStale: snapshot?.isStale(at: $0.date, threshold: 36 * 60 * 60) ?? false)
        }
    }

    /// Gallery / placeholder content: the mockup's morning, 14 minutes before BIO 201. Anchored to a
    /// fixed 8:46 AM on `now`'s day so the widget gallery never shows evening times or an empty day.
    public static func sampleEntry(now: Date) -> StudentScheduleEntry {
        let morning = SampleSchedule.at(hour: 8, minute: 46, on: now)
        let classes = SampleSchedule.day(around: now)
        let moment = ScheduleTimeline.moment(at: morning, sorted: classes)
        return StudentScheduleEntry(date: morning, moment: moment, isSample: true)
    }
}

/// Sample classes for widget previews and the gallery (never written to a snapshot).
/// Fixed times of day matching the mockup's week grid (Student.png).
public enum SampleSchedule {
    public static func day(around now: Date) -> [ClassSlot] {
        func slot(_ id: String, _ code: String, _ room: String, _ h: Int, _ m: Int, minutes: Double, _ paint: CoursePaint) -> ClassSlot {
            let start = at(hour: h, minute: m, on: now)
            return ClassSlot(id: "sample-\(id)", courseID: nil, code: code, location: room,
                             start: start, end: start.addingTimeInterval(minutes * 60), paint: paint)
        }
        return [
            slot("bio", "BIO 201", "Room 3B", 9, 0, minutes: 50, .coral),
            slot("eng", "ENG 110", "Hall A", 10, 0, minutes: 50, .sand),
            slot("chem", "CHEM 150", "Hall C", 11, 0, minutes: 75, .tide),
            slot("psy", "PSY 101", "Room 12", 13, 0, minutes: 50, .sage),
            slot("lab", "CHEM LAB", "Lab 2", 14, 0, minutes: 90, .tide),
        ]
    }

    static func at(hour: Int, minute: Int, on day: Date) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

// MARK: - Next Class

/// Next Class widget: small, medium (the mockup's Flow chip) and Lock Screen rectangular.
public struct NextClassWidgetView: View {
    @Environment(\.widgetFamily) private var family
    private let entry: StudentScheduleEntry

    public init(entry: StudentScheduleEntry) {
        self.entry = entry
    }

    private var slot: ClassSlot? { entry.moment.featured }

    public var body: some View {
        content
            .widgetURL(StudentDeepLink.url(course: slot?.courseID))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .systemMedium:
            PaintChipWidget(axis: .horizontal, color: slot?.paint.color ?? WXSection.student.color, field: .fixed(128), punchHole: .medium) {
                ClockGlyph(size: 46, lineWidth: 2.6)
            } label: {
                band(valueSize: 25, padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16), twoLines: true)
            }
            .accessibilityElement(children: .combine)
        default:
            PaintChipWidget(color: slot?.paint.color ?? WXSection.student.color, field: .fixed(76)) {
                ClockGlyph(size: 34, lineWidth: 2.2)
            } label: {
                band(valueSize: 20, padding: EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 13), twoLines: false)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Caps / display / caps stack, like `ChipLabelBand`, with a live countdown as the value.
    private func band(valueSize: CGFloat, padding: EdgeInsets, twoLines: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let slot {
                Text(caption(for: slot)).wxLabel(color: WXColor.inkSecondary).lineLimit(1)
                VStack(alignment: .leading, spacing: 0) {
                    if twoLines { Text(slot.code).wxGrotesk(valueSize).lineLimit(1) }
                    value(for: slot).wxGrotesk(valueSize, tabular: true).lineLimit(1)
                }
                // Medium has room for the leave time and the place on their own lines; small shows one.
                ForEach(Array(trendLines(for: slot, twoLines: twoLines).enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .wxLabel(color: index == 0 && !slot.isInProgress(at: entry.date) ? WXColor.clayLink : WXColor.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text(entry.moment.hasData ? "Next class" : "Schedule").wxLabel(color: WXColor.inkSecondary)
                Text(entry.moment.hasData ? "No classes soon" : "Connect your calendar")
                    .wxGrotesk(min(valueSize, 20)).lineLimit(2)
                Text(entry.moment.hasData ? "Enjoy the break" : "Open Widgetdeck").wxLabel(color: WXColor.inkSecondary)
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func caption(for slot: ClassSlot) -> String {
        let prefix = slot.isInProgress(at: entry.date) ? String(localized: "Now") : String(localized: "Next class")
        // Small: the course is the caption (the countdown already says "next"); "Now" stays explicit.
        guard family != .systemMedium else { return prefix }
        return slot.isInProgress(at: entry.date) ? "\(prefix) · \(slot.code)" : slot.code
    }

    @ViewBuilder
    private func value(for slot: ClassSlot) -> some View {
        if slot.isInProgress(at: entry.date) {
            Text("ends \(Text(ScheduleFormat.time(slot.end)))")
        } else if Calendar.current.isDate(slot.start, inSameDayAs: entry.date) {
            CountdownText(target: slot.start, sampleNow: entry.isSample ? entry.date : nil)
        } else {
            Text(ScheduleFormat.dayAndTime(slot.start, now: entry.date))
        }
    }

    /// Caps lines under the value: leave time (if any) first, then the place. Small widgets get one.
    private func trendLines(for slot: ClassSlot, twoLines: Bool) -> [String] {
        if entry.isStale { return [String(localized: "Open Widgetdeck to refresh")] }
        var lines: [String] = []
        if let leave = leaveBy(for: slot) {
            lines.append(slot.leaveByIsEstimate == true
                ? String(localized: "Leave ~\(ScheduleFormat.time(leave)) est.")
                : String(localized: "Leave by \(ScheduleFormat.time(leave))"))
        }
        if let place = slot.shortLocation { lines.append(place) }
        return Array(lines.prefix(twoLines ? 2 : 1))
    }

    /// The class's user-set leave time, while it's still ahead and the class hasn't started.
    private func leaveBy(for slot: ClassSlot) -> Date? {
        guard let leave = slot.leaveBy, !slot.isInProgress(at: entry.date), leave > entry.date else { return nil }
        return leave
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let slot {
                // The leave time gets its own line: sharing the caption with the code cut it off ("Leave ~10:0…").
                Text([slot.code, slot.shortLocation].compactMap { $0 }.joined(separator: " · "))
                    .wxLabel(11, color: .primary).lineLimit(1)
                Group {
                    if slot.isInProgress(at: entry.date) {
                        Text("ends \(Text(ScheduleFormat.time(slot.end)))")
                    } else if Calendar.current.isDate(slot.start, inSameDayAs: entry.date) {
                        CountdownText(target: slot.start, sampleNow: entry.isSample ? entry.date : nil)
                    } else {
                        Text(ScheduleFormat.dayAndTime(slot.start, now: entry.date))
                    }
                }
                .font(WXFont.headline(22)).lineLimit(1).minimumScaleFactor(0.7)
                if let leave = leaveBy(for: slot) {
                    Text(slot.leaveByIsEstimate == true
                         ? String(localized: "Leave ~\(ScheduleFormat.time(leave)) est.")
                         : String(localized: "Leave by \(ScheduleFormat.time(leave))"))
                        .wxLabel(11, color: .primary).lineLimit(1)
                }
            } else {
                Text("Next class").wxLabel(11, color: .primary)
                Text(entry.moment.hasData ? "None soon" : "Connect calendar").font(WXFont.title(15)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Today's Schedule

/// Today's Schedule widget: medium (4 rows) and large (up to 8 rows).
public struct TodayScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    private let entry: StudentScheduleEntry

    public init(entry: StudentScheduleEntry) {
        self.entry = entry
    }

    private var rowLimit: Int { family == .systemLarge ? 8 : 4 }

    /// Today's classes that haven't ended yet; ended ones drop off at their end boundary.
    private var rows: [ClassSlot] { entry.moment.today.filter { $0.end > entry.date } }

    public var body: some View {
        PaintChipWidget(axis: family == .systemLarge ? .vertical : .horizontal,
                        color: rows.first?.paint.color ?? WXSection.student.color,
                        field: .fixed(family == .systemLarge ? 76 : 96),
                        punchHole: family == .systemLarge ? .regular : .medium) {
            ClockGlyph(size: family == .systemLarge ? 34 : 40, lineWidth: 2.4)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(caption).wxLabel(color: WXColor.inkSecondary).lineLimit(1)
                if rows.isEmpty {
                    Text(entry.moment.hasData ? "No more classes" : "Connect your calendar").wxGrotesk(20).lineLimit(2)
                    Text(entry.moment.hasData ? "Enjoy the break" : "Open Widgetdeck").wxLabel(color: WXColor.inkSecondary)
                } else {
                    ForEach(rows.prefix(rowLimit)) { slot in row(slot) }
                    if rows.count > rowLimit {
                        Text("+\(rows.count - rowLimit) more").wxLabel(color: WXColor.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .widgetURL(StudentDeepLink.url(course: rows.first?.courseID))
    }

    private var caption: String {
        let day = entry.date.formatted(.dateTime.weekday(.wide))
        if entry.isStale { return String(localized: "\(day) · open Widgetdeck to refresh") }
        return String(localized: "Today · \(day)")
    }

    private func row(_ slot: ClassSlot) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(slot.paint.color)
                .frame(width: 6, height: 22)
                .widgetAccentable()
            Text(slot.code).wxGrotesk(15).lineLimit(1)
            Spacer(minLength: 4)
            Text(slot.isInProgress(at: entry.date) ? String(localized: "Now") : ScheduleFormat.time(slot.start))
                .wxLabel(color: slot.isInProgress(at: entry.date) ? WXColor.clayLink : WXColor.inkSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slot.code), \(ScheduleFormat.range(slot.start, slot.end))\(slot.shortLocation.map { ", \($0)" } ?? "")")
    }
}
