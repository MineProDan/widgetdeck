import CoreGraphics
import CoreKit
import DesignSystem
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AestheticFeature
@testable import AestheticFeatureWidgetKit

// MARK: - Fixtures

enum Fixture {
    /// Horizontal colour bands (top to bottom) with the given pixel heights, as PNG data.
    static func bands(_ bands: [(hex: String, rows: Int)], width: Int = 200) -> Data {
        let height = bands.reduce(0) { $0 + $1.rows }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var y = height
        for band in bands {
            let c = RGBAColor(hex: band.hex)!
            context.setFillColor(CGColor(colorSpace: space, components: [c.red, c.green, c.blue, 1])!)
            y -= band.rows
            context.fill(CGRect(x: 0, y: y, width: width, height: band.rows))
        }
        return png(context.makeImage()!)
    }

    static func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// The mockup's beach sunset, as flat bands.
    static let beach = bands([("#F6DDB2", 90), ("#F2CC8F", 70), ("#E07A5F", 40), ("#5B6C8F", 30), ("#3D405B", 70)])

    static func distance(_ a: RGBAColor, _ b: RGBAColor) -> Double {
        let dr = a.red - b.red, dg = a.green - b.green, db = a.blue - b.blue
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    static func pixelSize(of url: URL) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    static func tempFiles() -> AestheticFiles {
        AestheticFiles(root: FileManager.default.temporaryDirectory.appending(path: "aesthetic-tests-\(UUID().uuidString)"))
    }
}

// MARK: - Palette extraction (A-02)

@Suite("Palette extraction")
struct PaletteExtractionTests {
    @Test func findsTheFiveBeachColours() throws {
        let clusters = try PaletteExtractor.extract(from: Fixture.beach)
        #expect(clusters.count == 5)
        for hex in ["#F6DDB2", "#F2CC8F", "#E07A5F", "#5B6C8F", "#3D405B"] {
            let expected = RGBAColor(hex: hex)!
            let nearest = clusters.map { Fixture.distance($0.color, expected) }.min()!
            #expect(nearest < 0.06, "No cluster near \(hex): \(clusters.map(\.color))")
        }
        // Edge blends (< 3 %) are dropped, so the kept weights cover almost the whole image.
        #expect(clusters.map(\.weight).reduce(0, +) > 0.97)
    }

    @Test func isDeterministic() throws {
        #expect(try PaletteExtractor.extract(from: Fixture.beach) == PaletteExtractor.extract(from: Fixture.beach))
    }

    @Test func swiftFallbackMatchesClusters() throws {
        let pixels = [PaletteExtractor.RGB](repeating: .init(1, 0, 0), count: 50) + .init(repeating: .init(0, 0, 1), count: 50)
        let centres = PaletteExtractor.lloyd(pixels, seeds: PaletteExtractor.farthestPointSeeds(pixels, count: 2))
        #expect(Set(centres.map { [$0.x, $0.y, $0.z] }) == [[1, 0, 0], [0, 0, 1]])
    }

    @Test func twoColourImageIsPaddedToFive() throws {
        let clusters = try PaletteExtractor.extract(from: Fixture.bands([("#81B29A", 100), ("#FFFFFF", 100)]))
        #expect(clusters.count == 5)
        #expect(Set(clusters.map(\.color)).count == 5)
    }

    @Test func unreadableDataThrows() {
        #expect(throws: PaletteExtractor.Error.unreadableImage) { try PaletteExtractor.extract(from: Data([1, 2, 3])) }
    }
}

// MARK: - Roles, names, contrast

@Suite("Theme Sync roles")
struct RoleAssignmentTests {
    @Test func beachGetsTheMockupRolesAndNames() throws {
        let palette = try #require(RoleAssigner.assign(PaletteExtractor.extract(from: Fixture.beach)))
        #expect(palette.rows.map(\.color.name) == ["Shell", "Dune", "Coral Hour", "Evening Sea", "Deep Tide"])
        #expect(palette.name == "Beach Hour")
        #expect(palette.contrastChecked)
    }

    @Test func darkestIsTextAndMostVividIsAccent() throws {
        let colors = ["#FFFFFF", "#DDDDDD", "#20B040", "#777777", "#111111"].map { ColorCluster(color: RGBAColor(hex: $0)!, weight: 0.2) }
        let palette = try #require(RoleAssigner.assign(colors))
        #expect(palette.text.color.hexString == "#111111")
        #expect(palette.accent.color.hexString == "#20B040")
        #expect(palette.surface.color.hexString == "#FFFFFF")
        #expect(palette.background.color.hexString == "#DDDDDD")
        #expect(palette.primary.color.hexString == "#777777")
        #expect(palette.name == "Moss Field")
    }

    @Test func lowContrastTextIsFixedUp() throws {
        // All mid-tones: the "text" colour fails 4.5:1 on the background until fixed.
        let colors = ["#B0B0B0", "#A8A8A8", "#C08080", "#A0A0A0", "#909090"].map { ColorCluster(color: RGBAColor(hex: $0)!, weight: 0.2) }
        let palette = try #require(RoleAssigner.assign(colors))
        #expect(!ContrastChecker.meets(palette.text.color, on: palette.background.color))
        #expect(ContrastChecker.meets(palette.textOnBackground, on: palette.background.color))
        #expect(ContrastChecker.meets(palette.textOnBackground, on: palette.surface.color))
        #expect(ContrastChecker.meets(palette.textOnAccent, on: palette.accent.color))
        #expect(palette.contrastChecked)
    }

    @Test func namesNeverRepeat() {
        let names = PaintNamer.names(for: Array(repeating: RGBAColor(hex: "#E07A5F")!, count: 5))
        #expect(Set(names).count == 5)
        #expect(names[0] == "Coral Hour")
    }

    @Test func themeCarriesRolesAndSource() throws {
        let palette = try #require(RoleAssigner.assign(PaletteExtractor.extract(from: Fixture.beach)))
        let id = UUID()
        let theme = palette.theme(id: id, now: .now)
        #expect(theme.id == id && theme.source == .wallpaper && theme.name == "Beach Hour")
        #expect(Set(theme.palette.keys) == Set(ColorRole.allCases))
    }

    @Test func snapshotRoundTripsAndIsSmall() throws {
        let palette = try #require(RoleAssigner.assign(PaletteExtractor.extract(from: Fixture.beach)))
        let snapshot = palette.snapshot(now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try SnapshotStore.encode(snapshot).count < 2_000)
        let restored = try #require(ExtractedPalette(snapshot: snapshot))
        #expect(restored.rows.map(\.color.name) == palette.rows.map(\.color.name))
        #expect(restored.rows.map(\.color.color.hexString) == palette.rows.map(\.color.color.hexString))
    }
}

// MARK: - Photo rotation (A-01)

@Suite("Photo timeline")
struct PhotoTimelineTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    func snapshot(count: Int, rotation: PhotoRotation) -> PhotoSnapshot {
        PhotoSnapshot(photos: (0..<count).map { _ in PhotoItem(addedAt: .now, files: [.small: "x.jpg"]) },
                      rotation: rotation, generatedAt: .now)
    }

    func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return formatter.date(from: string)!
    }

    @Test func dailyEntriesStartAtEachMidnight() {
        let now = date("2026-10-05T15:30:00")
        let timeline = PhotoTimelineBuilder.timeline(snapshot: snapshot(count: 3, rotation: .daily), now: now, calendar: calendar)
        #expect(timeline.entries.count == 7)
        #expect(timeline.entries[0].date == now)
        #expect(timeline.entries[1].date == date("2026-10-06T00:00:00"))
        let positions = timeline.entries.map(\.position)
        #expect(Set(positions) == [1, 2, 3])
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 != $1 })
        #expect(timeline.policy == .after(date("2026-10-12T00:00:00")))
    }

    @Test func dailyRotationIsDSTSafe() {
        // US fall-back: 2026-11-01 has 25 hours. Each entry must still land on local midnight.
        let now = date("2026-10-30T12:00:00")
        let entries = PhotoTimelineBuilder.timeline(snapshot: snapshot(count: 5, rotation: .daily), now: now, calendar: calendar).entries
        for entry in entries.dropFirst() {
            #expect(calendar.dateComponents([.hour, .minute], from: entry.date) == DateComponents(hour: 0, minute: 0))
        }
        let indices = entries.map { PhotoTimelineBuilder.periodIndex(of: $0.date, rotation: .daily, calendar: calendar) }
        #expect(zip(indices, indices.dropFirst()).allSatisfy { $1 == $0 + 1 })
    }

    @Test func hourlyGivesADayOfEntries() {
        let now = date("2026-10-05T15:30:00")
        let timeline = PhotoTimelineBuilder.timeline(snapshot: snapshot(count: 4, rotation: .hourly), now: now, calendar: calendar)
        #expect(timeline.entries.count == 24)
        #expect(timeline.entries[1].date == date("2026-10-05T16:00:00"))
        #expect(timeline.policy == .after(date("2026-10-06T15:00:00")))
    }

    @Test func samePeriodSamePhotoAcrossTimelines() {
        let morning = PhotoTimelineBuilder.photoIndex(at: date("2026-10-05T08:00:00"), count: 7, rotation: .daily, calendar: calendar)
        let evening = PhotoTimelineBuilder.photoIndex(at: date("2026-10-05T23:00:00"), count: 7, rotation: .daily, calendar: calendar)
        let tomorrow = PhotoTimelineBuilder.photoIndex(at: date("2026-10-06T00:10:00"), count: 7, rotation: .daily, calendar: calendar)
        #expect(morning == evening)
        #expect(tomorrow == (morning + 1) % 7)
    }

    @Test func emptyAndSinglePhotoNeverReload() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let empty = PhotoTimelineBuilder.timeline(snapshot: nil, now: now)
        #expect(empty.entries.count == 1 && empty.entries[0].photo == nil && empty.policy == .never)
        let single = PhotoTimelineBuilder.timeline(snapshot: snapshot(count: 1, rotation: .hourly), now: now)
        #expect(single.entries.count == 1 && single.entries[0].photo != nil && single.policy == .never)
    }
}

// MARK: - Downsampling at import

@Suite("Photo import")
struct PhotoImportTests {
    @Test func widgetSizesComeFromTheTable() {
        let pro = CGSize(width: 402, height: 874)
        #expect(PhotoWidgetSize.points(for: .small, screen: CGSize(width: 390, height: 844)) == CGSize(width: 158, height: 158))
        #expect(PhotoWidgetSize.points(for: .large, screen: CGSize(width: 844, height: 390)) == CGSize(width: 338, height: 354))
        // Unlisted screens use the next wider row, so images are never upscaled.
        #expect(PhotoWidgetSize.points(for: .medium, screen: pro) == CGSize(width: 360, height: 169))
        #expect(PhotoWidgetSize.pixels(for: .small, screen: pro, scale: 3) == PixelSize(width: 507, height: 507))
    }

    @Test func importWritesExactPixelSizesPerSlot() async throws {
        let files = Fixture.tempFiles()
        defer { try? FileManager.default.removeItem(at: files.root) }
        let screen = CGSize(width: 390, height: 844)
        let library = PhotoLibrary(files: files, screen: screen, scale: 3)
        let item = try await library.importPhoto(Fixture.bands([("#E07A5F", 900), ("#3D405B", 900)], width: 1200),
                                                 existingCount: 0, now: .now)
        for slot in PhotoSlot.allCases {
            let expected = PhotoWidgetSize.pixels(for: slot, screen: screen, scale: 3)
            let name = try #require(item.files[slot])
            let size = try #require(Fixture.pixelSize(of: files.url(for: name)))
            #expect(size.0 == expected.width && size.1 == expected.height, "\(slot): \(size)")
        }
        await library.delete(item)
        #expect(item.files.values.allSatisfy { !FileManager.default.fileExists(atPath: files.url(for: $0).path) })
    }

    @Test func importRespectsTheLimitAndRejectsJunk() async {
        let library = PhotoLibrary(files: Fixture.tempFiles(), screen: CGSize(width: 390, height: 844), scale: 2)
        await #expect(throws: PhotoLibrary.Error.limitReached(PhotoLibrary.maxPhotos)) {
            try await library.importPhoto(Fixture.beach, existingCount: PhotoLibrary.maxPhotos, now: .now)
        }
        await #expect(throws: PhotoLibrary.Error.unreadable) {
            try await library.importPhoto(Data([0, 1, 2]), existingCount: 0, now: .now)
        }
    }
}

// MARK: - Store

private actor RecordingThemes: ThemeRepository {
    private(set) var applied: [Theme] = []
    func applyTheme(_ theme: Theme) async throws { applied.append(theme) }
}

actor ReloadLog {
    private(set) var kinds: [[String]] = []
    func add(_ value: [String]) { kinds.append(value) }
}

@Suite("Aesthetic store")
@MainActor
struct AestheticStoreTests {
    @Test func pickThenApplySavesThemeWritesSnapshotAndReloads() async throws {
        let files = Fixture.tempFiles()
        let snapshots = SnapshotStore(appGroup: AppGroupContainer(rootURL: files.root))
        defer { try? FileManager.default.removeItem(at: files.root) }
        let themes = RecordingThemes()
        let log = ReloadLog()
        let store = AestheticStore(themes: themes, files: files, snapshots: snapshots, reload: { await log.add($0) })

        await store.pickWallpaper(Fixture.beach)
        #expect(store.palette?.name == "Beach Hour")
        #expect(store.hasUnappliedPalette)
        #expect(store.wallpaper != nil)

        await store.applyPalette()
        #expect(!store.hasUnappliedPalette)
        #expect(await themes.applied.count == 1)
        #expect(snapshots.read(PaletteSnapshot.self)?.name == "Beach Hour")
        #expect(await log.kinds.last?.count == WidgetKind.allCases.count)

        // A re-sync replaces the same wallpaper theme instead of adding another.
        await store.applyPalette()
        await store.pickWallpaper(Fixture.bands([("#81B29A", 100), ("#FFFFFF", 100)]))
        await store.applyPalette()
        let ids = await themes.applied.map(\.id)
        #expect(Set(ids).count == 1)

        // Restored on the next launch.
        let relaunched = AestheticStore(themes: themes, files: files, snapshots: snapshots, reload: { _ in })
        await relaunched.load()
        #expect(relaunched.appliedPalette == store.appliedPalette)
    }

    @Test func badWallpaperShowsAnError() async {
        let files = Fixture.tempFiles()
        let store = AestheticStore(files: files, snapshots: SnapshotStore(appGroup: AppGroupContainer(rootURL: files.root)),
                                   reload: { _ in })
        await store.pickWallpaper(Data([9, 9, 9]))
        guard case .failed = store.syncPhase else {
            Issue.record("Expected failure, got \(store.syncPhase)")
            return
        }
        #expect(store.palette == nil)
    }

    @Test func photosPublishASnapshot() async throws {
        let files = Fixture.tempFiles()
        let snapshots = SnapshotStore(appGroup: AppGroupContainer(rootURL: files.root))
        defer { try? FileManager.default.removeItem(at: files.root) }
        let store = AestheticStore(files: files, snapshots: snapshots, reload: { _ in })
        await store.importPhotos([Fixture.beach, Fixture.beach], screen: CGSize(width: 390, height: 844), scale: 2)
        #expect(store.photos.count == 2)
        await store.setRotation(.hourly)
        let snapshot = try #require(snapshots.read(PhotoSnapshot.self))
        #expect(snapshot.photos.count == 2 && snapshot.rotation == .hourly)
        #expect(try SnapshotStore.encode(snapshot).count < SnapshotStore.maxSize)
        await store.removePhoto(store.photos[0])
        #expect(snapshots.read(PhotoSnapshot.self)?.photos.count == 1)
    }

    @Test func moduleBelongsToAestheticSection() {
        #expect(AestheticWidgetModule.section == .aesthetic)
    }
}
