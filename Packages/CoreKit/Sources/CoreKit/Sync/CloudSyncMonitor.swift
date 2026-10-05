import CloudKit
import CoreData
import Foundation
import os

/// Watches `NSPersistentCloudKitContainer`'s sync events and notices when iCloud refuses uploads
/// because the user's iCloud storage is full. Data is always saved on the iPhone first, so nothing is
/// lost and every feature keeps working; only the iCloud copy is paused. Apple's sync retries by itself.
///
/// **Main app only.**
@MainActor
@Observable
public final class CloudSyncMonitor {
    /// `true` after an upload failed with "Quota Exceeded"; cleared by the next successful upload.
    public private(set) var iCloudFull = false

    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "CloudSync")

    public init() {}

    public var userMessage: String? {
        iCloudFull
            ? String(localized: "Your iCloud storage is full, so changes are saved on this iPhone only. They'll sync once there's space in iCloud.")
            : nil
    }

    public func start(container: NSPersistentContainer) {
        guard observation == nil, container is NSPersistentCloudKitContainer else { return }
        observation = Task { [weak self] in
            let events = NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification, object: container)
            for await note in events {
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event,
                      event.type == .export, event.endDate != nil else { continue }
                let full = event.error.map(Self.isQuotaExceeded) ?? false
                if full != self?.iCloudFull {
                    self?.iCloudFull = full
                    self?.logger.info("iCloud full: \(full)")
                }
            }
        }
    }

    /// "Quota Exceeded" arrives either directly or inside a "Partial Failure".
    nonisolated static func isQuotaExceeded(_ error: any Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .quotaExceeded { return true }
        if ckError.code == .partialFailure, let partial = ckError.partialErrorsByItemID?.values {
            return partial.contains { ($0 as? CKError)?.code == .quotaExceeded }
        }
        return false
    }
}
