import Foundation
import Security

/// Errors from `KeychainStore`.
public enum KeychainError: Error, Equatable, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain error: \(message)"
        case .invalidData: return "Keychain item has an unexpected format."
        }
    }
}

/// Generic-password Keychain wrapper shared by the app and the widget extension.
///
/// Items use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: readable by the widget after the
/// first unlock, **never** included in backups or synced to other devices. OAuth tokens belong
/// here, never in Core Data or UserDefaults.
public struct KeychainStore: Sendable {
    public let service: String
    public let accessGroup: String?
    private let backend: any KeychainBackend

    /// - Parameters:
    ///   - service: namespace for items (default: the app bundle ID).
    ///   - accessGroup: the shared access group; pass `AppIdentifiers.keychainAccessGroup()` in the
    ///     app and extension. `nil` uses the process's default group (tests).
    ///   - backend: `SecItemKeychainBackend` (default) or `InMemoryKeychainBackend` for tests/previews.
    public init(service: String = AppIdentifiers.appBundleID, accessGroup: String? = AppIdentifiers.keychainAccessGroup(),
                backend: any KeychainBackend = SecItemKeychainBackend()) {
        self.service = service
        self.accessGroup = accessGroup
        self.backend = backend
    }

    private func baseQuery(key: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true
        ]
        if let key { query[kSecAttrAccount as String] = key }
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    /// Stores (inserts or replaces) `data` under `key`.
    public func set(_ data: Data, for key: String) throws {
        let query = baseQuery(key: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = backend.update(query, attributes: attributes)
        if status == errSecItemNotFound {
            status = backend.add(query.merging(attributes) { $1 })
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// The data stored under `key`, or `nil` if there is none.
    public func data(for key: String) throws -> Data? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = backend.copyMatching(query)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.invalidData }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes the item under `key` (no error if it doesn't exist).
    public func delete(_ key: String) throws {
        let status = backend.delete(baseQuery(key: key))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Removes every item in this service (used by "Delete all data" and Pinterest disconnect).
    public func deleteAll() throws {
        let status = backend.delete(baseQuery())
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }
    }

    // MARK: Convenience

    public func setString(_ value: String, for key: String) throws { try set(Data(value.utf8), for: key) }

    public func string(for key: String) throws -> String? {
        guard let data = try data(for: key) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else { throw KeychainError.invalidData }
        return string
    }

    public func setCodable<T: Encodable>(_ value: T, for key: String) throws {
        try set(JSONEncoder().encode(value), for: key)
    }

    public func codable<T: Decodable>(_ type: T.Type, for key: String) throws -> T? {
        guard let data = try data(for: key) else { return nil }
        do { return try JSONDecoder().decode(type, from: data) } catch { throw KeychainError.invalidData }
    }
}

/// The four SecItem primitives, abstracted so unit tests can run without keychain entitlements
/// (hostless test bundles get `errSecMissingEntitlement`, -34018).
public protocol KeychainBackend: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?)
    func delete(_ query: [String: Any]) -> OSStatus
}

/// The real Keychain.
public struct SecItemKeychainBackend: KeychainBackend {
    public init() {}
    public func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    public func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
    public func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }
    public func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

/// In-memory generic-password store with SecItem semantics for service/account/access group.
/// For unit tests and SwiftUI previews only.
public final class InMemoryKeychainBackend: KeychainBackend, @unchecked Sendable {
    private struct ItemKey: Hashable { let service: String; let account: String; let group: String? }
    private let lock = NSLock()
    private var items: [ItemKey: Data] = [:]

    public init() {}

    private func matches(_ key: ItemKey, _ query: [String: Any]) -> Bool {
        if let service = query[kSecAttrService as String] as? String, service != key.service { return false }
        if let account = query[kSecAttrAccount as String] as? String, account != key.account { return false }
        if let group = query[kSecAttrAccessGroup as String] as? String, group != key.group { return false }
        return true
    }

    public func add(_ attributes: [String: Any]) -> OSStatus {
        guard let service = attributes[kSecAttrService as String] as? String,
              let account = attributes[kSecAttrAccount as String] as? String,
              let data = attributes[kSecValueData as String] as? Data else { return errSecParam }
        let key = ItemKey(service: service, account: account, group: attributes[kSecAttrAccessGroup as String] as? String)
        return lock.withLock {
            guard items[key] == nil else { return errSecDuplicateItem }
            items[key] = data
            return errSecSuccess
        }
    }

    public func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            let keys = items.keys.filter { matches($0, query) }
            guard !keys.isEmpty else { return errSecItemNotFound }
            if let data = attributes[kSecValueData as String] as? Data {
                for key in keys { items[key] = data }
            }
            return errSecSuccess
        }
    }

    public func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?) {
        lock.withLock {
            guard let key = items.keys.first(where: { matches($0, query) }), let data = items[key] else {
                return (errSecItemNotFound, nil)
            }
            return (errSecSuccess, data as NSData)
        }
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock {
            let keys = items.keys.filter { matches($0, query) }
            guard !keys.isEmpty else { return errSecItemNotFound }
            for key in keys { items[key] = nil }
            return errSecSuccess
        }
    }
}
