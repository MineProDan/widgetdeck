import Foundation
import Testing
@testable import CoreKit

struct SampleSnapshot: WidgetSnapshot, Equatable {
    static var kind: WidgetKind { .battery }
    var level: Int
    var label: String
    var generatedAt: Date
}

struct OtherSnapshot: WidgetSnapshot, Equatable {
    static var kind: WidgetKind { .quote }
    var text: String
    var generatedAt: Date
}

struct BumpedSnapshot: WidgetSnapshot {
    static var kind: WidgetKind { .battery }
    static var schemaVersion: Int { 2 }
    var level: Int
    var label: String
    var generatedAt: Date
}

@Suite("SnapshotStore")
struct SnapshotStoreTests {
    let appGroup = AppGroupContainer.temporary()
    var store: SnapshotStore { SnapshotStore(appGroup: appGroup) }
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func roundTrip() throws {
        let snapshot = SampleSnapshot(level: 82, label: "Charging", generatedAt: date)
        try store.write(snapshot)
        #expect(store.read(SampleSnapshot.self) == snapshot)
    }

    @Test func missingSnapshotReadsNil() {
        #expect(store.read(SampleSnapshot.self) == nil)
    }

    @Test func overwriteReplacesContent() throws {
        try store.write(SampleSnapshot(level: 1, label: "a", generatedAt: date))
        try store.write(SampleSnapshot(level: 2, label: "b", generatedAt: date))
        #expect(store.read(SampleSnapshot.self)?.level == 2)
    }

    @Test func corruptFileReadsNilInsteadOfCrashing() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.url(for: SampleSnapshot.self))
        #expect(store.read(SampleSnapshot.self) == nil)
    }

    @Test func schemaVersionMismatchReadsNil() throws {
        try store.write(SampleSnapshot(level: 5, label: "old", generatedAt: date))
        #expect(store.read(BumpedSnapshot.self) == nil)
    }

    @Test func rejectsSnapshotsOver50KB() throws {
        let huge = SampleSnapshot(level: 0, label: String(repeating: "x", count: 60_000), generatedAt: date)
        #expect(throws: SnapshotError.tooLarge(fileName: "battery", bytes: try SnapshotStore.encode(huge).count)) {
            try store.write(huge)
        }
        #expect(store.read(SampleSnapshot.self) == nil)
    }

    @Test func failedOversizeWriteKeepsPreviousSnapshot() throws {
        let good = SampleSnapshot(level: 50, label: "ok", generatedAt: date)
        try store.write(good)
        _ = try? store.write(SampleSnapshot(level: 0, label: String(repeating: "x", count: 60_000), generatedAt: date))
        #expect(store.read(SampleSnapshot.self) == good)
    }

    @Test func writesAreAtomicUnderConcurrentReaders() async throws {
        // Readers racing a writer must only ever observe complete snapshots (old or new), never a
        // partial file: every successful read must decode to one of the written values.
        let store = self.store
        let date = self.date
        try store.write(SampleSnapshot(level: 0, label: String(repeating: "a", count: 20_000), generatedAt: date))
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for index in 1...200 {
                    try store.write(SampleSnapshot(level: index, label: String(repeating: "a", count: 20_000), generatedAt: date))
                }
            }
            for _ in 0..<4 {
                group.addTask {
                    for _ in 0..<200 {
                        let url = store.url(for: SampleSnapshot.self)
                        if let data = try? Data(contentsOf: url) {
                            let decoder = JSONDecoder()
                            decoder.dateDecodingStrategy = .secondsSince1970
                            #expect((try? decoder.decode(SnapshotEnvelope<SampleSnapshot>.self, from: data)) != nil)
                        }
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    @Test func staleness() {
        let snapshot = SampleSnapshot(level: 1, label: "", generatedAt: date)
        #expect(!snapshot.isStale(at: date.addingTimeInterval(60 * 60)))
        #expect(snapshot.isStale(at: date.addingTimeInterval(3 * 60 * 60)))
    }
}

/// Collects reload calls from the coordinator.
actor ReloadRecorder {
    private(set) var batches: [[String]] = []
    func record(_ kinds: [String]) { batches.append(kinds) }
}

@Suite("WidgetReloadCoordinator")
struct WidgetReloadCoordinatorTests {
    let store = SnapshotStore(appGroup: .temporary())
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeCoordinator(debounce: Duration, recorder: ReloadRecorder) -> WidgetReloadCoordinator {
        WidgetReloadCoordinator(store: store, unclampedDebounce: debounce) { await recorder.record($0) }
    }

    @Test func publicInitClampsDebounceToSixtySeconds() async throws {
        let recorder = ReloadRecorder()
        let coordinator = WidgetReloadCoordinator(store: store, debounce: .milliseconds(10)) { await recorder.record($0) }
        try await coordinator.publish(SampleSnapshot(level: 1, label: "a", generatedAt: date))
        try await Task.sleep(for: .milliseconds(300))
        #expect(await recorder.batches.isEmpty, "a 10 ms debounce must have been clamped to 60 s")
        #expect(await coordinator.pendingKinds == [.battery])
    }

    @Test func coalescesChangesWithinDebounceWindow() async throws {
        let recorder = ReloadRecorder()
        let coordinator = makeCoordinator(debounce: .milliseconds(200), recorder: recorder)
        try await coordinator.publish(SampleSnapshot(level: 1, label: "a", generatedAt: date))
        try await coordinator.publish(SampleSnapshot(level: 2, label: "b", generatedAt: date))
        try await coordinator.publish(OtherSnapshot(text: "hi", generatedAt: date))
        #expect(await recorder.batches.isEmpty)

        try await Task.sleep(for: .milliseconds(600))
        let batches = await recorder.batches
        #expect(batches.count == 1)
        #expect(batches.first == [WidgetKind.battery.kindIdentifier, WidgetKind.quote.kindIdentifier].sorted())
    }

    @Test func unchangedContentDoesNotReload() async throws {
        let recorder = ReloadRecorder()
        let coordinator = makeCoordinator(debounce: .milliseconds(100), recorder: recorder)
        let snapshot = SampleSnapshot(level: 1, label: "a", generatedAt: date)
        #expect(try await coordinator.publish(snapshot))
        await coordinator.flushNow()
        #expect(await recorder.batches.count == 1)

        // Same bytes again: no reload is scheduled.
        #expect(try await coordinator.publish(snapshot) == false)
        try await Task.sleep(for: .milliseconds(300))
        #expect(await recorder.batches.count == 1)
    }

    @Test func revertingToReloadedContentCancelsPendingReload() async throws {
        let recorder = ReloadRecorder()
        let coordinator = makeCoordinator(debounce: .milliseconds(150), recorder: recorder)
        let original = SampleSnapshot(level: 1, label: "a", generatedAt: date)
        try await coordinator.publish(original)
        await coordinator.flushNow()

        try await coordinator.publish(SampleSnapshot(level: 2, label: "b", generatedAt: date))
        try await coordinator.publish(original)
        #expect(await coordinator.pendingKinds.isEmpty)
        try await Task.sleep(for: .milliseconds(400))
        #expect(await recorder.batches.count == 1)
    }

    @Test func flushNowReloadsImmediately() async throws {
        let recorder = ReloadRecorder()
        let coordinator = makeCoordinator(debounce: .seconds(3600), recorder: recorder)
        try await coordinator.publish(OtherSnapshot(text: "x", generatedAt: date))
        await coordinator.flushNow()
        #expect(await recorder.batches == [[WidgetKind.quote.kindIdentifier]])
    }
}
