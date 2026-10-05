import CoreKit
import DesignSystem
import Foundation
import Observation
import StudentFeature
import StudentFeatureWidgetKit
import SwiftUI

/// Data for the Home tab. Pure helpers are `static` so they can be unit-tested without a store.
@MainActor
@Observable
final class HomeModel {
    struct DeckCard: Identifiable, Equatable {
        let id: String
        let color: Color
        let paint: String
        let name: String
    }

    /// What the Flow hero shows.
    struct Flow: Equatable {
        var color: Color
        var caption: String
        var value: String
        var trailing: String?
        var trend: String?
        /// 0...1 for the field bar; nil hides it.
        var progress: Double?
    }

    struct Suggestion: Equatable {
        enum Kind: Equatable { case connectCalendar, addWidget, matchWallpaper, deadlines }
        var kind: Kind
        var color: Color
        var caption: String
        var title: String
        var action: String
        var why: String
    }

    /// Widget kinds on the Home/Lock Screen (nil until the first check finishes).
    private(set) var widgetKinds: [WidgetKind]?
    private let detect: () async -> Result<[String], any Error>
    private let activeTheme: () -> ActiveThemeSnapshot?

    init(detect: @escaping () async -> Result<[String], any Error> = { await OnboardingModel.currentWidgetKinds() },
         activeTheme: @escaping () -> ActiveThemeSnapshot? = { ActiveThemeStore().read() }) {
        self.detect = detect
        self.activeTheme = activeTheme
    }

    func refreshWidgets() async {
        switch await detect() {
        case .success(let identifiers): widgetKinds = identifiers.compactMap(Self.kind(fromIdentifier:))
        case .failure: widgetKinds = widgetKinds ?? []
        }
    }

    var liveCount: Int { widgetKinds?.count ?? 0 }

    /// One card per distinct widget kind, in the order they were found, at most four (the fan).
    var deckCards: [DeckCard] {
        guard let widgetKinds else { return [] }
        let theme = activeTheme()
        var seen = Set<WidgetKind>()
        return widgetKinds.filter { seen.insert($0).inserted }.prefix(4).map { Self.card(for: $0, theme: theme) }
    }

    // MARK: Helpers

    static func kind(fromIdentifier identifier: String) -> WidgetKind? {
        WidgetKind.allCases.first { $0.kindIdentifier == identifier }
    }

    /// Card paint follows the section and the user's applied theme, so the deck matches the widgets.
    static func card(for kind: WidgetKind, theme: ActiveThemeSnapshot?) -> DeckCard {
        let section: WXSection = switch kind.section {
        case .tech: .tech
        case .student, nil: .student
        case .aesthetic: .aesthetic
        case .wellness: .wellness
        }
        return DeckCard(id: kind.rawValue,
                        color: WidgetThemePaint.resolve(section.color, theme: theme),
                        paint: theme?.name ?? section.paintName,
                        name: displayName(kind))
    }

    static func displayName(_ kind: WidgetKind) -> String {
        switch kind {
        case .welcome: "Widgetdeck"
        case .battery: "Battery"
        case .systemOverview: "Overview"
        case .storage: "Storage"
        case .nextClass: "Next Class"
        case .todaySchedule: "Today"
        case .assignments: "Assignments"
        case .photo: "Photo"
        case .palette: "Palette"
        case .moodBoard: "Mood Board"
        case .quote: "Quote"
        case .affirmation: "Affirmation"
        case .habits: "Habits"
        case .mood: "Mood"
        case .breathe: "Breathe"
        case .streak: "Streak"
        case .flow: "Flow"
        }
    }

    /// Fan angles from the mockup (4 cards: −27…27°), narrowed for fewer cards.
    static func angles(for count: Int) -> [Double] {
        switch count {
        case 0, 1: [0]
        case 2: [-9, 9]
        case 3: [-18, 0, 18]
        default: [-27, -9, 9, 27]
        }
    }

    /// Faded example shown before any widget is added (the mockup's deck).
    static let exampleCards = [
        DeckCard(id: "e-sage", color: WXColor.sageNoon, paint: "Sage Noon", name: "Habits"),
        DeckCard(id: "e-sand", color: WXColor.beachSand, paint: "Beach Hour", name: "Palette"),
        DeckCard(id: "e-tide", color: WXColor.deepTide, paint: "Deep Tide", name: "Battery"),
        DeckCard(id: "e-coral", color: WXColor.coralHour, paint: "Coral Hour", name: "Next Class")
    ]

    static func subtitle(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let greeting = hour < 12 ? "Morning" : hour < 18 ? "Afternoon" : "Evening"
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide)) + " · " + greeting
    }

    // MARK: Flow

    /// The hero: the class in progress or next up. Falls back to tomorrow's first class, then to an
    /// invitation to connect a calendar. Never shows sample classes (those live on the Student tab).
    static func flow(student: StudentStore?, now: Date, calendar: Calendar = .current) -> Flow {
        let paintColor = WXSection.student.color
        guard let student, student.mode == .live else {
            let picking = student?.mode == .needsCalendars
            return Flow(color: paintColor, caption: "Flow · Student",
                        value: picking ? "Pick your school calendars" : "Connect your calendar",
                        trailing: nil, trend: "Your next class shows up here", progress: nil)
        }
        return flow(classes: student.schedule.classes, now: now, calendar: calendar)
    }

    static func flow(classes: [ClassSlot], now: Date, calendar: Calendar = .current) -> Flow {
        let upcoming = classes.filter { $0.end > now }.sorted { $0.start < $1.start }
        guard let slot = upcoming.first else {
            return Flow(color: WXSection.student.color, caption: "Flow · Next up", value: "No classes coming up",
                        trailing: nil, trend: "Enjoy the free time", progress: nil)
        }
        // Headline = the class; the caption carries where it is.
        let paint = slot.code
        let place = slot.shortLocation ?? ""
        func caption(_ prefix: String) -> String { place.isEmpty ? prefix : prefix + " · " + place }
        let time = slot.start.formatted(date: .omitted, time: .shortened)

        if slot.start <= now {
            let total = slot.end.timeIntervalSince(slot.start)
            let done = total > 0 ? now.timeIntervalSince(slot.start) / total : 1
            return Flow(color: slot.paint.color, caption: caption("Flow · Now"), value: paint,
                        trailing: "Now", trend: "Until " + slot.end.formatted(date: .omitted, time: .shortened),
                        progress: min(max(done, 0), 1))
        }
        guard calendar.isDate(slot.start, inSameDayAs: now) else {
            let day = calendar.isDate(slot.start, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
                ? "Tomorrow" : slot.start.formatted(.dateTime.weekday(.wide))
            return Flow(color: slot.paint.color, caption: caption("Flow · Next up"), value: paint,
                        trailing: nil, trend: "\(day) \(time)", progress: nil)
        }
        let minutes = Int((slot.start.timeIntervalSince(now) / 60).rounded(.up))
        // The bar fills over the last two hours before class, like the mockup's "almost time" chip.
        let window: Double = 120
        return Flow(color: slot.paint.color, caption: caption("Flow · Next up"), value: paint,
                    trailing: countdown(minutes), trend: "Starts " + time,
                    progress: min(max(1 - Double(minutes) / window, 0), 1))
    }

    static func countdown(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    static func paintName(_ paint: CoursePaint) -> String {
        switch paint {
        case .coral: WXSection.student.paintName
        case .sand: WXSection.aesthetic.paintName
        case .tide: WXSection.tech.paintName
        case .sage: WXSection.wellness.paintName
        }
    }

    // MARK: Suggestion

    /// One suggestion, most useful first. Only suggests things the app can actually do today.
    func suggestion(student: StudentStore?, now: Date) -> Suggestion? {
        Self.suggestion(calendarLive: student?.mode == .live,
                        calendarNeedsPicking: student?.mode == .needsCalendars,
                        widgetCount: widgetKinds?.count,
                        hasTheme: activeTheme() != nil,
                        deadlines: student?.schedule.deadlines.filter { !$0.isDone }.map(\.due) ?? [],
                        now: now)
    }

    static func suggestion(calendarLive: Bool, calendarNeedsPicking: Bool = false, widgetCount: Int?, hasTheme: Bool, deadlines: [Date],
                           now: Date, calendar: Calendar = .current) -> Suggestion? {
        let weekAhead = now.addingTimeInterval(7 * 24 * 3600)
        let dueSoon = deadlines.filter { $0 > now && $0 <= weekAhead }.sorted()
        if dueSoon.count >= 3, let last = dueSoon.last {
            return Suggestion(kind: .deadlines, color: WXSection.student.color,
                              caption: "Busy week · \(dueSoon.count) deadlines by \(last.formatted(.dateTime.weekday(.abbreviated)))",
                              title: "See what's due", action: "Open",
                              why: "You have \(dueSoon.count) deadlines in your school calendars over the next 7 days.")
        }
        if widgetCount == 0 {
            return Suggestion(kind: .addWidget, color: WXSection.wellness.color,
                              caption: "Home Screen · nothing yet", title: "Add your first widget?", action: "How",
                              why: "Widgetdeck doesn't see any of its widgets on your Home Screen or Lock Screen yet.")
        }
        if !calendarLive && calendarNeedsPicking {
            return Suggestion(kind: .connectCalendar, color: WXSection.student.color,
                              caption: "Student · calendar connected", title: "Pick your school calendars?", action: "Choose",
                              why: "Widgetdeck can read your calendar, but you haven't chosen which calendars are for school yet.")
        }
        if !calendarLive {
            return Suggestion(kind: .connectCalendar, color: WXSection.student.color,
                              caption: "Student · sample week", title: "Connect your calendar?", action: "Connect",
                              why: "Your schedule and the Next Class widget use your school calendars. Widgetdeck only reads them.")
        }
        if !hasTheme {
            return Suggestion(kind: .matchWallpaper, color: WXSection.aesthetic.color,
                              caption: "Theme Sync · default colours", title: "Match my wallpaper?", action: "Try",
                              why: "Your widgets use the default colours. Theme Sync recolours them from a photo you pick.")
        }
        return nil
    }
}
