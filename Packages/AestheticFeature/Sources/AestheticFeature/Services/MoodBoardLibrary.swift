import AestheticFeatureWidgetKit
import CoreGraphics
import CoreKit
import Foundation
import os

private let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Aesthetic")

/// Imports mood-board photos (A-06) into the App Group: each photo is downsampled once per grid
/// layout to the exact pixel size of one tile on this device, so the widget never resizes.
///
/// Memory: the largest board (large, 4 × 2) decodes 8 tiles of about 270 × 570 px on a Pro Max,
/// under 5 MB in total, well inside the ~30 MB widget ceiling.
public actor MoodBoardLibrary {
    public static let maxPhotos = 12

    private let files: AestheticFiles
    private let screen: CGSize
    private let scale: CGFloat

    public init(files: AestheticFiles = AestheticFiles(), screen: CGSize, scale: CGFloat) {
        self.files = files
        self.screen = screen
        self.scale = scale
    }

    public func pixelSizes() -> [MoodBoardLayout: PixelSize] {
        Dictionary(uniqueKeysWithValues: MoodBoardLayout.allCases.map { ($0, $0.tilePixels(screen: screen, scale: scale)) })
    }

    public func importPhoto(_ data: Data, existingCount: Int, now: Date) throws -> MoodBoardItem {
        guard existingCount < Self.maxPhotos else { throw PhotoLibrary.Error.limitReached(Self.maxPhotos) }
        let id = UUID()
        var written: [MoodBoardLayout: String] = [:]
        do {
            try FileManager.default.createDirectory(at: files.moodBoardDirectory, withIntermediateDirectories: true)
            for (layout, size) in pixelSizes() {
                let image: CGImage
                do {
                    image = try Downsampler.downsample(data: data, toFill: size)
                } catch {
                    throw PhotoLibrary.Error.unreadable
                }
                let name = "\(id.uuidString)-\(layout.rawValue).jpg"
                let jpeg = try Downsampler.encode(image, format: .jpeg, quality: 0.85)
                try jpeg.write(to: files.moodBoardURL(for: name),
                               options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                written[layout] = name
            }
        } catch let error as PhotoLibrary.Error {
            remove(fileNames: Array(written.values))
            throw error
        } catch {
            remove(fileNames: Array(written.values))
            logger.error("Mood board import failed: \(error.localizedDescription, privacy: .public)")
            throw PhotoLibrary.Error.saveFailed
        }
        return MoodBoardItem(id: id, addedAt: now, files: written)
    }

    public func delete(_ item: MoodBoardItem) {
        remove(fileNames: Array(item.files.values))
    }

    /// Removes tile files no snapshot references (e.g. after a crash mid-import).
    public func removeOrphans(keeping items: [MoodBoardItem]) {
        let keep = Set(items.flatMap { $0.files.values })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: files.moodBoardDirectory.path(percentEncoded: false))) ?? []
        remove(fileNames: names.filter { !keep.contains($0) })
    }

    private func remove(fileNames: [String]) {
        for name in fileNames { try? FileManager.default.removeItem(at: files.moodBoardURL(for: name)) }
    }
}
