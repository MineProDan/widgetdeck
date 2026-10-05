import CoreKit
import DesignSystem
import SwiftUI
import WidgetKit

/// One open deadline as widgets see it: an assignment (S-05) or a calendar deadline (S-02).
public struct DueSlot: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var code: String?
    public var courseID: UUID?
    public var due: Date
    public var paint: CoursePaint

    public init(id: String, title: String, code: String?, courseID: UUID?, due: Date, paint: CoursePaint) {
        self.id = id
        self.title = title
        self.code = code
        self.courseID = courseID
        self.due = due
        self.paint = paint
    }
}

/// Feeds the Assignments Due widget (medium, large, accessoryRectangular).
public struct AssignmentsSnapshot: WidgetSnapshot {
    public static var kind: WidgetKind { .assignments }
    public static let maxItems = 20
    public var items: [DueSlot]
    public var generatedAt: Date

    public init(items: [DueSlot], generatedAt: Date) {
        self.items = Array(items.sorted { ($0.due, $0.id) < ($1.due, $1.id) }.prefix(Self.maxItems))
        self.generatedAt = generatedAt
    }
}

public struct AssignmentsEntry: TimelineEntry, Sendable {
    public var date: Date
    /// Items not yet past due at `date`; `nil` = no snapshot yet.
    public var items: [DueSlot]?
    public var isStale: Bool

    public init(date: Date, items: [DueSlot]?, isStale: Bool = false) {
        self.date = date
        self.items = items
        self.isStale = isStale
    }
}

/// Timeline: one entry now plus one at each due date in the next 24 h, so passed items drop off.
public struct AssignmentsProvider: TimelineProvider {
    private let read: @Sendable () -> AssignmentsSnapshot?

    public init(read: @escaping @Sendable () -> AssignmentsSnapshot? = { SnapshotStore().read(AssignmentsSnapshot.self) }) {
        self.read = read
    }

    public func placeholder(in context: Context) -> AssignmentsEntry { Self.sample(now: .now) }

    public func getSnapshot(in context: Context, completion: @escaping (AssignmentsEntry) -> Void) {
        let snapshot = read()
        if context.isPreview, snapshot == nil {
            completion(Self.sample(now: .now))
        } else {
            completion(Self.entries(snapshot: snapshot, now: .now).first ?? Self.sample(now: .now))
        }
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<AssignmentsEntry>) -> Void) {
        let now = Date.now
        completion(Timeline(entries: Self.entries(snapshot: read(), now: now), policy: .after(now.addingTimeInterval(24 * 3600))))
    }

    public static func entries(snapshot: AssignmentsSnapshot?, now: Date) -> [AssignmentsEntry] {
        guard let snapshot else { return [AssignmentsEntry(date: now, items: nil)] }
        let horizon = now.addingTimeInterval(24 * 3600)
        let dates = [now] + snapshot.items.map(\.due).filter { $0 > now && $0 <= horizon }
        return Set(dates).sorted().map { date in
            AssignmentsEntry(date: date, items: snapshot.items.filter { $0.due > date },
                             isStale: snapshot.isStale(at: date, threshold: 36 * 3600))
        }
    }

    public static func sample(now: Date) -> AssignmentsEntry {
        let day: TimeInterval = 86_400
        return AssignmentsEntry(date: now, items: [
            DueSlot(id: "s1", title: "Lab report", code: "CHEM 150", courseID: nil, due: now.addingTimeInterval(day * 0.8), paint: .tide),
            DueSlot(id: "s2", title: "Problem set 4", code: "BIO 201", courseID: nil, due: now.addingTimeInterval(day * 2), paint: .coral),
            DueSlot(id: "s3", title: "Essay draft", code: "ENG 110", courseID: nil, due: now.addingTimeInterval(day * 4), paint: .sand),
            DueSlot(id: "s4", title: "Reading notes", code: "PSY 101", courseID: nil, due: now.addingTimeInterval(day * 6), paint: .sage),
        ])
    }
}

/// Assignments Due: medium (3 rows), large (7 rows), Lock Screen rectangular (the next one).
public struct AssignmentsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    private let entry: AssignmentsEntry

    public init(entry: AssignmentsEntry) {
        self.entry = entry
    }

    private var items: [DueSlot] { entry.items ?? [] }
    private var rowLimit: Int { family == .systemLarge ? 7 : 3 }

    public var body: some View {
        if family == .accessoryRectangular {
            rectangular
        } else {
            PaintChipWidget(axis: family == .systemLarge ? .vertical : .horizontal,
                            color: items.first?.paint.color ?? WXSection.student.color,
                            field: .fixed(family == .systemLarge ? 76 : 96),
                            punchHole: family == .systemLarge ? .regular : .medium) {
                CheckKey(isOn: false, size: family == .systemLarge ? 34 : 40)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(caption).wxLabel(color: WXColor.inkSecondary).lineLimit(1)
                    if items.isEmpty {
                        Text(entry.items == nil ? "Open Widgetdeck" : "All caught up").wxGrotesk(20).lineLimit(2)
                        Text(entry.items == nil ? "Add assignments in Student" : "Nothing due").wxLabel(color: WXColor.inkSecondary)
                    } else {
                        ForEach(items.prefix(rowLimit)) { row($0) }
                        if items.count > rowLimit {
                            Text("+\(items.count - rowLimit) more").wxLabel(color: WXColor.inkSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .widgetURL(StudentDeepLink.url(course: items.first?.courseID))
        }
    }

    private var caption: String {
        entry.isStale ? String(localized: "Due · open Widgetdeck to refresh") : String(localized: "Due soon")
    }

    private func row(_ item: DueSlot) -> some View {
        let urgent = item.due.timeIntervalSince(entry.date) < 36 * 3600
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(item.paint.color)
                .frame(width: 6, height: 22)
                .widgetAccentable()
            Text(item.title).wxGrotesk(15).lineLimit(1)
            Spacer(minLength: 4)
            Text(ScheduleFormat.shortDue(item.due, now: entry.date))
                .wxLabel(color: urgent ? WXColor.clayLink : WXColor.inkSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title)\(item.code.map { ", \($0)" } ?? ""), due \(ScheduleFormat.dayAndTime(item.due, now: entry.date))")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let first = items.first {
                Text([first.code, ScheduleFormat.shortDue(first.due, now: entry.date)].compactMap { $0 }.joined(separator: " · "))
                    .wxLabel(11, color: .primary).lineLimit(1)
                Text(first.title).font(WXFont.headline(20)).lineLimit(1).minimumScaleFactor(0.7)
                if items.count > 1 {
                    Text("+\(items.count - 1) more due").font(WXFont.body(12)).lineLimit(1)
                }
            } else {
                Text("Due soon").wxLabel(11, color: .primary)
                Text(entry.items == nil ? "Open Widgetdeck" : "All caught up").font(WXFont.title(15)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        .accessibilityElement(children: .combine)
        .widgetURL(StudentDeepLink.url(course: items.first?.courseID))
    }
}

extension ScheduleFormat {
    /// "9:00 AM" today, "Tomorrow", "Thu" within a week, else "Oct 12".
    public static func shortDue(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return time(date) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        if date.timeIntervalSince(now) < 6 * 86_400 { return weekday(date) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
