import AestheticFeatureWidgetKit
import CoreGraphics
import CoreKit
import DesignSystem
import Foundation
import ImageIO
import StudentFeatureWidgetKit
import SwiftUI
import TechFeatureWidgetKit
import Testing
import UniformTypeIdentifiers
import WidgetKit

/// Structural render matrix for every widget view: widget × family size × light/dark × Dynamic
/// Type (XS, L, AX3). Each cell must render, be non-blank and stay far below the widget memory
/// ceiling.
///
/// Limits (why this is not a pixel snapshot test):
/// - `\.widgetFamily` and `\.widgetRenderingMode` are read-only environment values, so offscreen
///   `ImageRenderer` always takes the view's default (`.systemSmall`, `.fullColor`) branch. Each
///   family's frame size is exercised, but family-specific layouts and the accented/vibrant
///   rendering modes are verified visually in the simulator widget gallery (see
///   docs/AppStore/test-report.md), not here.
/// - swift-snapshot-testing was not added: the app project has no test-only SPM dependency today,
///   and reference images are tied to one Mac and Xcode version, so they break on CI or toolchain updates.
@MainActor
@Suite("Widget render matrix")
struct WidgetRenderMatrixTests {
    enum Family: String, CaseIterable, Sendable {
        case small, medium, large, circular, rectangular, inline

        /// iPhone 17 Pro (402 × 874 pt) widget sizes.
        var size: CGSize {
            switch self {
            case .small: CGSize(width: 170, height: 170)
            case .medium: CGSize(width: 364, height: 170)
            case .large: CGSize(width: 364, height: 382)
            case .circular: CGSize(width: 76, height: 76)
            case .rectangular: CGSize(width: 172, height: 76)
            case .inline: CGSize(width: 257, height: 26)
            }
        }
    }

    struct Widget: Sendable, CustomStringConvertible {
        let name: String
        let families: [Family]
        var description: String { name }
    }

    /// Mirrors every `supportedFamilies` list in WidgetExtension/.
    nonisolated static let widgets: [Widget] = [
        Widget(name: "Battery", families: [.small, .circular, .inline]),
        Widget(name: "SystemOverview", families: [.medium, .large]),
        Widget(name: "Storage", families: [.small, .rectangular]),
        Widget(name: "NextClass", families: [.small, .medium, .rectangular]),
        Widget(name: "TodaySchedule", families: [.medium, .large]),
        Widget(name: "Palette", families: [.small, .rectangular]),
        Widget(name: "Photo", families: [.small, .medium, .large]),
    ]

    nonisolated static let dynamicTypes: [DynamicTypeSize] = [.xSmall, .large, .accessibility3]
    nonisolated static let schemes: [ColorScheme] = [.light, .dark]

    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    @ViewBuilder
    private static func view(for name: String) -> some View {
        switch name {
        case "Battery": BatteryWidgetView(entry: .placeholder(at: now))
        case "SystemOverview": SystemOverviewWidgetView(entry: .placeholder(at: now))
        case "Storage": StorageWidgetView(entry: .placeholder(at: now))
        case "NextClass": NextClassWidgetView(entry: StudentScheduleProvider<NextClassSnapshot>.sampleEntry(now: now))
        case "TodaySchedule": TodayScheduleWidgetView(entry: StudentScheduleProvider<TodayScheduleSnapshot>.sampleEntry(now: now))
        case "Palette": PaletteWidgetView(entry: PaletteEntry(date: now, palette: .sample))
        case "Photo": PhotoWidgetView(entry: .sample(at: now))
        default: EmptyView()
        }
    }

    @Test(arguments: widgets)
    func rendersEveryCell(widget: Widget) throws {
        var cells = 0
        for family in widget.families {
            for scheme in Self.schemes {
                for type in Self.dynamicTypes {
                    let content = Self.view(for: widget.name)
                        .frame(width: family.size.width, height: family.size.height)
                        .environment(\.colorScheme, scheme)
                        .environment(\.dynamicTypeSize, type)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 3
                    let image = try #require(renderer.cgImage, "\(widget) \(family) \(scheme) \(type) did not render")
                    #expect(image.width == Int(family.size.width * 3))
                    #expect(Self.distinctColorCount(image) > 1, "\(widget) \(family) \(scheme) \(type) rendered blank")
                    // Decoded bitmap must stay far below the ~30 MB widget ceiling (Platform Reality Rule 7).
                    #expect(image.bytesPerRow * image.height < 8_000_000)
                    cells += 1
                }
            }
        }
        #expect(cells == widget.families.count * 6)
    }

    /// Samples a grid of pixels; a blank render has one colour.
    static func distinctColorCount(_ image: CGImage) -> Int {
        let width = 16, height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var colors = Set<UInt32>()
        for i in stride(from: 0, to: pixels.count, by: 4) {
            colors.insert(UInt32(pixels[i]) << 24 | UInt32(pixels[i + 1]) << 16 | UInt32(pixels[i + 2]) << 8 | UInt32(pixels[i + 3]))
        }
        return colors.count
    }
}

/// Measurements that can be taken on the simulator. Printed as `PERF` lines and gathered into
/// docs/AppStore/test-report.md. These are simulator numbers, not device numbers.
@Suite("Performance (simulator)")
struct SimulatorPerformanceTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private static func median(_ runs: Int = 50, _ body: () throws -> Void) rethrows -> Double {
        var times: [Double] = []
        for _ in 0..<runs {
            let start = ContinuousClock.now
            try body()
            let elapsed = ContinuousClock.now - start
            times.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        }
        return times.sorted()[times.count / 2]
    }

    @Test func timelineGenerationUnder50ms() throws {
        let store = SnapshotStore(appGroup: .temporary())
        let classes = (0..<7).flatMap { day in SampleSchedule.day(around: Self.now.addingTimeInterval(Double(day) * 86_400)) }
        try store.write(TodayScheduleSnapshot(classes: Array(classes.prefix(40)), generatedAt: Self.now))
        let photos = (0..<24).map { PhotoItem(addedAt: Self.now, files: [.small: "\($0).jpg"]) }
        try store.write(PhotoSnapshot(photos: photos, rotation: .hourly, generatedAt: Self.now))

        // Read the snapshot from disk + build entries, as the widget extension does.
        let student = Self.median {
            let snapshot = store.read(TodayScheduleSnapshot.self)
            _ = ScheduleTimeline.moments(classes: snapshot?.classes, now: Self.now)
        }
        let photo = Self.median {
            _ = PhotoTimelineBuilder.timeline(snapshot: store.read(PhotoSnapshot.self), now: Self.now)
        }
        print("PERF timeline.todaySchedule(40 classes) median_ms=\(String(format: "%.3f", student))")
        print("PERF timeline.photo(24 photos, hourly) median_ms=\(String(format: "%.3f", photo))")
        #expect(student < 50)
        #expect(photo < 50)
    }

    @Test func snapshotSizes() throws {
        let classes = (0..<7).flatMap { day in SampleSchedule.day(around: Self.now.addingTimeInterval(Double(day) * 86_400)) }
        let photos = (0..<24).map { _ in PhotoItem(addedAt: Self.now, files: [.small: "\(UUID()).jpg", .medium: "\(UUID()).jpg", .large: "\(UUID()).jpg"]) }
        let overview = SystemOverviewEntry.placeholder(at: Self.now).snapshot
        let sizes: [(String, Int)] = [
            ("nextClass(40 classes)", try SnapshotStore.encode(NextClassSnapshot(classes: Array(classes.prefix(40)), generatedAt: Self.now)).count),
            ("palette", try SnapshotStore.encode(PaletteSnapshot.sample).count),
            ("photo(24 photos x 3 sizes)", try SnapshotStore.encode(PhotoSnapshot(photos: photos, rotation: .daily, generatedAt: Self.now)).count),
            ("systemOverview", try overview.map { try SnapshotStore.encode($0).count } ?? 0),
        ]
        for (name, bytes) in sizes {
            print("PERF snapshot.\(name) bytes=\(bytes)")
            #expect(bytes < 50_000)
        }
    }

    @Test func downsampleToWidgetPixels() throws {
        // A 12 MP camera-sized JPEG, downsampled to the large widget on iPhone 17 Pro (@3x).
        let source = try Self.makeJPEG(width: 4032, height: 3024)
        let target = PhotoWidgetSize.pixels(for: .large, screen: CGSize(width: 402, height: 874), scale: 3)
        var output: CGImage?
        let ms = try SimulatorPerformanceTests.median(5) { output = try Downsampler.downsample(data: source, toFill: target) }
        let image = try #require(output)
        let decodedBytes = image.bytesPerRow * image.height
        let jpeg = try Downsampler.encode(image)
        print("PERF downsample 4032x3024 -> \(image.width)x\(image.height) median_ms=\(String(format: "%.1f", ms)) decoded_bytes=\(decodedBytes) jpeg_bytes=\(jpeg.count)")
        #expect(image.width == target.width && image.height == target.height)
        #expect(decodedBytes < 8_000_000)
    }

    static func makeJPEG(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for band in 0..<8 {
            context.setFillColor(CGColor(red: Double(band) / 8, green: 0.5, blue: 1 - Double(band) / 8, alpha: 1))
            context.fill(CGRect(x: band * width / 8, y: 0, width: width / 8, height: height))
        }
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
