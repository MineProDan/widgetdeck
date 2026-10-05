import DesignSystem
import StudentFeatureWidgetKit
import SwiftUI

/// Layout of the week grid, computed from the classes (pure, so it's testable).
struct WeekGridLayout: Equatable {
    /// Monday of the displayed week.
    var monday: Date
    /// Monday-based day indices to show (Mon–Fri, plus weekend days that have classes).
    var days: [Int]
    var firstHour: Int
    var lastHour: Int
    /// Monday-based index of today, if today is in the displayed week.
    var todayIndex: Int?

    static func make(classes: [ClassSlot], now: Date, calendar: Calendar = .current) -> WeekGridLayout {
        var monday = WeekMath.monday(of: now, calendar: calendar)
        let todayIndex = WeekMath.weekdayIndex(now, calendar: calendar)
        // On weekends with no weekend classes, look ahead to the coming week.
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        let thisWeek = classes.filter { $0.start >= monday && $0.start < weekEnd }
        let hasWeekendClass = thisWeek.contains { WeekMath.weekdayIndex($0.start, calendar: calendar) >= 5 }
        var showsToday = true
        if todayIndex >= 5 && !hasWeekendClass {
            monday = weekEnd
            showsToday = false
        }
        let end = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        let week = classes.filter { $0.start >= monday && $0.start < end }
        let weekendDays = Set(week.map { WeekMath.weekdayIndex($0.start, calendar: calendar) }.filter { $0 >= 5 })
        let days = Array(0...4) + weekendDays.sorted()

        let startHours = week.map { calendar.component(.hour, from: $0.start) }
        let endHours = week.map { slot -> Int in
            let hour = calendar.component(.hour, from: slot.end)
            let minute = calendar.component(.minute, from: slot.end)
            let sameDay = calendar.isDate(slot.end, inSameDayAs: slot.start)
            return sameDay ? hour + (minute > 0 ? 1 : 0) : 24
        }
        let first = min(startHours.min() ?? 8, 8)
        let last = max(endHours.max() ?? 16, first + 8)
        return WeekGridLayout(monday: monday, days: days, firstHour: first, lastHour: min(last, 24),
                              todayIndex: showsToday && days.contains(todayIndex) ? todayIndex : nil)
    }
}

/// The Schedule week grid from Student.png: 30 pt hour column, 36 pt per hour, today's column
/// tinted Coral Hour 8 %, a 2 pt Clay Link "now" line, `ClassBlock`s in course paints.
struct WeekGridView: View {
    let classes: [ClassSlot]
    let now: Date
    var onSelect: (ClassSlot) -> Void

    private let hour: CGFloat = 36
    private let hourColumn: CGFloat = 30
    private let header: CGFloat = 30
    private let calendar = Calendar.current

    var body: some View {
        let layout = WeekGridLayout.make(classes: classes, now: now, calendar: calendar)
        let rows = layout.lastHour - layout.firstHour
        GeometryReader { proxy in
            let columnWidth = (proxy.size.width - hourColumn) / CGFloat(layout.days.count)
            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.days.enumerated()), id: \.offset) { column, day in
                    let isToday = day == layout.todayIndex
                    Text(dayLabel(layout, day))
                        .wxLabel(color: isToday ? WXColor.labelIvory : WXColor.inkSecondary)
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(isToday ? WXColor.ink : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .frame(width: columnWidth)
                        .offset(x: hourColumn + CGFloat(column) * columnWidth)
                }
                ZStack(alignment: .topLeading) {
                    ForEach(0..<rows, id: \.self) { index in
                        WXColor.rule.frame(height: 1).offset(y: CGFloat(index) * hour)
                        Text(hourLabel(layout.firstHour + index)).wxLabel(10, color: WXColor.inkInactive).monospacedDigit()
                            .offset(y: CGFloat(index) * hour + 3)
                    }
                    if let today = layout.todayIndex, let column = layout.days.firstIndex(of: today) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(WXColor.coralHour.opacity(0.08))
                            .frame(width: columnWidth - 0.4, height: CGFloat(rows) * hour + 4)
                            .offset(x: hourColumn + CGFloat(column) * columnWidth - 1)
                    }
                    ForEach(blocks(layout)) { placed in
                        Button { onSelect(placed.slot) } label: {
                            ClassBlock(code: placed.slot.code, color: placed.slot.paint.color)
                        }
                        .buttonStyle(.plain)
                        .frame(width: columnWidth - 4.4, height: max(placed.height * hour - 4, 22))
                        .offset(x: hourColumn + 2 + CGFloat(placed.column) * columnWidth, y: placed.top * hour + 2)
                        .accessibilityLabel("\(placed.slot.code), \(ScheduleFormat.weekday(placed.slot.start)) \(ScheduleFormat.range(placed.slot.start, placed.slot.end))")
                    }
                    if let y = nowOffset(layout), let today = layout.todayIndex, let column = layout.days.firstIndex(of: today) {
                        let x = hourColumn + CGFloat(column) * columnWidth
                        WXColor.clayLink.frame(width: columnWidth + 4, height: 2).offset(x: x - 5, y: y * hour - 1)
                        Circle().fill(WXColor.clayLink).frame(width: 10, height: 10).offset(x: x - 9, y: y * hour - 5)
                            .accessibilityHidden(true)
                    }
                }
                .offset(y: header)
            }
        }
        .frame(height: header + CGFloat(rows) * hour)
        // A dense chart: it keeps its geometry; accessibility sizes get the list instead (see section view).
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private struct Placed: Identifiable {
        var slot: ClassSlot
        var column: Int
        var top: CGFloat
        var height: CGFloat
        var id: String { slot.id }
    }

    private func blocks(_ layout: WeekGridLayout) -> [Placed] {
        classes.compactMap { slot in
            let dayOffset = calendar.dateComponents([.day], from: layout.monday, to: calendar.startOfDay(for: slot.start)).day ?? -1
            guard let column = layout.days.firstIndex(of: dayOffset) else { return nil }
            let top = fractionalHour(slot.start) - CGFloat(layout.firstHour)
            let end = calendar.isDate(slot.end, inSameDayAs: slot.start) ? fractionalHour(slot.end) : 24
            let clampedTop = max(top, 0)
            let bottom = min(end - CGFloat(layout.firstHour), CGFloat(layout.lastHour - layout.firstHour))
            guard bottom > clampedTop else { return nil }
            return Placed(slot: slot, column: column, top: clampedTop, height: bottom - clampedTop)
        }
    }

    private func fractionalHour(_ date: Date) -> CGFloat {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return CGFloat(parts.hour ?? 0) + CGFloat(parts.minute ?? 0) / 60
    }

    private func nowOffset(_ layout: WeekGridLayout) -> CGFloat? {
        let value = fractionalHour(now) - CGFloat(layout.firstHour)
        return value >= 0 && value <= CGFloat(layout.lastHour - layout.firstHour) ? value : nil
    }

    private func dayLabel(_ layout: WeekGridLayout, _ index: Int) -> String {
        let date = calendar.date(byAdding: .day, value: index, to: layout.monday) ?? layout.monday
        return ScheduleFormat.weekday(date)
    }

    private func hourLabel(_ hour: Int) -> String {
        // Bare numerals like the mockup ("8 … 12, 1, 2"): 12-hour or 24-hour per the locale.
        let uses12Hour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true
        guard uses12Hour else { return "\(hour % 24)" }
        let value = hour % 12
        return "\(value == 0 ? 12 : value)"
    }
}
