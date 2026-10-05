import CoreLocation
import EventKit
import Foundation
import Observation
import Photos
import UserNotifications

/// Permissions the app may ask for. **No HealthKit** (Phase 3 only).
public enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    /// Full read access to events (iOS 17 `requestFullAccessToEvents`). Key: `NSCalendarsFullAccessUsageDescription`.
    case calendar
    /// Full read access to reminders. Key: `NSRemindersFullAccessUsageDescription`.
    case reminders
    /// Photo library read access. Prefer `PhotosPicker`, which needs **no** permission; only
    /// request this for features that must re-read the library. Key: `NSPhotoLibraryUsageDescription`.
    case photos
    /// Local notifications (reminders, streaks).
    case notifications
    /// When-in-use location for travel alerts (Phase 2). Key: `NSLocationWhenInUseUsageDescription`.
    case locationWhenInUse

    public var id: String { rawValue }
}

/// Normalized authorization state.
public enum PermissionStatus: String, Sendable, Equatable {
    case notDetermined
    case granted
    /// Partial access (limited photos, write-only calendar, provisional notifications).
    case limited
    case denied
    case restricted

    /// Whether the feature can read what it needs (limited counts for photos/notifications).
    public var isUsable: Bool { self == .granted || self == .limited }
    /// Whether asking again would show the system prompt.
    public var canRequest: Bool { self == .notDetermined }
    /// Whether the user must go to Settings to change it.
    public var needsSettings: Bool { self == .denied }
}

/// Central permission status + request API. Always show a `PermissionPrimer` (DesignSystem)
/// explaining the benefit **before** calling `request(_:)`.
@MainActor
@Observable
public final class PermissionManager {
    public private(set) var statuses: [PermissionKind: PermissionStatus] = [:]

    @ObservationIgnored private lazy var eventStore = EKEventStore()
    @ObservationIgnored private var locationAuthorizer: LocationAuthorizer?
    /// Calendar/Reminders access the user just granted. `EKEventStore.authorizationStatus(for:)`
    /// can keep returning `.notDetermined` in the same process right after the prompt, so the
    /// request's own result is trusted until the system reports a decided status. Shared by every
    /// instance in the process (the app and feature stores each hold one).
    @ObservationIgnored private static var grantedThisLaunch: Set<PermissionKind> = []

    /// URL that opens this app's page in the Settings app.
    public static let settingsURL = URL(string: "app-settings:")!

    public init() {
        refresh()
    }

    public func status(for kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? currentStatus(for: kind)
    }

    /// Re-reads every status (call when the app becomes active; users change them in Settings).
    public func refresh() {
        for kind in PermissionKind.allCases where kind != .notifications {
            statuses[kind] = currentStatus(for: kind)
        }
        Task { statuses[.notifications] = await notificationStatus() }
    }

    /// Shows the system prompt if the status is undetermined; otherwise returns the current status.
    @discardableResult
    public func request(_ kind: PermissionKind) async -> PermissionStatus {
        let current = kind == .notifications ? await notificationStatus() : currentStatus(for: kind)
        guard current.canRequest else {
            statuses[kind] = current
            return current
        }
        let result: PermissionStatus
        switch kind {
        case .calendar:
            if (try? await eventStore.requestFullAccessToEvents()) == true { Self.grantedThisLaunch.insert(.calendar) }
            result = currentStatus(for: .calendar)
        case .reminders:
            if (try? await eventStore.requestFullAccessToReminders()) == true { Self.grantedThisLaunch.insert(.reminders) }
            result = currentStatus(for: .reminders)
        case .photos:
            result = Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
        case .notifications:
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            result = await notificationStatus()
        case .locationWhenInUse:
            let authorizer = LocationAuthorizer()
            locationAuthorizer = authorizer
            result = Self.map(await authorizer.requestWhenInUse())
            locationAuthorizer = nil
        }
        statuses[kind] = result
        return result
    }

    private func currentStatus(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .calendar: eventKitStatus(.event, kind: kind)
        case .reminders: eventKitStatus(.reminder, kind: kind)
        case .photos: Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .locationWhenInUse: Self.map(CLLocationManager().authorizationStatus)
        case .notifications: statuses[.notifications] ?? .notDetermined
        }
    }

    private func notificationStatus() async -> PermissionStatus {
        Self.map(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    // MARK: Mapping (internal for tests)

    private func eventKitStatus(_ entity: EKEntityType, kind: PermissionKind) -> PermissionStatus {
        let status = Self.map(EKEventStore.authorizationStatus(for: entity))
        return status == .notDetermined && Self.grantedThisLaunch.contains(kind) ? .granted : status
    }

    static func map(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess: .granted
        case .writeOnly: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    static func map(_ status: PHAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    static func map(_ status: UNAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .provisional, .ephemeral: .limited
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    static func map(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}

/// Bridges `CLLocationManager`'s delegate-based authorization to async/await.
@MainActor
private final class LocationAuthorizer: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    func requestWhenInUse() async -> CLAuthorizationStatus {
        guard manager.authorizationStatus == .notDetermined else { return manager.authorizationStatus }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Called once immediately with .notDetermined when the delegate is set; wait for the answer.
        guard manager.authorizationStatus != .notDetermined, let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: manager.authorizationStatus)
    }
}
