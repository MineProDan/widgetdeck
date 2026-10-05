import CoreData
import Foundation

/// The two Core Data store configurations.
public enum StoreConfiguration: String, CaseIterable, Sendable {
    /// Synced to the CloudKit **private** database (main app only).
    case cloud = "Cloud"
    /// Never leaves the device (Tech metric samples, EventKit ID mirror, content cache index).
    case local = "Local"

    var fileName: String { "\(rawValue).sqlite" }
}

/// Feature packages add their own entities by conforming a type to this protocol and passing it
/// to `CoreDataStack`. This keeps CoreKit frozen while every section owns its schema.
///
/// CloudKit rules for `.cloud` entities (enforced by `PersistenceModel.validate`):
/// every attribute optional or defaulted, no unique constraints, every relationship optional
/// with an inverse, no ordered relationships.
public protocol PersistenceModelContributor {
    /// Entities to add, keyed by the configuration they belong to.
    static func makeEntities() -> [StoreConfiguration: [NSEntityDescription]]
}

/// Builds the programmatic `NSManagedObjectModel`. A programmatic model avoids `.xcdatamodeld`
/// resource-compilation differences between SwiftPM and Xcode, and lets features contribute entities.
public enum PersistenceModel {
    /// Entity names owned by CoreKit.
    public enum Entity {
        public static let theme = "ThemeRecord"
        public static let userProfile = "UserProfileRecord"
        public static let widgetConfiguration = "WidgetConfigurationRecord"
        public static let localCacheEntry = "LocalCacheEntry"
    }

    /// Attribute names shared by every "payload" entity (see `PayloadEntity`).
    public enum Attribute {
        public static let id = "id"
        public static let updatedAt = "updatedAt"
        public static let payload = "payload"
        public static let key = "key"
    }

    /// Validation errors for CloudKit-incompatible schemas.
    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case nonOptionalAttribute(entity: String, attribute: String)
        case uniqueConstraint(entity: String)
        case relationshipNotOptional(entity: String, relationship: String)
        case relationshipMissingInverse(entity: String, relationship: String)
        case orderedRelationship(entity: String, relationship: String)
        case duplicateEntity(String)

        public var description: String {
            switch self {
            case let .nonOptionalAttribute(e, a): "\(e).\(a) must be optional or have a default value for CloudKit"
            case let .uniqueConstraint(e): "\(e) must not declare unique constraints (CloudKit)"
            case let .relationshipNotOptional(e, r): "\(e).\(r) must be optional (CloudKit)"
            case let .relationshipMissingInverse(e, r): "\(e).\(r) must have an inverse (CloudKit)"
            case let .orderedRelationship(e, r): "\(e).\(r) must not be ordered (CloudKit)"
            case let .duplicateEntity(name): "Entity \(name) is defined more than once"
            }
        }
    }

    /// CoreKit's own entities.
    static func coreEntities() -> [StoreConfiguration: [NSEntityDescription]] {
        [
            .cloud: [
                PayloadEntity.make(name: Entity.theme),
                // Display name lives in the payload, so the whole payload is end-to-end encrypted.
                PayloadEntity.make(name: Entity.userProfile, encryptPayload: true),
                PayloadEntity.make(name: Entity.widgetConfiguration)
            ],
            .local: [
                localCacheEntity()
            ]
        ]
    }

    /// Builds a model from CoreKit's entities plus every contributor's entities.
    /// - Throws: `ValidationError` if an entity breaks the CloudKit schema rules.
    public static func make(contributors: [any PersistenceModelContributor.Type] = []) throws -> NSManagedObjectModel {
        var byConfiguration = coreEntities()
        for contributor in contributors {
            for (configuration, entities) in contributor.makeEntities() {
                byConfiguration[configuration, default: []].append(contentsOf: entities)
            }
        }

        var seen = Set<String>()
        for entity in byConfiguration.values.flatMap({ $0 }) {
            let name = entity.name ?? ""
            guard seen.insert(name).inserted else { throw ValidationError.duplicateEntity(name) }
        }
        try validate(byConfiguration[.cloud] ?? [])

        let model = NSManagedObjectModel()
        model.entities = byConfiguration.values.flatMap { $0 }
        for (configuration, entities) in byConfiguration {
            model.setEntities(entities, forConfigurationName: configuration.rawValue)
        }
        return model
    }

    /// Checks the CloudKit schema rules on `.cloud` entities.
    public static func validate(_ cloudEntities: [NSEntityDescription]) throws {
        for entity in cloudEntities {
            let name = entity.name ?? "?"
            if !entity.uniquenessConstraints.isEmpty { throw ValidationError.uniqueConstraint(entity: name) }
            for (attributeName, attribute) in entity.attributesByName
            where !attribute.isOptional && attribute.defaultValue == nil {
                throw ValidationError.nonOptionalAttribute(entity: name, attribute: attributeName)
            }
            for (relationshipName, relationship) in entity.relationshipsByName {
                if !relationship.isOptional { throw ValidationError.relationshipNotOptional(entity: name, relationship: relationshipName) }
                if relationship.inverseRelationship == nil {
                    throw ValidationError.relationshipMissingInverse(entity: name, relationship: relationshipName)
                }
                if relationship.isOrdered { throw ValidationError.orderedRelationship(entity: name, relationship: relationshipName) }
            }
        }
    }

    private static func localCacheEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = Entity.localCacheEntry
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            PayloadEntity.attribute(Attribute.key, .stringAttributeType),
            PayloadEntity.attribute(Attribute.payload, .binaryDataAttributeType),
            PayloadEntity.attribute(Attribute.updatedAt, .dateAttributeType)
        ]
        return entity
    }
}

/// Helpers for the "payload entity" pattern used across the app: `id` (UUID), `updatedAt` (Date)
/// and `payload` (JSON-encoded Codable value). Keeps the CloudKit schema tiny and lets the Swift
/// model evolve without migrations. Feature packages may use it for their own entities.
public enum PayloadEntity {
    /// Creates an optional attribute.
    public static func attribute(_ name: String, _ type: NSAttributeType, encrypted: Bool = false,
                                 defaultValue: Any? = nil) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        attribute.defaultValue = defaultValue
        // End-to-end encrypted in CloudKit ("Allows Cloud Encryption").
        attribute.allowsCloudEncryption = encrypted
        if type == .binaryDataAttributeType { attribute.allowsExternalBinaryDataStorage = false }
        return attribute
    }

    /// Creates an `id` / `updatedAt` / `payload` entity.
    /// - Parameters:
    ///   - encryptPayload: mark the payload as *Allows Cloud Encryption* (mood notes, grades…).
    ///   - extraAttributes: additional queryable attributes (must be optional for CloudKit).
    public static func make(name: String, encryptPayload: Bool = false,
                            extraAttributes: [NSAttributeDescription] = []) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute(PersistenceModel.Attribute.id, .UUIDAttributeType),
            attribute(PersistenceModel.Attribute.updatedAt, .dateAttributeType),
            attribute(PersistenceModel.Attribute.payload, .binaryDataAttributeType, encrypted: encryptPayload)
        ] + extraAttributes
        return entity
    }
}
