import CloudKit
import Foundation
import Testing
@testable import CoreKit

/// Scripted iCloud account provider.
final class FakeAccountProvider: CloudAccountProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var status: CKAccountStatus
    private var recordName: String
    init(status: CKAccountStatus, recordName: String = "_user1") {
        self.status = status
        self.recordName = recordName
    }
    func set(status: CKAccountStatus? = nil, recordName: String? = nil) {
        lock.withLock {
            if let status { self.status = status }
            if let recordName { self.recordName = recordName }
        }
    }
    func accountStatus() async throws -> CKAccountStatus { lock.withLock { status } }
    func userRecordName() async throws -> String { lock.withLock { recordName } }
}

@Suite("CloudKitAccountMonitor")
@MainActor
struct CloudKitAccountMonitorTests {
    @Test func mapsStatusesAndDetectsAccountSwitch() async throws {
        let defaults = try #require(UserDefaults(suiteName: "corekit.tests.\(UUID().uuidString)"))
        let provider = FakeAccountProvider(status: .noAccount)
        let monitor = CloudKitAccountMonitor(provider: provider, defaults: defaults)

        await monitor.refresh()
        #expect(monitor.status == .noAccount)
        #expect(monitor.status.userMessage != nil)

        provider.set(status: .available)
        await monitor.refresh()
        #expect(monitor.status == .available)
        #expect(monitor.accountChangeDetected == false)

        provider.set(recordName: "_user2")
        await monitor.refresh()
        #expect(monitor.accountChangeDetected)

        await monitor.resolveAccountChange()
        await monitor.refresh()
        #expect(monitor.accountChangeDetected == false)
    }

    @Test func storesOnlyAHashOfTheUser() {
        let hash = CloudKitAccountMonitor.hash("_abc")
        #expect(hash.count == 64)
        #expect(!hash.contains("abc"))
    }
}

@Suite("DataEraser")
struct DataEraserTests {
    struct FailingZoneEraser: CloudZoneErasing {
        func deleteSyncZone() async throws { throw CKError(.networkUnavailable) }
    }

    @Test func erasesLocalDataFilesAndKeychainEvenIfCloudFails() async throws {
        let appGroup = AppGroupContainer.temporary()
        let stack = try await CoreDataStack.load(mode: .inMemory)
        try await RecordStore<Theme>(stack: stack).upsert(Theme(name: "X", palette: [:]))
        try SnapshotStore(appGroup: appGroup).write(SampleSnapshot(level: 1, label: "", generatedAt: .now))
        let keychain = KeychainStore(service: "corekit.tests.\(UUID().uuidString)", accessGroup: nil, backend: InMemoryKeychainBackend())
        try keychain.setString("secret", for: "token")

        let report = await DataEraser(stack: stack, appGroup: appGroup, keychain: keychain, zoneEraser: FailingZoneEraser()).eraseEverything()

        #expect(report.localDataDeleted && report.filesDeleted && report.keychainCleared)
        #expect(report.cloudZoneDeleted == false)
        #expect(report.cloudErrorMessage != nil)
        #expect(report.isComplete == false)
        #expect(try await RecordStore<Theme>(stack: stack).fetchAll().isEmpty)
        #expect(SnapshotStore(appGroup: appGroup).read(SampleSnapshot.self) == nil)
        #expect(try keychain.string(for: "token") == nil)
    }
}

@Suite("DataEraser feature folders")
struct DataEraserFeatureFolderTests {
    @Test func removesFeatureFoldersAndActiveThemeButKeepsStoresFolder() async throws {
        let appGroup = AppGroupContainer.temporary()
        let fm = FileManager.default
        let aesthetic = appGroup.applicationSupportURL.appending(path: "Aesthetic", directoryHint: .isDirectory)
        try fm.createDirectory(at: aesthetic, withIntermediateDirectories: true)
        try Data("photo".utf8).write(to: aesthetic.appending(path: "p.heic"))
        try fm.createDirectory(at: appGroup.storesURL, withIntermediateDirectories: true)
        ActiveThemeStore(appGroup: appGroup).write(ActiveThemeSnapshot(themeID: UUID(), name: "Beach Hour",
                                                                       primary: .black, accent: .white))
        let keychain = KeychainStore(service: "corekit.tests.\(UUID().uuidString)", accessGroup: nil, backend: InMemoryKeychainBackend())

        _ = await DataEraser(stack: nil, appGroup: appGroup, keychain: keychain, zoneEraser: nil).eraseEverything()

        #expect(!fm.fileExists(atPath: aesthetic.path(percentEncoded: false)))
        #expect(ActiveThemeStore(appGroup: appGroup).read() == nil)
        #expect(fm.fileExists(atPath: appGroup.storesURL.path(percentEncoded: false)))
    }
}

@Suite("ActiveThemeStore")
struct ActiveThemeStoreTests {
    @Test func roundTripsAndReportsChanges() {
        let store = ActiveThemeStore(appGroup: .temporary())
        let snapshot = ActiveThemeSnapshot(themeID: UUID(), name: "Beach Hour",
                                           primary: RGBAColor(hex: "#5B6C8F")!, accent: RGBAColor(hex: "#E07A5F")!)
        #expect(store.read() == nil)
        #expect(store.write(snapshot))
        #expect(store.read() == snapshot)
        #expect(store.write(snapshot) == false) // unchanged → no widget reload
        #expect(store.write(nil))
        #expect(store.read() == nil)
    }

    @Test func needsPrimaryRole() {
        #expect(ActiveThemeSnapshot(theme: Theme(name: "Empty", palette: [:])) == nil)
        let theme = Theme(name: "One", palette: [.primary: .black])
        #expect(ActiveThemeSnapshot(theme: theme)?.accent == .black) // accent falls back to primary
    }
}
