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

    // The completion-handler versions, not `async`: with the async ones iOS finishes the tap off the
    // main thread and UIKit crashes ("Call must be made on main thread"). Both complete on main.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        nonisolated(unsafe) let done = completionHandler
        DispatchQueue.main.async { done([.banner, .list, .sound]) }
    }

    /// Notifications may carry a deep link URL string under `deepLink` or `url`
    /// (Student reminders use `url`), e.g. `widgetx://section/student?course=<uuid>`.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let link = (userInfo["deepLink"] ?? userInfo["url"]) as? String
        nonisolated(unsafe) let done = completionHandler
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let link, let url = URL(string: link) { AppEnvironment.shared.handle(url: url) }
            }
            done()
        }
    }
}
