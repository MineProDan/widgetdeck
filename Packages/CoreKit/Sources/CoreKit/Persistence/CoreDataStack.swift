import CoreData
import Foundation
import os

/// Errors raised by the persistence layer.
public enum PersistenceError: Error, LocalizedError {
    case storeLoadFailed(configuration: String, underlying: any Error)
    case encodingFailed(any Error)
    case decodingFailed(any Error)

    public var errorDescription: String? {
        switch self {
        case .storeLoadFailed:
            // Shown in Settings. The configuration and underlying error go to the log, not the user.
            "Your saved data couldn't be opened, so changes won't be kept this session. Restart Widgetdeck to try again."
        case .encodingFailed: "Couldn't save your data."
        case .decodingFailed: "Some saved data couldn't be read."
        }
    }
}

/// Owns the Core Data container with two configurations:
/// - `Cloud`: `NSPersistentCloudKitContainer`, CloudKit **private** database (main app only).
/// - `Local`: never synced.
///
/// Both stores live in the App Group so App Intents in the widget extension can write one small
/// record locally. The widget extension opens the stack with `.extensionLocalOnly`, which
/// **never** attaches CloudKit options, so the extension never syncs.
public final class CoreDataStack: @unchecked Sendable {
    // @unchecked: `container` is thread-safe for the operations we expose (view context on main,
    // background work through `performBackgroundTask`).

    public enum Mode: Sendable {
        /// Main app: Cloud store syncs through CloudKit.
        case app
        /// Widget extension / App Intents: same files, no CloudKit.
        case extensionLocalOnly
        /// Tests and previews: in-memory stores.
        case inMemory
    }

    public let container: NSPersistentContainer
    public let mode: Mode
    private let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "CoreData")

    public var viewContext: NSManagedObjectContext { container.viewContext }

    private init(container: NSPersistentContainer, mode: Mode) {
        self.container = container
        self.mode = mode
    }

    /// Creates and loads the stack.
    /// - Parameters:
    ///   - contributors: feature entity contributors (see `PersistenceModelContributor`).
    ///   - appGroup: where the store files live.
    public static func load(mode: Mode, contributors: [any PersistenceModelContributor.Type] = [],
                            appGroup: AppGroupContainer = .shared) async throws -> CoreDataStack {
        let model = try PersistenceModel.make(contributors: contributors)
        let name = "WidgetX"
        let container: NSPersistentContainer = mode == .app
            ? NSPersistentCloudKitContainer(name: name, managedObjectModel: model)
            : NSPersistentContainer(name: name, managedObjectModel: model)

        var descriptions: [NSPersistentStoreDescription] = []
        for configuration in StoreConfiguration.allCases {
            let description: NSPersistentStoreDescription
            if mode == .inMemory {
                description = NSPersistentStoreDescription(url: URL(filePath: "/dev/null"))
                description.url = URL(filePath: "/dev/null").appending(path: "\(configuration.rawValue)-\(UUID().uuidString)")
                description.type = NSInMemoryStoreType
            } else {
                let directory = try appGroup.ensureDirectory(appGroup.storesURL)
                description = NSPersistentStoreDescription(url: directory.appending(path: configuration.fileName))
                // History tracking must be on for every process that opens the files, otherwise
                // Core Data opens the store read-only in the process that omits it.
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                                      forKey: NSPersistentStoreFileProtectionKey)
            }
            description.configuration = configuration.rawValue
            description.shouldAddStoreAsynchronously = false
            if mode == .app && configuration == .cloud {
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: AppIdentifiers.iCloudContainer)
            } else {
                description.cloudKitContainerOptions = nil
            }
            descriptions.append(description)
        }
        container.persistentStoreDescriptions = descriptions

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            var remaining = descriptions.count
            var firstError: (any Error)?
            container.loadPersistentStores { description, error in
                if let error, firstError == nil {
                    firstError = PersistenceError.storeLoadFailed(configuration: description.configuration ?? "?", underlying: error)
                }
                remaining -= 1
                if remaining == 0 {
                    if let firstError { continuation.resume(throwing: firstError) } else { continuation.resume() }
                }
            }
        }

        #if DEBUG
        // One-time schema setup: run a Debug build with the launch argument `-WXInitCloudKitSchema YES`
        // to create every record type in the CloudKit Development environment, then deploy it to
        // Production in CloudKit Console. Never compiled into Release builds.
        if mode == .app, UserDefaults.standard.bool(forKey: "WXInitCloudKitSchema"),
           let cloudContainer = container as? NSPersistentCloudKitContainer {
            do {
                try cloudContainer.initializeCloudKitSchema(options: [])
                print("[CoreDataStack] CloudKit schema initialized in Development")
            } catch {
                print("[CoreDataStack] initializeCloudKitSchema failed: \(error)")
            }
        }
        #endif

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.name = "viewContext"
        container.viewContext.transactionAuthor = mode == .app ? "app" : "extension"
        return CoreDataStack(container: container, mode: mode)
    }

    /// Runs `body` on a fresh background context and saves if it has changes.
    public func performBackgroundTask<T: Sendable>(_ body: @escaping @Sendable (NSManagedObjectContext) throws -> T) async throws -> T {
        let author = mode == .app ? "app" : "extension"
        return try await container.performBackgroundTask { context in
            context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
            context.transactionAuthor = author
            let result = try body(context)
            if context.hasChanges { try context.save() }
            return result
        }
    }

    /// Emits whenever another process (CloudKit import, widget intent) changes a store.
    public func remoteChanges() -> AsyncStream<Void> {
        let coordinator = container.persistentStoreCoordinator
        return AsyncStream { continuation in
            let task = Task {
                for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange, object: coordinator) {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Deletes every object in every store (used by "Delete all data").
    public func deleteAllObjects() async throws {
        let entityNames = container.managedObjectModel.entities.compactMap(\.name)
        let inMemory = mode == .inMemory
        try await performBackgroundTask { context in
            for name in entityNames {
                if inMemory {
                    // Batch deletes aren't supported by in-memory stores.
                    for object in try context.fetch(NSFetchRequest<NSManagedObject>(entityName: name)) {
                        context.delete(object)
                    }
                    continue
                }
                let request = NSBatchDeleteRequest(fetchRequest: NSFetchRequest<any NSFetchRequestResult>(entityName: name))
                request.resultType = .resultTypeObjectIDs
                if let result = try context.execute(request) as? NSBatchDeleteResult,
                   let ids = result.result as? [NSManagedObjectID] {
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: ids], into: [context])
                }
            }
        }
        await MainActor.run { viewContext.reset() }
        logger.info("Deleted all objects in \(entityNames.count) entities")
    }
}

extension CoreDataStack.Mode: Equatable {}
