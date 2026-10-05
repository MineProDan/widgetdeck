import CoreData
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CoreKit

@Suite("KeychainStore", .serialized)
struct KeychainStoreTests {
    // nil access group: the test host has no keychain-sharing entitlement.
    let keychain = KeychainStore(service: "corekit.tests.\(UUID().uuidString)", accessGroup: nil, backend: InMemoryKeychainBackend())

    @Test func createReadUpdateDelete() throws {
        defer { try? keychain.deleteAll() }
        #expect(try keychain.data(for: "token") == nil)

        try keychain.setString("abc", for: "token")
        #expect(try keychain.string(for: "token") == "abc")

        try keychain.setString("def", for: "token")
        #expect(try keychain.string(for: "token") == "def")

        try keychain.delete("token")
        #expect(try keychain.string(for: "token") == nil)
        // Deleting a missing item is not an error.
        try keychain.delete("token")
    }

    @Test func codableRoundTripAndDeleteAll() throws {
        struct Token: Codable, Equatable { let access: String; let expires: Date }
        defer { try? keychain.deleteAll() }
        let token = Token(access: "a1", expires: Date(timeIntervalSince1970: 1_900_000_000))
        try keychain.setCodable(token, for: "pinterest")
        try keychain.setString("x", for: "other")
        #expect(try keychain.codable(Token.self, for: "pinterest") == token)

        try keychain.deleteAll()
        #expect(try keychain.data(for: "pinterest") == nil)
        #expect(try keychain.data(for: "other") == nil)
    }

    @Test func servicesAreIsolated() throws {
        let backend = InMemoryKeychainBackend()
        let mine = KeychainStore(service: "corekit.tests.mine", accessGroup: nil, backend: backend)
        let other = KeychainStore(service: "corekit.tests.other", accessGroup: nil, backend: backend)
        try mine.setString("mine", for: "k")
        #expect(try other.string(for: "k") == nil)
        try other.deleteAll()
        #expect(try mine.string(for: "k") == "mine")
    }
}

@Suite("Persistence")
struct PersistenceTests {
    @Test func coreModelPassesCloudKitRules() throws {
        let model = try PersistenceModel.make()
        let cloud = model.entities(forConfigurationName: StoreConfiguration.cloud.rawValue) ?? []
        #expect(Set(cloud.compactMap(\.name)) == [
            PersistenceModel.Entity.theme, PersistenceModel.Entity.userProfile, PersistenceModel.Entity.widgetConfiguration
        ])
        let local = model.entities(forConfigurationName: StoreConfiguration.local.rawValue) ?? []
        #expect(local.compactMap(\.name) == [PersistenceModel.Entity.localCacheEntry])
        let profile = try #require(model.entitiesByName[PersistenceModel.Entity.userProfile])
        #expect(profile.attributesByName[PersistenceModel.Attribute.payload]?.allowsCloudEncryption == true)
    }

    @Test func validationRejectsNonOptionalAttributes() {
        let entity = PayloadEntity.make(name: "Bad")
        let attribute = NSAttributeDescription()
        attribute.name = "required"
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = false
        entity.properties.append(attribute)
        #expect(throws: PersistenceModel.ValidationError.nonOptionalAttribute(entity: "Bad", attribute: "required")) {
            try PersistenceModel.validate([entity])
        }
    }

    enum Contributor: PersistenceModelContributor {
        static func makeEntities() -> [StoreConfiguration: [NSEntityDescription]] {
            [.local: [PayloadEntity.make(name: "MetricSample")]]
        }
    }

    @Test func contributorsAddEntities() throws {
        let model = try PersistenceModel.make(contributors: [Contributor.self])
        #expect(model.entities(forConfigurationName: "Local")?.contains { $0.name == "MetricSample" } == true)
    }

    @Test func recordStoreCRUDAndDedupe() async throws {
        let stack = try await CoreDataStack.load(mode: .inMemory)
        let store = RecordStore<Theme>(stack: stack)
        var theme = Theme(name: "Sunset", palette: [.accent: RGBAColor(hex: "#FF7A59")!], updatedAt: Date(timeIntervalSince1970: 10))
        try await store.upsert(theme)
        #expect(try await store.fetch(id: theme.id)?.name == "Sunset")

        theme.name = "Dusk"
        theme.updatedAt = Date(timeIntervalSince1970: 20)
        try await store.upsert(theme)
        #expect(try await store.fetchAll().map(\.name) == ["Dusk"])

        // Simulate a CloudKit duplicate: same id inserted directly with an older timestamp.
        let stale = try JSONEncoder().encode(Theme(id: theme.id, name: "Stale", palette: [:], updatedAt: Date(timeIntervalSince1970: 5)))
        let themeID = theme.id
        try await stack.performBackgroundTask { context in
            let object = NSEntityDescription.insertNewObject(forEntityName: Theme.entityName, into: context)
            object.setValue(themeID, forKey: "id")
            object.setValue(Date(timeIntervalSince1970: 5), forKey: "updatedAt")
            object.setValue(stale, forKey: "payload")
        }
        #expect(try await store.fetchAll().map(\.name) == ["Dusk"], "reads return the newest copy")
        #expect(try await DeduplicationService(stack: stack).run() == 1)
        #expect(try await DeduplicationService(stack: stack).run() == 0)

        try await store.delete(id: theme.id)
        #expect(try await store.fetchAll().isEmpty)
    }

    @Test func deleteAllObjectsEmptiesStores() async throws {
        let stack = try await CoreDataStack.load(mode: .inMemory)
        try await RecordStore<UserProfile>(stack: stack).upsert(UserProfile(displayName: "Sam"))
        try await RecordStore<WidgetSettings>(stack: stack).upsert(WidgetSettings(kind: .battery, family: .systemSmall))
        try await stack.deleteAllObjects()
        #expect(try await RecordStore<UserProfile>(stack: stack).fetchAll().isEmpty)
        #expect(try await RecordStore<WidgetSettings>(stack: stack).fetchAll().isEmpty)
    }

    @Test func exportWritesJSON() async throws {
        let stack = try await CoreDataStack.load(mode: .inMemory)
        let appGroup = AppGroupContainer.temporary()
        try await RecordStore<Theme>(stack: stack).upsert(Theme(name: "Mint", palette: [.primary: .white]))
        let url = try await DataExporter(stack: stack, appGroup: appGroup).export()
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect((json?["themes"] as? [[String: Any]])?.first?["name"] as? String == "Mint")
    }
}

@Suite("Models")
struct ModelTests {
    @Test func hexParsingAndFormatting() throws {
        #expect(RGBAColor(hex: "#FFF") == .white)
        #expect(RGBAColor(hex: "000000") == .black)
        #expect(RGBAColor(hex: "#11223380")?.hexString == "#11223380")
        #expect(RGBAColor(hex: "#12345") == nil)
        #expect(RGBAColor(hex: "zzzzzz") == nil)
    }

    @Test func themeCodableUsesHexAndRoleKeys() throws {
        let theme = Theme(name: "T", palette: [.background: RGBAColor(hex: "#101820")!])
        let json = try #require(String(data: JSONEncoder().encode(theme), encoding: .utf8))
        #expect(json.contains(##""background":"#101820""##))
        #expect(try JSONDecoder().decode(Theme.self, from: Data(json.utf8)) == theme)
    }

    @Test func sectionDeepLinkRoundTrip() {
        for section in AppSection.allCases {
            #expect(AppSection(deepLink: section.deepLink) == section)
        }
        #expect(AppSection(deepLink: URL(string: "https://example.com/section/tech")!) == nil)
    }
}

@Suite("Imaging")
struct ImagingTests {
    /// A solid-color test image of `width`×`height`, encoded as PNG (optionally with EXIF orientation).
    static func makeImageData(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func aspectFitLimitsLongestSide() throws {
        let image = try Downsampler.downsample(data: Self.makeImageData(width: 1200, height: 800), maxPixelSize: 300)
        #expect(image.width == 300)
        #expect(image.height == 200)
    }

    @Test func neverUpsamples() throws {
        let image = try Downsampler.downsample(data: Self.makeImageData(width: 100, height: 50), maxPixelSize: 1000)
        #expect(image.width == 100 && image.height == 50)
    }

    @Test(arguments: [
        (1200, 800, PixelSize(width: 338, height: 338)),   // small widget @2x-ish
        (800, 1200, PixelSize(width: 720, height: 338)),   // medium, portrait source
        (4032, 3024, PixelSize(width: 1107, height: 1107)),
        (100, 60, PixelSize(width: 300, height: 300))      // source smaller than target
    ])
    func aspectFillProducesExactSize(sourceWidth: Int, sourceHeight: Int, target: PixelSize) throws {
        let image = try Downsampler.downsample(data: Self.makeImageData(width: sourceWidth, height: sourceHeight), toFill: target)
        #expect(image.width == target.width)
        #expect(image.height == target.height)
    }

    @Test func respectsExifRotation() throws {
        // Orientation 6 = rotated 90°: a 400×200 buffer displays as 200×400.
        let data = try Self.makeImageData(width: 400, height: 200, orientation: 6)
        #expect(try Downsampler.pixelSize(of: data) == PixelSize(width: 200, height: 400))
        let image = try Downsampler.downsample(data: data, maxPixelSize: 100)
        #expect(image.width == 50 && image.height == 100)
    }

    @Test func rejectsGarbage() {
        #expect(throws: Downsampler.Error.unreadableSource) {
            try Downsampler.downsample(data: Data("nope".utf8), maxPixelSize: 10)
        }
    }

    @Test func encodesJPEG() throws {
        let image = try Downsampler.downsample(data: Self.makeImageData(width: 64, height: 64), maxPixelSize: 64)
        let data = try Downsampler.encode(image, format: .jpeg)
        #expect(try Downsampler.pixelSize(of: data) == PixelSize(width: 64, height: 64))
    }

    @Test func pixelSizeFromPoints() {
        #expect(PixelSize(points: CGSize(width: 170, height: 170), scale: 3) == PixelSize(width: 510, height: 510))
    }
}

/// Manually advanced wall clock for cache recency.
final class DateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value.addTimeInterval(seconds) } }
}

@Suite("ImageCache")
struct ImageCacheTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "ImageCache-\(UUID().uuidString)")

    @Test func storeAndRead() async throws {
        let cache = ImageCache(directory: directory, capacity: 1_000)
        try await cache.store(Data([1, 2, 3]), forKey: "a")
        #expect(await cache.data(forKey: "a") == Data([1, 2, 3]))
        #expect(await cache.contains("a"))
        #expect(await cache.data(forKey: "missing") == nil)
    }

    @Test func evictsLeastRecentlyUsedOverCapacity() async throws {
        let clock = DateBox()
        let cache = ImageCache(directory: directory, capacity: 250, now: { clock.now })
        let blob = Data(repeating: 7, count: 100)

        try await cache.store(blob, forKey: "a"); clock.advance(10)
        try await cache.store(blob, forKey: "b"); clock.advance(10)
        _ = await cache.data(forKey: "a"); clock.advance(10)  // "a" is now more recent than "b"
        try await cache.store(blob, forKey: "c")               // 300 > 250: evict LRU ("b")

        #expect(await cache.contains("a"))
        #expect(await cache.contains("b") == false)
        #expect(await cache.contains("c"))
        #expect(await cache.totalSize() == 200)
    }

    @Test func neverEvictsTheEntryJustStored() async throws {
        let cache = ImageCache(directory: directory, capacity: 50)
        try await cache.store(Data(repeating: 1, count: 80), forKey: "big")
        #expect(await cache.contains("big"))
    }

    @Test func keyIncludesFamilyAndSize() {
        let small = ImageCache.key(assetID: "x", family: .systemSmall, pixelSize: PixelSize(width: 338, height: 338))
        let medium = ImageCache.key(assetID: "x", family: .systemMedium, pixelSize: PixelSize(width: 720, height: 338))
        #expect(small != medium)
    }

    @Test func removeAll() async throws {
        let cache = ImageCache(directory: directory, capacity: 1_000)
        try await cache.store(Data([1]), forKey: "a")
        await cache.removeAll()
        #expect(await cache.totalSize() == 0)
    }
}
