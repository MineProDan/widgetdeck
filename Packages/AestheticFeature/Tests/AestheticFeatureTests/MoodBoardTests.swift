import CoreGraphics
import CoreKit
import Foundation
import Testing
@testable import AestheticFeature
@testable import AestheticFeatureWidgetKit

// MARK: - Mood board layout (A-06)

@Suite("Mood board layout")
struct MoodBoardLayoutTests {
    @Test func gridShapes() {
        #expect(MoodBoardLayout.medium.tileCount == 4)
        #expect(MoodBoardLayout.large6.tileCount == 6)
        #expect(MoodBoardLayout.large8.tileCount == 8)
        #expect(MoodBoardLayout.forSlot(.medium, photoCount: 12) == .medium)
        #expect(MoodBoardLayout.forSlot(.large, photoCount: 7) == .large6)
        #expect(MoodBoardLayout.forSlot(.large, photoCount: 8) == .large8)
    }

    @Test func tilesFillTheWidgetWithGaps() {
        let container = CGSize(width: 338, height: 158)
        let frames = MoodBoardLayout.medium.tileFrames(in: container)
        #expect(frames.count == 4)
        #expect(frames[0].origin == .zero)
        #expect(abs(frames[3].maxX - container.width) < 0.001)
        #expect(abs(frames[3].maxY - container.height) < 0.001)
        #expect(abs(frames[1].minX - frames[0].maxX - MoodBoardLayout.gap) < 0.001)
        for layout in MoodBoardLayout.allCases {
            let large = layout.tileFrames(in: CGSize(width: 364, height: 382))
            #expect(abs(large.last!.maxX - 364) < 0.001 && abs(large.last!.maxY - 382) < 0.001)
        }
    }

    @Test func tilePixelSizesOnIPhone() {
        // iPhone 16 / 17 class (390 × 844 pt @3x): medium widget 338 × 158 pt → tile 167.5 × 77.5 pt.
        let px = MoodBoardLayout.medium.tilePixels(screen: CGSize(width: 390, height: 844), scale: 3)
        #expect(px == PixelSize(width: 503, height: 233))
        // Every tile is smaller than the whole widget (never upscaled, never a full-size decode).
        for layout in MoodBoardLayout.allCases {
            let tile = layout.tilePixels(screen: CGSize(width: 440, height: 956), scale: 3)
            let widget = PhotoWidgetSize.pixels(for: layout.slot, screen: CGSize(width: 440, height: 956), scale: 3)
            #expect(tile.width < widget.width && tile.height < widget.height)
        }
    }

    @Test func largestBoardFitsTheWidgetMemoryBudget() {
        let tile = MoodBoardLayout.large8.tilePixels(screen: CGSize(width: 440, height: 956), scale: 3)
        let bytes = tile.width * tile.height * 4 * MoodBoardLayout.large8.tileCount
        #expect(bytes < 8 * 1_024 * 1_024)
    }
}

// MARK: - Mood board timeline

@Suite("Mood board timeline")
struct MoodBoardTimelineTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func items(_ n: Int) -> [MoodBoardItem] {
        (0..<n).map { MoodBoardItem(addedAt: Date(timeIntervalSinceReferenceDate: Double($0)), files: [.medium: "\($0).jpg"]) }
    }

    @Test func emptyAndUnshuffledNeverReload() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let empty = MoodBoardTimelineBuilder.timeline(snapshot: nil, style: .default, now: now, calendar: calendar)
        #expect(empty.entries.count == 1 && empty.entries[0].photos.isEmpty && empty.policy == .never)
        let board = MoodBoardSnapshot(photos: items(5), shuffleDaily: false, generatedAt: now)
        let fixed = MoodBoardTimelineBuilder.timeline(snapshot: board, style: .default, now: now, calendar: calendar)
        #expect(fixed.entries.count == 1 && fixed.entries[0].photos == board.photos && fixed.policy == .never)
    }

    @Test func shuffleGivesAWeekOfDailyArrangements() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let board = MoodBoardSnapshot(photos: items(8), shuffleDaily: true, generatedAt: now)
        let timeline = MoodBoardTimelineBuilder.timeline(snapshot: board, style: .default, now: now, calendar: calendar)
        #expect(timeline.entries.count == MoodBoardTimelineBuilder.shuffleDays)
        #expect(timeline.entries[0].date == now)
        for entry in timeline.entries.dropFirst() {
            #expect(entry.date == calendar.startOfDay(for: entry.date))
        }
        for entry in timeline.entries {
            #expect(Set(entry.photos.map(\.id)) == Set(board.photos.map(\.id)))
        }
        #expect(Set(timeline.entries.map { $0.photos.map(\.id) }).count > 1)
        // The same day gives the same arrangement in every timeline.
        let later = MoodBoardTimelineBuilder.timeline(snapshot: board, style: .default, now: now.addingTimeInterval(3_600),
                                                      calendar: calendar)
        #expect(later.entries[0].photos == timeline.entries[0].photos)
    }
}

// MARK: - Mood board import + store

@Suite("Mood board import")
struct MoodBoardImportTests {
    @Test func importWritesExactTilePixelSizes() async throws {
        let files = Fixture.tempFiles()
        defer { try? FileManager.default.removeItem(at: files.root) }
        let screen = CGSize(width: 390, height: 844)
        let library = MoodBoardLibrary(files: files, screen: screen, scale: 3)
        let item = try await library.importPhoto(Fixture.beach, existingCount: 0, now: .now)
        #expect(item.files.count == MoodBoardLayout.allCases.count)
        for layout in MoodBoardLayout.allCases {
            let url = files.moodBoardURL(for: try #require(item.files[layout]))
            let size = try #require(Fixture.pixelSize(of: url))
            let expected = layout.tilePixels(screen: screen, scale: 3)
            #expect(size.0 == expected.width && size.1 == expected.height)
        }
        await library.delete(item)
        for name in item.files.values {
            #expect(!FileManager.default.fileExists(atPath: files.moodBoardURL(for: name).path(percentEncoded: false)))
        }
    }

    @Test func limitAndJunk() async {
        let files = Fixture.tempFiles()
        defer { try? FileManager.default.removeItem(at: files.root) }
        let library = MoodBoardLibrary(files: files, screen: CGSize(width: 390, height: 844), scale: 2)
        await #expect(throws: PhotoLibrary.Error.limitReached(MoodBoardLibrary.maxPhotos)) {
            try await library.importPhoto(Fixture.beach, existingCount: MoodBoardLibrary.maxPhotos, now: .now)
        }
        await #expect(throws: PhotoLibrary.Error.unreadable) {
            try await library.importPhoto(Data([1, 2, 3]), existingCount: 0, now: .now)
        }
    }

    @Test @MainActor func storeEditsPublishASnapshot() async throws {
        let files = Fixture.tempFiles()
        let snapshots = SnapshotStore(appGroup: AppGroupContainer(rootURL: files.root))
        defer { try? FileManager.default.removeItem(at: files.root) }
        let log = ReloadLog()
        let store = AestheticStore(files: files, snapshots: snapshots, reload: { await log.add($0) })
        await store.importMoodBoardPhotos([Fixture.beach, Fixture.beach, Fixture.beach],
                                          screen: CGSize(width: 390, height: 844), scale: 2)
        #expect(store.moodBoard.count == 3)
        #expect(await log.kinds.last == [WidgetKind.moodBoard.kindIdentifier])

        let first = store.moodBoard[0]
        await store.moveMoodBoardPhoto(first, by: 1)
        #expect(store.moodBoard[1].id == first.id)
        await store.moveMoodBoardPhoto(first, by: 5)
        #expect(store.moodBoard.last?.id == first.id)
        await store.setShuffleDaily(true)

        let snapshot = try #require(snapshots.read(MoodBoardSnapshot.self))
        #expect(snapshot.photos.map(\.id) == store.moodBoard.map(\.id) && snapshot.shuffleDaily)
        #expect(try SnapshotStore.encode(snapshot).count < SnapshotStore.maxSize)

        await store.removeMoodBoardPhoto(first)
        #expect(snapshots.read(MoodBoardSnapshot.self)?.photos.count == 2)

        let relaunched = AestheticStore(files: files, snapshots: snapshots, reload: { _ in })
        await relaunched.load()
        #expect(relaunched.moodBoard.map(\.id) == store.moodBoard.map(\.id) && relaunched.shuffleDaily)
    }
}

// MARK: - Borders and effects (A-07)

@Suite("Widget styles")
struct WidgetStyleTests {
    @Test func defaultsAreQuiet() {
        let style = WidgetStyle.default
        #expect(!style.border && style.dim == .none && style.corners == .rounded)
        let all = AestheticStyleSnapshot()
        for target in AestheticStyleTarget.allCases { #expect(all[target] == .default) }
        #expect(!AestheticStyleTarget.palette.supportsDim)
    }

    @Test func roundTrips() throws {
        var snapshot = AestheticStyleSnapshot()
        snapshot[.moodBoard] = WidgetStyle(border: true, borderColor: .themeAccent, borderWidth: .thick,
                                           corners: .square, dim: .medium)
        snapshot[.palette].border = true
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AestheticStyleSnapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.photo == .default)
    }

    @Test func missingAndUnknownValuesFallBackToDefaults() throws {
        let json = #"{"moodBoard": {"border": true, "borderColor": "neonGlow", "dim": "light"}}"#
        let decoded = try JSONDecoder().decode(AestheticStyleSnapshot.self, from: Data(json.utf8))
        #expect(decoded.moodBoard.border)
        #expect(decoded.moodBoard.borderColor == WidgetStyle.default.borderColor)
        #expect(decoded.moodBoard.dim == .light)
        #expect(decoded.photo == .default && decoded.palette == .default)
    }

    @Test func styleTokens() {
        #expect(WidgetBorderWidth.allCases.map(\.points) == [4, 8, 12])
        #expect(WidgetDim.none.opacity == 0 && WidgetDim.medium.opacity < 0.5)
        #expect(WidgetCornerStyle.square.radius == 0)
        #expect(AestheticStyleSnapshot.fileName != WidgetKind.photo.rawValue)
    }

    @Test @MainActor func storeWritesTheStyleFileAndReloadsThatWidget() async throws {
        let files = Fixture.tempFiles()
        let snapshots = SnapshotStore(appGroup: AppGroupContainer(rootURL: files.root))
        defer { try? FileManager.default.removeItem(at: files.root) }
        let log = ReloadLog()
        let store = AestheticStore(files: files, snapshots: snapshots, reload: { await log.add($0) })
        await store.setStyle(WidgetStyle(border: true, borderColor: .ink), for: .photo)
        #expect(AestheticStyleSnapshot.load(store: snapshots).photo.borderColor == .ink)
        #expect(await log.kinds.last == [WidgetKind.photo.kindIdentifier])
        // Photo snapshot and style file don't collide.
        #expect(snapshots.read(PhotoSnapshot.self) == nil)

        let relaunched = AestheticStore(files: files, snapshots: snapshots, reload: { _ in })
        await relaunched.load()
        #expect(relaunched.styles.photo.border)
    }
}
