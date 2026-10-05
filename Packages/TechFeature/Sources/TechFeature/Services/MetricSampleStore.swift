import CoreData
import CoreKit
import Foundation

/// Where `MetricSample`s live. 7-day rolling window.
public protocol MetricSampleStore: Sendable {
    func append(_ sample: MetricSample) async throws
    /// Oldest sample at or after `date` (used for the weekly storage trend).
    func oldest(since date: Date) async throws -> MetricSample?
    /// Deletes samples older than `date`; returns how many were removed.
    @discardableResult
    func prune(olderThan date: Date) async throws -> Int
}

/// Adds the Tech entity to CoreKit's **Local** configuration (never synced to CloudKit).
/// The app passes this to `CoreDataStack.load(mode:contributors:)` (see README, CoreKit requests).
public enum TechPersistenceModel: PersistenceModelContributor {
    public static let metricSampleEntity = "TechMetricSampleRecord"

    public static func makeEntities() -> [StoreConfiguration: [NSEntityDescription]] {
        [.local: [PayloadEntity.make(name: metricSampleEntity)]]
    }
}

/// Core Data implementation: one `PayloadEntity` row per sample, `updatedAt` = sample date.
public struct CoreDataMetricSampleStore: MetricSampleStore {
    private let stack: CoreDataStack

    public init(stack: CoreDataStack) {
        self.stack = stack
    }

    public func append(_ sample: MetricSample) async throws {
        let payload = try JSONEncoder().encode(sample)
        try await stack.performBackgroundTask { context in
            let object = NSEntityDescription.insertNewObject(forEntityName: TechPersistenceModel.metricSampleEntity, into: context)
            object.setValue(sample.id, forKey: PersistenceModel.Attribute.id)
            object.setValue(sample.date, forKey: PersistenceModel.Attribute.updatedAt)
            object.setValue(payload, forKey: PersistenceModel.Attribute.payload)
        }
    }

    public func oldest(since date: Date) async throws -> MetricSample? {
        let data: Data? = try await stack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: TechPersistenceModel.metricSampleEntity)
            request.predicate = NSPredicate(format: "%K >= %@", PersistenceModel.Attribute.updatedAt, date as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: PersistenceModel.Attribute.updatedAt, ascending: true)]
            request.fetchLimit = 1
            return try context.fetch(request).first?.value(forKey: PersistenceModel.Attribute.payload) as? Data
        }
        guard let data else { return nil }
        return try JSONDecoder().decode(MetricSample.self, from: data)
    }

    @discardableResult
    public func prune(olderThan date: Date) async throws -> Int {
        try await stack.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: TechPersistenceModel.metricSampleEntity)
            request.predicate = NSPredicate(format: "%K < %@", PersistenceModel.Attribute.updatedAt, date as NSDate)
            let old = try context.fetch(request)
            old.forEach(context.delete)
            return old.count
        }
    }
}

/// Fallback when the app hasn't wired a Core Data stack (and for previews/tests).
public actor InMemoryMetricSampleStore: MetricSampleStore {
    public private(set) var samples: [MetricSample] = []

    public init(samples: [MetricSample] = []) {
        self.samples = samples
    }

    public func append(_ sample: MetricSample) {
        samples.append(sample)
    }

    public func oldest(since date: Date) -> MetricSample? {
        samples.filter { $0.date >= date }.min { $0.date < $1.date }
    }

    @discardableResult
    public func prune(olderThan date: Date) -> Int {
        let before = samples.count
        samples.removeAll { $0.date < date }
        return before - samples.count
    }
}
