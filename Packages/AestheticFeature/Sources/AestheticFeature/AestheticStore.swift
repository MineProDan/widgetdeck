import AestheticFeatureWidgetKit
import CoreGraphics
import CoreKit
import Foundation
import Observation
import os
import UIKit
import WidgetKit

/// State and actions for the Aesthetic section (A-01 Photo widget, A-02 Theme Sync).
@MainActor
@Observable
public final class AestheticStore {
    public enum SyncPhase: Equatable {
        case idle
        case extracting
        case failed(String)
    }

    // Theme Sync
    public private(set) var wallpaper: UIImage?
    public private(set) var palette: ExtractedPalette?
    /// The palette currently on the widgets (nil until the first apply).
    public private(set) var appliedPalette: ExtractedPalette?
    public private(set) var syncPhase: SyncPhase = .idle
    public private(set) var isApplying = false
    /// Installed Widgetdeck widgets, for "Apply to N widgets" (nil = unknown).
    public private(set) var installedWidgetCount: Int?
    public var comparePosition = 0.44

    // Photos
    public private(set) var photos: [PhotoItem] = []
    public private(set) var rotation: PhotoRotation = .daily
    public private(set) var isImporting = false
    public var errorMessage: String?

    // Mood board (A-06)
    public private(set) var moodBoard: [MoodBoardItem] = []
    public private(set) var shuffleDaily = false

    // Borders and effects (A-07)
    public private(set) var styles = AestheticStyleSnapshot()

    public var hasUnappliedPalette: Bool { palette != nil && palette != appliedPalette }

    @ObservationIgnored private let files: AestheticFiles
    @ObservationIgnored private let snapshots: SnapshotStore
    @ObservationIgnored private let themes: any ThemeRepository
    @ObservationIgnored private let reload: @Sendable ([String]) async -> Void
    @ObservationIgnored private let onThemeApplied: @MainActor () async -> Void
    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Aesthetic")

    /// - Parameters:
    ///   - themes: where the synced theme is saved (`CoreDataThemeRepository` in the app).
    ///   - reload: widget reloader (defaults to WidgetCenter).
    ///   - onThemeApplied: lets the app re-read the active theme (e.g. `AppEnvironment.loadActiveTheme`).
    public init(themes: any ThemeRepository = NoPersistenceThemeRepository(),
                files: AestheticFiles = AestheticFiles(),
                snapshots: SnapshotStore = SnapshotStore(),
                reload: @escaping @Sendable ([String]) async -> Void = WidgetReloadCoordinator.widgetCenterReloader,
                onThemeApplied: @escaping @MainActor () async -> Void = {}) {
        self.themes = themes
        self.files = files
        self.snapshots = snapshots
        self.reload = reload
        self.onThemeApplied = onThemeApplied
    }

    /// Restores the applied palette, wallpaper thumbnail and photo list. Idempotent.
    public func load() async {
        if !didLoad {
            didLoad = true
            if let snapshot = snapshots.read(PaletteSnapshot.self), let restored = ExtractedPalette(snapshot: snapshot) {
                appliedPalette = restored
                palette = restored
            }
            wallpaper = UIImage(contentsOfFile: files.wallpaperThumbnailURL.path(percentEncoded: false))
            if let photoSnapshot = snapshots.read(PhotoSnapshot.self) {
                photos = photoSnapshot.photos
                rotation = photoSnapshot.rotation
            }
            if let board = snapshots.read(MoodBoardSnapshot.self) {
                moodBoard = board.photos
                shuffleDaily = board.shuffleDaily
            }
            styles = AestheticStyleSnapshot.load(store: snapshots)
            // Clear files left by an interrupted import.
            await PhotoLibrary(files: files, screen: .zero, scale: 1).removeOrphans(keeping: photos)
            await MoodBoardLibrary(files: files, screen: .zero, scale: 1).removeOrphans(keeping: moodBoard)
        }
        await refreshInstalledWidgetCount()
    }

    public func refreshInstalledWidgetCount() async {
        let prefix = AppIdentifiers.appBundleID
        // iOS 17 has only the completion-handler API (`currentConfigurations()` is iOS 18+).
        installedWidgetCount = await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                switch result {
                case let .success(widgets): continuation.resume(returning: widgets.filter { $0.kind.hasPrefix(prefix) }.count)
                case .failure: continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: Theme Sync

    /// Extracts the palette from the wallpaper photo the user picked. Nothing is applied yet.
    public func pickWallpaper(_ data: Data) async {
        syncPhase = .extracting
        errorMessage = nil
        let thumbnailURL = files.wallpaperThumbnailURL
        let root = files.root
        let result = await Task.detached(priority: .userInitiated) { () -> Result<(ExtractedPalette, Data), Swift.Error> in
            do {
                let clusters = try PaletteExtractor.extract(from: data)
                guard let palette = RoleAssigner.assign(clusters) else { throw PaletteExtractor.Error.unreadableImage }
                // A display-size thumbnail for this screen (112 × 206 pt card @3x); the original isn't kept.
                let thumb = try Downsampler.encode(Downsampler.downsample(data: data, maxPixelSize: 640), format: .jpeg)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try thumb.write(to: thumbnailURL, options: .atomic)
                return .success((palette, thumb))
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case let .success((palette, thumb)):
            self.palette = palette
            wallpaper = UIImage(data: thumb)
            comparePosition = 0.44
            syncPhase = .idle
        case let .failure(error):
            logger.error("Theme Sync failed: \(error.localizedDescription, privacy: .public)")
            syncPhase = .failed((error as? any LocalizedError)?.errorDescription ?? "That photo couldn't be read.")
        }
    }

    /// Saves the theme via CoreKit, writes the palette snapshot and reloads every widget.
    public func applyPalette() async {
        guard let palette, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        let now = Date.now
        let settings = AestheticSettings.load(files: files)
        do {
            try await themes.applyTheme(palette.theme(id: settings.wallpaperThemeID, now: now))
            let snapshot = palette.snapshot(now: now)
            try snapshots.write(snapshot)
            // Keep exactly what the widgets show (hex-rounded), so "applied" survives a relaunch.
            let stored = ExtractedPalette(snapshot: snapshot) ?? palette
            self.palette = stored
            appliedPalette = stored
            await onThemeApplied()
            await reload(WidgetKind.allCases.map(\.kindIdentifier))
            Analytics.shared.track(AnalyticsEvent("theme_applied", parameters: ["source": "wallpaper"]))
        } catch {
            logger.error("Theme apply failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't apply the theme. Try again."
        }
    }

    // MARK: Photos

    /// Imports picked photos (PhotosPicker data; no photo-library permission needed).
    public func importPhotos(_ items: [Data], screen: CGSize, scale: CGFloat) async {
        guard !items.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        let library = PhotoLibrary(files: files, screen: screen, scale: scale)
        for data in items {
            do {
                let item = try await library.importPhoto(data, existingCount: photos.count, now: .now)
                photos.append(item)
            } catch {
                errorMessage = (error as? any LocalizedError)?.errorDescription ?? "That photo couldn't be added."
                if case PhotoLibrary.Error.limitReached = error { break }
            }
        }
        await publishPhotos()
    }

    public func removePhoto(_ item: PhotoItem) async {
        photos.removeAll { $0.id == item.id }
        await PhotoLibrary(files: files, screen: .zero, scale: 1).delete(item)
        await publishPhotos()
    }

    public func setRotation(_ rotation: PhotoRotation) async {
        guard rotation != self.rotation else { return }
        self.rotation = rotation
        await publishPhotos()
    }

    /// The photo the widget shows right now (same rotation math as the widget timeline).
    public func currentPhoto(at date: Date = .now, calendar: Calendar = .current) -> PhotoItem? {
        guard !photos.isEmpty else { return nil }
        return photos[PhotoTimelineBuilder.photoIndex(at: date, count: photos.count, rotation: rotation, calendar: calendar)]
    }

    public func thumbnail(for item: PhotoItem) -> UIImage? {
        guard let name = item.files[.small] else { return nil }
        return UIImage(contentsOfFile: files.url(for: name).path(percentEncoded: false))
    }

    private func publishPhotos() async {
        let snapshot = PhotoSnapshot(photos: photos, rotation: rotation, generatedAt: .now)
        do {
            try snapshots.write(snapshot)
        } catch {
            logger.error("Photo snapshot failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't update the Photo widget. Try again."
        }
        await reload([WidgetKind.photo.kindIdentifier])
    }

    // MARK: Mood board (A-06)

    /// Adds picked photos to the end of the board (PhotosPicker data; no library permission).
    public func importMoodBoardPhotos(_ items: [Data], screen: CGSize, scale: CGFloat) async {
        guard !items.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        let library = MoodBoardLibrary(files: files, screen: screen, scale: scale)
        for data in items {
            do {
                moodBoard.append(try await library.importPhoto(data, existingCount: moodBoard.count, now: .now))
            } catch {
                if case PhotoLibrary.Error.limitReached = error {
                    errorMessage = "The mood board holds up to \(MoodBoardLibrary.maxPhotos) photos. Remove one to add more."
                    break
                }
                errorMessage = (error as? any LocalizedError)?.errorDescription ?? "That photo couldn't be added."
            }
        }
        await publishMoodBoard()
    }

    public func removeMoodBoardPhoto(_ item: MoodBoardItem) async {
        moodBoard.removeAll { $0.id == item.id }
        await MoodBoardLibrary(files: files, screen: .zero, scale: 1).delete(item)
        await publishMoodBoard()
    }

    /// Moves a photo by `offset` places (−1 earlier, +1 later), clamped to the board.
    public func moveMoodBoardPhoto(_ item: MoodBoardItem, by offset: Int) async {
        guard let from = moodBoard.firstIndex(where: { $0.id == item.id }) else { return }
        let to = min(max(from + offset, 0), moodBoard.count - 1)
        guard to != from else { return }
        moodBoard.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        await publishMoodBoard()
    }

    public func setShuffleDaily(_ on: Bool) async {
        guard on != shuffleDaily else { return }
        shuffleDaily = on
        await publishMoodBoard()
    }

    /// The board as the widget shows it today (same shuffle as the widget timeline).
    public func moodBoardToday(at date: Date = .now, calendar: Calendar = .current) -> [MoodBoardItem] {
        MoodBoardTimelineBuilder.order(of: moodBoard, shuffleDaily: shuffleDaily, at: date, calendar: calendar)
    }

    public func thumbnail(for item: MoodBoardItem) -> UIImage? {
        guard let name = item.files[.medium] else { return nil }
        return UIImage(contentsOfFile: files.moodBoardURL(for: name).path(percentEncoded: false))
    }

    private func publishMoodBoard() async {
        do {
            try snapshots.write(MoodBoardSnapshot(photos: moodBoard, shuffleDaily: shuffleDaily, generatedAt: .now))
        } catch {
            logger.error("Mood board snapshot failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't update the Mood board widget. Try again."
        }
        await reload([WidgetKind.moodBoard.kindIdentifier])
    }

    // MARK: Borders and effects (A-07)

    public func setStyle(_ style: WidgetStyle, for target: AestheticStyleTarget) async {
        guard styles[target] != style else { return }
        styles[target] = style
        styles.generatedAt = .now
        do {
            try snapshots.write(styles)
        } catch {
            logger.error("Style snapshot failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't update the widget style. Try again."
        }
        await reload([target.kind.kindIdentifier])
    }
}
