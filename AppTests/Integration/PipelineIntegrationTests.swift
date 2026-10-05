import AestheticFeature
import AestheticFeatureWidgetKit
import CoreKit
import Foundation
import StudentFeature
import StudentFeatureWidgetKit
import TechFeature
import TechFeatureWidgetKit
import Testing

/// Records WidgetKit reload requests instead of calling WidgetCenter.
actor ReloadRecorder {
    private(set) var batches: [[String]] = []
    func record(_ kinds: [String]) { batches.append(kinds.sorted()) }
    var all: Set<String> { Set(batches.flatMap { $0 }) }
}

@Suite("Integration: sections, snapshot pipeline, failures")
struct PipelineIntegrationTests {
    // MARK: All sections launch together

    /// The app's shared model: CoreKit entities + Tech + Student contributions in one stack.
    @Test @MainActor func allSectionsOpenOnOneStack() async throws {
        let stack = try await CoreDataStack.load(mode: .inMemory,
                                                 contributors: [TechPersistenceModel.self, StudentModel.self])
        let student = StudentStore(repository: CoreDataStudentRepository(stack: stack, appGroup: .temporary()))
        let tech = SystemMonitorService(store: CoreDataMetricSampleStore(stack: stack))
        let aesthetic = AestheticStore(themes: CoreDataThemeRepository(stack: stack), onThemeApplied: {})
        _ = (student, tech, aesthetic)

        // A theme applied from Aesthetic is readable through CoreKit's profile, as the app shell does.
        let theme = Theme(name: "Test", palette: [.primary: .black, .accent: .white])
        try await CoreDataThemeRepository(stack: stack).applyTheme(theme)
        let profile = try await RecordStore<UserProfile>(stack: stack).fetchAll().first
        #expect(profile?.activeThemeID == theme.id)
        #expect(try await RecordStore<Theme>(stack: stack).fetch(id: theme.id)?.name == "Test")
    }

    // MARK: Data change → snapshot → reload

    @Test func techChangeWritesSnapshotsAndReloadsOnlyChangedKinds() async throws {
        let group = AppGroupContainer.temporary()
        let store = SnapshotStore(appGroup: group)
        let recorder = ReloadRecorder()
        let coordinator = WidgetReloadCoordinator(store: store, reloader: { await recorder.record($0) })

        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let metrics = SystemMetrics.sample(level: 0.62, now: now)
        let output = TechSnapshotBuilder.build(from: metrics, includeProcessor: false, now: now)
        #expect(try await coordinator.publish(output.battery))
        #expect(try await coordinator.publish(output.overview))
        await coordinator.flushNow()
        #expect(await recorder.all == [WidgetKind.battery.kindIdentifier, WidgetKind.systemOverview.kindIdentifier])

        // Widgets read the same bytes back (the extension's only data source).
        #expect(store.read(BatterySnapshot.self) == output.battery)

        // Unchanged content → no reload; a changed level → only Battery reloads.
        #expect(try await coordinator.publish(output.battery) == false)
        let changed = TechSnapshotBuilder.build(from: .sample(level: 0.63, now: now), includeProcessor: false, now: now)
        #expect(try await coordinator.publish(changed.battery))
        await coordinator.flushNow()
        #expect(await recorder.batches.last == [WidgetKind.battery.kindIdentifier])
    }

    @Test func studentAndAestheticSnapshotsRoundTrip() throws {
        let store = SnapshotStore(appGroup: .temporary())
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let next = NextClassSnapshot(classes: SampleSchedule.day(around: now), generatedAt: now)
        try store.write(next)
        #expect(store.read(NextClassSnapshot.self)?.classes == next.classes)
        try store.write(PaletteSnapshot.sample)
        #expect(store.read(PaletteSnapshot.self) == PaletteSnapshot.sample)
        // Missing snapshot → nil (widgets then show their sample/empty state, never blank).
        #expect(store.read(PhotoSnapshot.self) == nil)
    }

    @Test func activeThemeReachesWidgets() throws {
        let group = AppGroupContainer.temporary()
        let theme = Theme(name: "Moss", palette: [.primary: RGBAColor(hex: "#4C7A62")!, .accent: RGBAColor(hex: "#81B29A")!])
        let store = ActiveThemeStore(appGroup: group)
        #expect(store.write(ActiveThemeSnapshot(theme: theme)))
        #expect(store.read()?.primary == theme.palette[.primary])
        // Writing the same palette again is not a change (no widget reload).
        #expect(store.write(ActiveThemeSnapshot(theme: theme)) == false)
    }

    // MARK: Failure handling

    @Test func remoteFlagsKeepDefaultsWhenTheCDNFails() async throws {
        let suite = "flags.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailingURLProtocol.self]
        let client = HTTPClient(session: URLSession(configuration: config), retryPolicy: RetryPolicy(maxAttempts: 1))
        let flags = RemoteFlags(client: client, store: defaults, url: URL(string: "https://cdn.invalid/flags.json")!)
        await flags.refresh()
        for (name, value) in RemoteFlags.defaults {
            #expect(defaults.object(forKey: RemoteFlags.key(name)) as? Bool == value)
        }
    }

    @Test func flagsFileInDocsMatchesCompiledKeys() throws {
        // docs/AppStore/flags.json is what gets uploaded to the CDN; it must use the same keys.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/AppStore/flags.json")
        let data = try Data(contentsOf: url)
        let remote = try JSONDecoder().decode([String: Bool].self, from: data)
        #expect(Set(remote.keys) == Set(RemoteFlags.defaults.keys))
    }

    @Test func storeErrorsHaveFriendlyMessages() {
        struct Underlying: Error {}
        let errors: [PersistenceError] = [
            .storeLoadFailed(configuration: "Cloud", underlying: Underlying()),
            .encodingFailed(Underlying()),
            .decodingFailed(Underlying()),
        ]
        for error in errors {
            let message = error.errorDescription ?? ""
            #expect(!message.isEmpty)
            #expect(!message.contains("Underlying"))
        }
    }
}

final class FailingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

extension SystemMetrics {
    static func sample(level: Double, now: Date) -> SystemMetrics {
        SystemMetrics(battery: BatteryStatus(level: level, state: .unplugged),
                      storage: StorageStatus(totalBytes: 256_000_000_000, freeBytes: 91_000_000_000),
                      thermal: .nominal, cpuLoad: nil, memoryUsedBytes: nil,
                      memoryTotalBytes: 8_000_000_000, sampledAt: now)
    }
}
