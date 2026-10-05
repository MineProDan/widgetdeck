import AestheticFeatureWidgetKit
import CoreGraphics
import CoreKit
import Foundation
import os

private let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Aesthetic")

// MARK: - Photo library (A-01)

/// Imports picked photos into the App Group, downsampled once per widget slot to the exact pixel
/// size of that widget on this device (Platform Reality Rule 7: never resize at render time).
public actor PhotoLibrary {
    public enum Error: Swift.Error, Equatable, LocalizedError {
        case limitReached(Int)
        case unreadable
        case saveFailed

        public var errorDescription: String? {
            switch self {
            case let .limitReached(limit): "The Photo widget holds up to \(limit) photos. Remove one to add more."
            case .unreadable: "That photo couldn't be opened. Try another one."
            case .saveFailed: "That photo couldn't be saved. Check free space and try again."
            }
        }
    }

    public static let maxPhotos = 24

    private let files: AestheticFiles
    private let screen: CGSize
    private let scale: CGFloat

    /// - Parameters: screen size in points and scale (`UIScreen`/trait values, passed in by the view).
    public init(files: AestheticFiles = AestheticFiles(), screen: CGSize, scale: CGFloat) {
        self.files = files
        self.screen = screen
        self.scale = scale
    }

    /// Target pixel size for each slot on this device.
    public func pixelSizes() -> [PhotoSlot: PixelSize] {
        Dictionary(uniqueKeysWithValues: PhotoSlot.allCases.map { ($0, PhotoWidgetSize.pixels(for: $0, screen: screen, scale: scale)) })
    }

    /// Downsamples `data` for every slot and writes the JPEGs. The original is never stored.
    public func importPhoto(_ data: Data, existingCount: Int, now: Date) throws -> PhotoItem {
        guard existingCount < Self.maxPhotos else { throw Error.limitReached(Self.maxPhotos) }
        let id = UUID()
        var written: [PhotoSlot: String] = [:]
        do {
            try FileManager.default.createDirectory(at: files.photosDirectory, withIntermediateDirectories: true)
            for (slot, size) in pixelSizes() {
                let image: CGImage
                do {
                    image = try Downsampler.downsample(data: data, toFill: size)
                } catch {
                    throw Error.unreadable
                }
                let name = "\(id.uuidString)-\(slot.rawValue).jpg"
                let jpeg = try Downsampler.encode(image, format: .jpeg, quality: 0.85)
                try jpeg.write(to: files.url(for: name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                written[slot] = name
            }
        } catch let error as Error {
            remove(fileNames: Array(written.values))
            throw error
        } catch {
            remove(fileNames: Array(written.values))
            logger.error("Photo import failed: \(error.localizedDescription, privacy: .public)")
            throw Error.saveFailed
        }
        return PhotoItem(id: id, addedAt: now, files: written)
    }

    public func delete(_ item: PhotoItem) {
        remove(fileNames: Array(item.files.values))
    }

    /// Removes image files no snapshot references (e.g. after a crash mid-import).
    public func removeOrphans(keeping items: [PhotoItem]) {
        let keep = Set(items.flatMap { $0.files.values })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: files.photosDirectory.path(percentEncoded: false))) ?? []
        remove(fileNames: names.filter { !keep.contains($0) })
    }

    private func remove(fileNames: [String]) {
        for name in fileNames { try? FileManager.default.removeItem(at: files.url(for: name)) }
    }
}

// MARK: - Theme persistence (A-02)

/// Where Theme Sync saves the theme it builds.
public protocol ThemeRepository: Sendable {
    /// Saves `theme` and makes it the active theme.
    func applyTheme(_ theme: Theme) async throws
}

/// CoreKit Core Data storage: upserts the `Theme` (Cloud config) and sets `UserProfile.activeThemeID`.
public struct CoreDataThemeRepository: ThemeRepository {
    private let stack: CoreDataStack

    public init(stack: CoreDataStack) {
        self.stack = stack
    }

    public func applyTheme(_ theme: Theme) async throws {
        try await RecordStore<Theme>(stack: stack).upsert(theme)
        let profiles = RecordStore<UserProfile>(stack: stack)
        var profile = try await profiles.fetchAll().first ?? UserProfile()
        profile.activeThemeID = theme.id
        profile.updatedAt = .now
        try await profiles.upsert(profile)
    }
}

/// Fallback when the persistent store is unavailable: the theme lives only in the App Group
/// palette snapshot (widgets still update; the app theme resets next launch).
public struct NoPersistenceThemeRepository: ThemeRepository {
    public init() {}
    public func applyTheme(_ theme: Theme) async throws {}
}

// MARK: - Settings

/// Small, non-synced Aesthetic settings (App Group JSON).
public struct AestheticSettings: Codable, Hashable, Sendable {
    /// Stable ID of the wallpaper theme, so each re-sync replaces it instead of adding a new theme.
    public var wallpaperThemeID: UUID

    public init(wallpaperThemeID: UUID = UUID()) {
        self.wallpaperThemeID = wallpaperThemeID
    }

    static func url(files: AestheticFiles) -> URL { files.root.appending(path: "settings.json") }

    public static func load(files: AestheticFiles) -> AestheticSettings {
        guard let data = try? Data(contentsOf: url(files: files)),
              let settings = try? JSONDecoder().decode(AestheticSettings.self, from: data) else {
            let fresh = AestheticSettings()
            fresh.save(files: files)
            return fresh
        }
        return settings
    }

    public func save(files: AestheticFiles) {
        do {
            try FileManager.default.createDirectory(at: files.root, withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: Self.url(files: files), options: .atomic)
        } catch {
            logger.error("Settings save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
