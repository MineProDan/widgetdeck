import BackgroundTasks
import CoreKit
import UIKit
import UserNotifications

/// Background task registration, CloudKit push registration and the notification delegate.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Must be registered before launch finishes.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppIdentifiers.backgroundRefreshTask, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handle(task)
        }
        UNUserNotificationCenter.current().delegate = self
        // Silent pushes let NSPersistentCloudKitContainer import changes promptly. No user prompt.
        application.registerForRemoteNotifications()
        return true
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let work = Task { @MainActor in
            await AppEnvironment.shared.performBackgroundRefresh()
            // If the system expired the task, the expiration handler already completed it.
            if !Task.isCancelled { task.setTaskCompleted(success: true) }
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Notifications may carry a deep link URL string under `deepLink` or `url`
    /// (Student reminders use `url`), e.g. `widgetx://section/student?course=<uuid>`.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let link = (userInfo["deepLink"] ?? userInfo["url"]) as? String,
              let url = URL(string: link) else { return }
        await MainActor.run { AppEnvironment.shared.handle(url: url) }
    }
}
