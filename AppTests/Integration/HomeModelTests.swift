import CoreKit
import DesignSystem
import Foundation
import StudentFeatureWidgetKit
import Testing
@testable import WidgetX

@MainActor
@Suite("Home tab")
struct HomeModelTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: dayOffset, to: base)!
    }

    private func slot(_ code: String, start: Date, minutes: Double = 50, paint: CoursePaint = .coral) -> ClassSlot {
        ClassSlot(id: code + "\(start)", courseID: nil, code: code, location: "Room 3B",
                  start: start, end: start.addingTimeInterval(minutes * 60), paint: paint)
    }

    // MARK: Flow

    @Test func nextClassTodayShowsCountdownAndClass() {
        let flow = HomeModel.flow(classes: [slot("BIO 201", start: at(9, 0))], now: at(8, 46), calendar: calendar)
        #expect(flow.caption == "Flow · Next up · Room 3B")
        #expect(flow.value == "BIO 201")
        #expect(flow.trailing == "14 min")
        #expect(flow.progress != nil)
    }

    @Test func classInProgressShowsNowAndElapsedFraction() {
        let flow = HomeModel.flow(classes: [slot("CHEM 150", start: at(9, 0), minutes: 60, paint: .tide)],
                                  now: at(9, 30), calendar: calendar)
        #expect(flow.trailing == "Now")
        #expect(flow.value == "CHEM 150")
        #expect(abs((flow.progress ?? 0) - 0.5) < 0.01)
    }

    @Test func tomorrowsClassHasNoCountdown() {
        let flow = HomeModel.flow(classes: [slot("ENG 110", start: at(10, 0, dayOffset: 1), paint: .sand)],
                                  now: at(20, 0), calendar: calendar)
        #expect(flow.trailing == nil)
        #expect(flow.trend?.hasPrefix("Tomorrow") == true)
    }

    @Test func endedClassesAreSkipped() {
        let flow = HomeModel.flow(classes: [slot("BIO 201", start: at(8, 0))], now: at(12, 0), calendar: calendar)
        #expect(flow.value == "No classes coming up")
    }

    @Test func noStudentStoreInvitesToConnect() {
        #expect(HomeModel.flow(student: nil, now: .now).value == "Connect your calendar")
    }

    @Test func countdownFormatting() {
        #expect(HomeModel.countdown(14) == "14 min")
        #expect(HomeModel.countdown(65) == "1 h 5 min")
    }

    // MARK: Suggestion

    @Test func busyWeekWinsOverEverything() {
        let now = at(9, 0)
        let deadlines = [1, 2, 3].map { now.addingTimeInterval(Double($0) * 86_400) }
        let suggestion = HomeModel.suggestion(calendarLive: true, widgetCount: 0, hasTheme: false,
                                              deadlines: deadlines, now: now)
        #expect(suggestion?.kind == .deadlines)
    }

    @Test func suggestionPriorityWhenQuiet() {
        let now = at(9, 0)
        #expect(HomeModel.suggestion(calendarLive: false, widgetCount: 0, hasTheme: false, deadlines: [], now: now)?.kind == .addWidget)
        #expect(HomeModel.suggestion(calendarLive: false, widgetCount: 2, hasTheme: false, deadlines: [], now: now)?.kind == .connectCalendar)
        #expect(HomeModel.suggestion(calendarLive: true, widgetCount: 2, hasTheme: false, deadlines: [], now: now)?.kind == .matchWallpaper)
        #expect(HomeModel.suggestion(calendarLive: true, widgetCount: 2, hasTheme: true, deadlines: [], now: now) == nil)
    }

    @Test func unknownWidgetCountDoesNotSuggestAdding() {
        // Before the first WidgetCenter check finishes we don't know, so don't nag.
        let suggestion = HomeModel.suggestion(calendarLive: true, widgetCount: nil, hasTheme: true, deadlines: [], now: at(9, 0))
        #expect(suggestion == nil)
    }

    // MARK: Deck

    @Test func deckDedupesKindsCapsAtFourAndCounts() async {
        let ids = [WidgetKind.battery, .battery, .nextClass, .palette, .storage, .photo].map(\.kindIdentifier) + ["other.app.widget"]
        let model = HomeModel(detect: { .success(ids) }, activeTheme: { nil })
        await model.refreshWidgets()
        #expect(model.liveCount == 6)
        #expect(model.deckCards.map(\.name) == ["Battery", "Next Class", "Palette", "Storage"])
    }

    @Test func deckFollowsActiveTheme() async {
        let theme = ActiveThemeSnapshot(themeID: UUID(), name: "Ember", primary: .black, accent: .white)
        let model = HomeModel(detect: { .success([WidgetKind.battery.kindIdentifier]) }, activeTheme: { theme })
        await model.refreshWidgets()
        #expect(model.deckCards.first?.paint == "Ember")
        #expect(model.deckCards.first?.color == WidgetThemePaint.resolve(WXColor.deepTide, theme: theme))
    }

    @Test func eveningWidgetsUsePlumNotSage() {
        for kind in [WidgetKind.mood, .affirmation, .breathe] {
            let card = HomeModel.card(for: kind, theme: nil)
            #expect(card.color == WXColor.plumDusk)
            #expect(card.paint == WXSection.evening.paintName)
        }
        #expect(HomeModel.card(for: .habits, theme: nil).color == WXColor.sageNoon)
    }

    @Test func fanAnglesNarrowForFewerCards() {
        #expect(HomeModel.angles(for: 1) == [0])
        #expect(HomeModel.angles(for: 4) == [-27, -9, 9, 27])
    }
}
