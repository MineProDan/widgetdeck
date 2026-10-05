import CoreData
import Foundation
import os

/// Removes duplicate rows that CloudKit can produce when the same logical record (same `id`) is
/// created on two devices before they sync. Keeps the row with the newest `updatedAt`.
///
/// Run it after remote changes (`CoreDataStack.remoteChanges()`), debounced. Only for entities
/// that follow the payload-entity pattern (`id` + `updatedAt`).
public struct DeduplicationService: Sendable {
    private let stack: CoreDataStack
    private let entityNames: [String]

    /// - Parameter entityNames: entities to dedupe. Defaults to CoreKit's synced entities; features
    ///   append their own.
    public init(stack: CoreDataStack, entityNames: [String] = [
        PersistenceModel.Entity.theme, PersistenceModel.Entity.userProfile, PersistenceModel.Entity.widgetConfiguration
    ]) {
        self.stack = stack
        self.entityNames = entityNames
    }

    /// - Returns: number of rows deleted.
    @discardableResult
    public func run() async throws -> Int {
        let names = entityNames
        let removed = try await stack.performBackgroundTask { context in
            var removed = 0
            for name in names {
                let request = NSFetchRequest<NSManagedObject>(entityName: name)
                request.sortDescriptors = [
                    NSSortDescriptor(key: PersistenceModel.Attribute.updatedAt, ascending: false)
                ]
                var seen = Set<UUID>()
                for object in try context.fetch(request) {
                    guard let id = object.value(forKey: PersistenceModel.Attribute.id) as? UUID else {
                        // Rows without an id can never be addressed again; drop them.
                        context.delete(object)
                        removed += 1
                        continue
                    }
                    if !seen.insert(id).inserted {
                        context.delete(object)
                        removed += 1
                    }
                }
            }
            return removed
        }
        if removed > 0 {
            Logger(subsystem: AppIdentifiers.appBundleID, category: "Dedupe").info("Removed \(removed) duplicate rows")
        }
        return removed
    }
}
