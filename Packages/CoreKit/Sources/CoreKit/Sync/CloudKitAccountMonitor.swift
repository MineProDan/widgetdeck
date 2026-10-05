import CloudKit
import CryptoKit
import Foundation
import Observation
import os

/// iCloud account state as the UI needs it. Sync is best-effort: the app always works locally.
public enum CloudAccountStatus: String, Sendable, Equatable {
    /// Not checked yet.
    case unknown
    /// Signed in; sync is on (silently).
    case available
    /// No iCloud account: works locally, Settings shows "Sign in to iCloud to sync".
    case noAccount
    /// Parental controls / MDM: local only, no nagging.
    case restricted
    /// Temporarily unavailable; retried on `CKAccountChanged`.
    case temporarilyUnavailable
    /// The status check itself failed (e.g. no network on first launch).
    case couldNotDetermine

    public var isSyncing: Bool { self == .available }

    /// Short user-facing explanation for Settings, or `nil` when nothing needs saying.
    public var userMessage: String? {
        switch self {
        case .available, .unknown, .restricted: nil
        case .noAccount: "Sign in to iCloud to sync across your devices. Everything still works on this iPhone."
        case .temporarilyUnavailable: "iCloud is temporarily unavailable. We'll sync when it's back."
        case .couldNotDetermine: "Couldn't check iCloud right now. Your data is safe on this iPhone."
        }
    }
}

/// Abstraction over `CKContainer` so the monitor is testable.
public protocol CloudAccountProviding: Sendable {
    func accountStatus() async throws -> CKAccountStatus
    /// The current iCloud user's record name.
    func userRecordName() async throws -> String
}

/// Production provider. The container is created lazily so merely linking CoreKit never touches CloudKit.
public struct CloudKitContainerAccountProvider: CloudAccountProviding {
    private let identifier: String

    public init(containerIdentifier: String = AppIdentifiers.iCloudContainer) {
        self.identifier = containerIdentifier
    }

    public func accountStatus() async throws -> CKAccountStatus {
        try await CKContainer(identifier: identifier).accountStatus()
    }

    public func userRecordName() async throws -> String {
        try await CKContainer(identifier: identifier).userRecordID().recordName
    }
}

/// Tracks the iCloud account status and detects account switches.
///
/// **Main app only.** The widget extension must never create one.
@MainActor
@Observable
public final class CloudKitAccountMonitor {
    public private(set) var status: CloudAccountStatus = .unknown
    /// `true` when the signed-in iCloud user differs from the one we last synced with.
    /// The UI should ask: keep local data or reset (then call `resolveAccountChange`).
    public private(set) var accountChangeDetected = false

    @ObservationIgnored private let provider: any CloudAccountProviding
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "CloudAccount")
    private static let userHashKey = "corekit.cloud.userHash"

    public init(provider: any CloudAccountProviding = CloudKitContainerAccountProvider(),
                defaults: UserDefaults = AppGroupContainer.shared.userDefaults) {
        self.provider = provider
        self.defaults = defaults
    }

    /// Checks the status now and on every `CKAccountChanged` notification.
    public func start() {
        guard observation == nil else { return }
        observation = Task { [weak self] in
            await self?.refresh()
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                await self?.refresh()
            }
        }
    }

    public func stop() {
        observation?.cancel()
        observation = nil
    }

    /// Re-reads the account status (and user identity when available).
    public func refresh() async {
        do {
            let accountStatus = try await provider.accountStatus()
            status = Self.map(accountStatus)
            if status == .available { await checkIdentity() }
        } catch {
            logger.error("accountStatus failed: \(error.localizedDescription, privacy: .public)")
            status = .couldNotDetermine
        }
    }

    /// Call after the user chose what to do about a switched account.
    public func resolveAccountChange() async {
        accountChangeDetected = false
        if let name = try? await provider.userRecordName() {
            defaults.set(Self.hash(name), forKey: Self.userHashKey)
        }
    }

    static func map(_ status: CKAccountStatus) -> CloudAccountStatus {
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .couldNotDetermine
        @unknown default: .couldNotDetermine
        }
    }

    private func checkIdentity() async {
        guard let name = try? await provider.userRecordName() else { return }
        let hash = Self.hash(name)
        if let previous = defaults.string(forKey: Self.userHashKey) {
            accountChangeDetected = previous != hash
        } else {
            // First sync on this install: remember who we are.
            defaults.set(hash, forKey: Self.userHashKey)
        }
    }

    /// Only a hash of the record name is stored; the identifier itself never persists.
    static func hash(_ recordName: String) -> String {
        SHA256.hash(data: Data(recordName.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension CKError {
    /// User-facing message for the sync errors Settings must surface without blocking the app.
    public var syncUserMessage: String? {
        switch code {
        case .quotaExceeded: "Your iCloud storage is full, so sync is paused. Your data is safe on this iPhone."
        case .notAuthenticated: CloudAccountStatus.noAccount.userMessage
        case .networkUnavailable, .networkFailure: "You're offline. We'll sync when you're back online."
        default: nil
        }
    }
}
