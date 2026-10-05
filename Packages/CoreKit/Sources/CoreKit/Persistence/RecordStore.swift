import CoreData
import Foundation
import os

/// A Codable value stored with the payload-entity pattern (`id`, `updatedAt`, `payload`).
public protocol PersistableRecord: Codable, Identifiable, Sendable where ID == UUID {
    /// Core Data entity name (must be created with `PayloadEntity.make`).
    static var entityName: String { get }
    var updatedAt: Date { get }
}

extension Theme: PersistableRecord {
    public static var entityName: String { PersistenceModel.Entity.theme }
}

extension UserProfile: PersistableRecord {
    public static var entityName: String { PersistenceModel.Entity.userProfile }
}

extension WidgetSettings: PersistableRecord {
    public static var entityName: String { PersistenceModel.Entity.widgetConfiguration }
}

/// Generic CRUD for `PersistableRecord` values. All work runs on background contexts.
///
/// CloudKit can deliver duplicates (same `id` created on two devices before sync). Reads always
/// return the newest copy per `id`; `DeduplicationService` removes the stale rows.
public struct RecordStore<Value: PersistableRecord>: Sendable {
    private let stack: CoreDataStack
    private static var logger: Logger { Logger(subsystem: AppIdentifiers.appBundleID, category: "RecordStore") }

    public init(stack: CoreDataStack) {
        self.stack = stack
    }

    /// All values, newest copy per id, sorted by `updatedAt` descending.
    public func fetchAll() async throws -> [Value] {
        try await stack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Value.entityName)
            request.sortDescriptors = [NSSortDescriptor(key: PersistenceModel.Attribute.updatedAt, ascending: false)]
            var seen = Set<UUID>()
            var values: [Value] = []
            let decoder = JSONDecoder()
            for object in try context.fetch(request) {
                guard let id = object.value(forKey: PersistenceModel.Attribute.id) as? UUID, seen.insert(id).inserted,
                      let data = object.value(forKey: PersistenceModel.Attribute.payload) as? Data else { continue }
                do {
                    values.append(try decoder.decode(Value.self, from: data))
                } catch {
                    // A payload written by a newer app version or corrupted: skip, never crash.
                    Self.logger.error("Skipping undecodable \(Value.entityName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            return values
        }
    }

    /// The newest value with `id`, if any.
    public func fetch(id: UUID) async throws -> Value? {
        try await stack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Value.entityName)
            request.predicate = NSPredicate(format: "%K == %@", PersistenceModel.Attribute.id, id as NSUUID)
            request.sortDescriptors = [NSSortDescriptor(key: PersistenceModel.Attribute.updatedAt, ascending: false)]
            request.fetchLimit = 1
            guard let data = try context.fetch(request).first?.value(forKey: PersistenceModel.Attribute.payload) as? Data else {
                return nil
            }
            do { return try JSONDecoder().decode(Value.self, from: data) } catch { throw PersistenceError.decodingFailed(error) }
        }
    }

    /// Inserts or replaces the value with the same id (all duplicate rows are updated too).
    public func upsert(_ value: Value) async throws {
        let data: Data
        do { data = try JSONEncoder().encode(value) } catch { throw PersistenceError.encodingFailed(error) }
        try await stack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Value.entityName)
            request.predicate = NSPredicate(format: "%K == %@", PersistenceModel.Attribute.id, value.id as NSUUID)
            var objects = try context.fetch(request)
            if objects.isEmpty {
                objects = [NSEntityDescription.insertNewObject(forEntityName: Value.entityName, into: context)]
            }
            for object in objects {
                object.setValue(value.id, forKey: PersistenceModel.Attribute.id)
                object.setValue(value.updatedAt, forKey: PersistenceModel.Attribute.updatedAt)
                object.setValue(data, forKey: PersistenceModel.Attribute.payload)
            }
        }
    }

    /// Deletes every row with `id`.
    public func delete(id: UUID) async throws {
        try await stack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: Value.entityName)
            request.predicate = NSPredicate(format: "%K == %@", PersistenceModel.Attribute.id, id as NSUUID)
            for object in try context.fetch(request) { context.delete(object) }
        }
    }
}
