import CoreKit
import Foundation
import os
import UserNotifications
import WellnessFeatureWidgetKit

/// Schedules the mood reminder. A protocol so tests (which have no notification center) can stub it.
public protocol MoodReminding: Sendable {
    func requestAuthorization() async -> Bool
    func reschedule(enabled: Bool, hour: Int, loggedDays: Set<DayKey>, clock: WellnessDayClock, now: Date) async
}

/// Optional evening mood reminder (W-03), default 8 PM. Schedules a rolling week of one-off
/// notifications and skips days already logged, so nobody is nudged after checking in.
/// Uses 7 of iOS's 64 pending-notification slots (Student keeps its reminders to 48).
public struct MoodReminderScheduler: MoodReminding {
    public static let identifierPrefix = "wellness.mood."
    public static let days = 7
    private static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Wellness")

    public init() {}

    /// The fire dates for the next week, skipping logged days and times already past.
    public static func plan(hour: Int, loggedDays: Set<DayKey>, clock: WellnessDayClock, now: Date) -> [(day: DayKey, date: Date)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = clock.timeZone
        let today = clock.day(for: now)
        return (0..<days).compactMap { offset in
            let day = today.adding(days: offset)
            guard !loggedDays.contains(day),
                  let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour)),
                  date > now else { return nil }
            return (day, date)
        }
    }

    public func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    public func reschedule(enabled: Bool, hour: Int, loggedDays: Set<DayKey>, clock: WellnessDayClock, now: Date) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        for (day, date) in Self.plan(hour: hour, loggedDays: loggedDays, clock: clock, now: now) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "How was today?")
            content.body = String(localized: "One tap to log your mood.")
            content.userInfo = ["url": WellnessDeepLink.url(mood: true).absoluteString]
            var components = Calendar.current.dateComponents(in: clock.timeZone, from: date)
            components.nanosecond = nil
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: Self.identifierPrefix + day.description, content: content, trigger: trigger))
            } catch {
                Self.logger.error("Mood reminder not scheduled: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
