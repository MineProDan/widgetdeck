import CloudKit
import Foundation
import os

/// Deletes the CloudKit zone that `NSPersistentCloudKitContainer` mirrors into.
public protocol CloudZoneErasing: Sendable {
    func deleteSyncZone() async throws
}

/// Production zone eraser for the Core Data mirroring zone in the private database.
public struct CoreDataCloudZoneEraser: CloudZoneErasing {
    /// Zone name used by `NSPersistentCloudKitContainer`.
    public static let zoneName = "com.apple.coredata.cloudkit.zone"
    private let containerIdentifier: String

    public init(containerIdentifier: String = AppIdentifiers.iCloudContainer) {
        self.containerIdentifier = containerIdentifier
    }

    public func deleteSyncZone() async throws {
        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        do {
            _ = try await database.deleteRecordZone(withID: CKRecordZone.ID(zoneName: Self.zoneName))
        } catch let error as CKError where error.code == .zoneNotFound {
            // Nothing was ever synced; that's fine.
        }
    }
}

/// "Delete all my data" (P-08): purges local stores, App Group files, Keychain items and the
/// CloudKit private zone. Doubles as the App Store account-deletion story.
public struct DataEraser: Sendable {
    /// What happened, so Settings can tell the user precisely.
    public struct Report: Sendable, Equatable {
        public var localDataDeleted = false
        public var filesDeleted = false
        public var keychainCleared = false
        /// `nil` = not attempted (no iCloud account); otherwise success.
        public var cloudZoneDeleted: Bool?
        public var cloudErrorMessage: String?

        public var isComplete: Bool { localDataDeleted && filesDeleted && keychainCleared && cloudZoneDeleted != false }
    }

    private let stack: CoreDataStack?
    private let appGroup: AppGroupContainer
    private let keychain: KeychainStore
    private let zoneEraser: (any CloudZoneErasing)?
    private let extraCleanup: @Sendable () async -> Void

    /// - Parameters:
    ///   - zoneEraser: pass `nil` when iCloud isn't available (the zone is then left for iCloud to
    ///     remove if the user deletes the app's iCloud data in Settings).
    ///   - extraCleanup: feature-specific cleanup (pending notifications, UserDefaults keys).
    public init(stack: CoreDataStack?, appGroup: AppGroupContainer = .shared, keychain: KeychainStore,
                zoneEraser: (any CloudZoneErasing)?, extraCleanup: @escaping @Sendable () async -> Void = {}) {
        self.stack = stack
        self.appGroup = appGroup
        self.keychain = keychain
        self.zoneEraser = zoneEraser
        self.extraCleanup = extraCleanup
    }

    /// Runs every step even if an earlier one fails, and reports each outcome.
    public func eraseEverything() async -> Report {
        let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "DataEraser")
        var report = Report()

        // 1. Cloud first, so the local deletion isn't re-imported by a sync in between.
        if let zoneEraser {
            do {
                try await zoneEraser.deleteSyncZone()
                report.cloudZoneDeleted = true
            } catch {
                report.cloudZoneDeleted = false
                report.cloudErrorMessage = (error as? CKError)?.syncUserMessage
                    ?? "Couldn't delete your iCloud copy. Try again when you're online."
                logger.error("Zone deletion failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // 2. Local stores.
        if let stack {
            do {
                try await stack.deleteAllObjects()
                report.localDataDeleted = true
            } catch {
                logger.error("Local delete failed: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            report.localDataDeleted = true
        }

        // 3. App Group files + shared defaults. Everything under Application Support except the
        //    Core Data stores (handled above) is user data: snapshots, exports, the active theme and
        //    each feature's own folder (e.g. Aesthetic photos, Student settings). Listing the folder
        //    means new features are covered without changes here.
        let fileManager = FileManager.default
        var filesOK = true
        let supportItems = (try? fileManager.contentsOfDirectory(at: appGroup.applicationSupportURL,
                                                                 includingPropertiesForKeys: nil)) ?? []
        let targets = supportItems.filter { $0.lastPathComponent != appGroup.storesURL.lastPathComponent }
            + [appGroup.imageCacheURL, appGroup.cachesURL.appending(path: "sync-trace.log")]
        for url in targets
        where fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            do { try fileManager.removeItem(at: url) } catch {
                filesOK = false
                logger.error("Couldn't remove \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        let defaults = appGroup.userDefaults
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("corekit.") || key.hasPrefix("feature.") {
            defaults.removeObject(forKey: key)
        }
        report.filesDeleted = filesOK

        // 4. Keychain.
        do {
            try keychain.deleteAll()
            report.keychainCleared = true
        } catch {
            logger.error("Keychain wipe failed: \(error.localizedDescription, privacy: .public)")
        }

        await extraCleanup()
        return report
    }
}
