import BackgroundTasks
import CoreKit
import DesignSystem
import Foundation
import Observation
import AestheticFeature
import os
import StudentFeature
import StudentFeatureWidgetKit
import TechFeature
import UserNotifications
import WellnessFeature

/// App-wide dependencies, created once at launch and injected with `.environment(_:)`.
@MainActor
@Observable
final class AppEnvironment {
    /// The single instance (needed by `AppDelegate` for background tasks and notifications).
    static let shared = AppEnvironment()

    private(set) var stack: CoreDataStack?
    /// Shown in Settings when the persistent store couldn't open (the app then runs in memory).
    private(set) var storeErrorMessage: String?
    private(set) var theme: DSTheme = .standard
    /// The active theme deck's id (`WXDeck`). The tab content is keyed on it, so picking a deck
    /// redraws every screen in the new colours, face and shapes.
    private(set) var deckID: String = WXDeck.current.id
    var selectedSection: AppSection = .student
    /// Course to open from a widget or reminder deep link (consumed by the Student section).
    var requestedCourseID: UUID?
    /// Bumped on every section deep link so the tab switches even when `selectedSection` is unchanged.
    private(set) var deepLinkCount = 0

    /// Switches to a section's tab (used by Settings → "Set up my classes again").
    func show(_ section: AppSection) {
        selectedSection = section
        deepLinkCount += 1
    }
    /// Section stores, created once the Core Data stack is loaded so they survive tab switches.
    private(set) var studentStore: StudentStore?
    private(set) var techMonitor: SystemMonitorService?
    private(set) var aestheticStore: AestheticStore?
    private(set) var wellnessStore: WellnessStore?
    /// Wellness deep link to act on (start breathing, highlight a habit, log mood); consumed by the tab.
    var wellnessRequest: WellnessRequest?

    let account = CloudKitAccountMonitor()
    let cloudSync = CloudSyncMonitor()
    let permissions = PermissionManager()
    let reloadCoordinator = WidgetReloadCoordinator()
    let imageCache = ImageCache()
    let keychain = KeychainStore()

    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var dedupeTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "App")

    private init() {}

    /// Opens stores and starts long-lived listeners. Idempotent.
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        // An export left behind if the app was quit mid-share.
        DataExporter.removeExports()

        MetricKitSubscriber.shared.start()
        account.start()

        async let flags: Void = RemoteFlags().refresh()

        do {
            stack = try await CoreDataStack.load(mode: .app, contributors: Self.persistenceContributors())
        } catch {
            logger.fault("Store load failed: \(String(describing: error), privacy: .public)")
            storeErrorMessage = (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
            // Keep the app usable for this session rather than crashing.
            stack = try? await CoreDataStack.load(mode: .inMemory, contributors: Self.persistenceContributors())
        }

        if let stack { cloudSync.start(container: stack.container) }
        makeSectionStores()
        await flags
        await loadActiveTheme()
        startDedupeListener()
        await imageCache.purgeIfLowStorage()
        scheduleBackgroundRefresh()
    }

    /// Called when the scene becomes active.
    func didBecomeActive() {
        WidgetReloadCoordinator.appIsActive = true
        permissions.refresh()
        Task { await account.refresh() }
    }

    /// Called when the scene goes to the background: push pending widget reloads now.
    func didEnterBackground() {
        WidgetReloadCoordinator.appIsActive = false
        Task { await reloadCoordinator.flushNow() }
        scheduleBackgroundRefresh()
    }

    func handle(url: URL) {
        if let section = AppSection(deepLink: url) {
            selectedSection = section
            requestedCourseID = StudentDeepLink.courseID(from: url)
            wellnessRequest = section == .wellness ? WellnessRequest(url: url) : nil
            if FocusDeepLink.isFocus(url) { studentStore?.showFocus() }
            deepLinkCount += 1
        }
    }

    // MARK: Sections

    /// Feature entities added to the shared Core Data model.
    /// A function (not a stored array) so each call hands `CoreDataStack.load` a fresh, sendable value.
    nonisolated private static func persistenceContributors() -> [any PersistenceModelContributor.Type] {
        [TechPersistenceModel.self, StudentModel.self, WellnessModel.self]
    }

    /// CoreKit's synced entities plus each feature's.
    private static var dedupeEntityNames: [String] {
        [PersistenceModel.Entity.theme, PersistenceModel.Entity.userProfile, PersistenceModel.Entity.widgetConfiguration]
            + StudentModel.syncedEntityNames
            + WellnessModel.syncedEntityNames
    }

    private var wellnessRepository: any WellnessRepository {
        if let stack { CoreDataWellnessRepository(stack: stack) } else { FileWellnessRepository() }
    }

    private var studentRepository: any StudentRepository {
        if let stack { CoreDataStudentRepository(stack: stack) } else { FileStudentRepository() }
    }

    private func makeSectionStores() {
        studentStore = StudentStore(repository: studentRepository, permissions: permissions)
        let samples: any MetricSampleStore = stack.map { CoreDataMetricSampleStore(stack: $0) } ?? InMemoryMetricSampleStore()
        techMonitor = SystemMonitorService(store: samples)
        aestheticStore = AestheticStore(
            themes: stack.map { CoreDataThemeRepository(stack: $0) } ?? NoPersistenceThemeRepository(),
            onThemeApplied: { [weak self] in await self?.loadActiveTheme() })
        wellnessStore = WellnessStore(repository: wellnessRepository)
    }

    // MARK: Theme

    func loadActiveTheme() async {
        guard let stack else { return }
        var stored: Theme?
        do {
            let profile = try await RecordStore<UserProfile>(stack: stack).fetchAll().first
            if let themeID = profile?.activeThemeID {
                stored = try await RecordStore<Theme>(stack: stack).fetch(id: themeID)
            }
        } catch {
            logger.error("Theme load failed: \(error.localizedDescription, privacy: .public)")
        }
        theme = stored.map(ThemeResolver.resolve) ?? .standard
        publishWidgetTheme(stored)
    }

    /// Every widget recolours its Paint Chip fields from the active theme (DesignSystem
    /// `WidgetThemePaint`). Widgets only reload when the stored palette actually changed.
    private func publishWidgetTheme(_ stored: Theme?) {
        guard ActiveThemeStore().write(stored.flatMap(ActiveThemeSnapshot.init(theme:))) else { return }
        Task { await WidgetReloadCoordinator.widgetCenterReloader(WidgetKind.allCases.map(\.kindIdentifier)) }
    }

    /// Saves `theme` as the active theme (onboarding vibe picker) and recolours the app and widgets.
    func applyTheme(_ theme: Theme) async {
        guard let stack else { return }
        do {
            try await CoreDataThemeRepository(stack: stack).applyTheme(theme)
        } catch {
            logger.error("Theme apply failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        await loadActiveTheme()
    }

    /// Makes `deck` the look of the app and every widget (Settings → Theme, onboarding vibe).
    /// A deck brings its own colours, so a Theme Sync or earlier vibe palette is cleared; Theme Sync
    /// can recolour the new deck again later (fonts and shapes stay the deck's).
    func applyDeck(_ deck: WXDeck) async {
        WXDeck.select(deck)
        deckID = deck.id
        await clearActiveTheme()
        await WidgetReloadCoordinator.widgetCenterReloader(WidgetKind.allCases.map(\.kindIdentifier))
        Analytics.shared.track(AnalyticsEvent("deck_applied", parameters: ["deck": deck.id]))
    }

    private func clearActiveTheme() async {
        guard let stack else {
            ActiveThemeStore().write(nil)
            theme = .standard
            return
        }
        do {
            let profiles = RecordStore<UserProfile>(stack: stack)
            if var profile = try await profiles.fetchAll().first, profile.activeThemeID != nil {
                profile.activeThemeID = nil
                profile.updatedAt = .now
                try await profiles.upsert(profile)
            }
        } catch {
            logger.error("Clearing the active theme failed: \(error.localizedDescription, privacy: .public)")
        }
        await loadActiveTheme()
    }

    // MARK: Data management

    func exportData() async throws -> URL {
        guard let stack else { throw CocoaError(.fileReadUnknown) }
        let url = try await DataExporter(stack: stack, contributors: [
            FeatureExportContributor.student(studentRepository),
            FeatureExportContributor.wellness(wellnessRepository),
        ]).export()
        Analytics.shared.track(.dataExported)
        return url
    }

    func deleteAllData() async -> DataEraser.Report {
        let zoneEraser: (any CloudZoneErasing)? = account.status == .available ? CoreDataCloudZoneEraser() : nil
        await studentStore?.focus.stop() // ends the focus Live Activity
        let report = await DataEraser(stack: stack, keychain: keychain, zoneEraser: zoneEraser).eraseEverything()
        theme = .standard
        WXDeck.select(.paintChip)
        deckID = WXDeck.paintChip.id
        // Class reminders and mood reminders would otherwise still fire for deleted data.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        makeSectionStores() // drop in-memory copies of the deleted data
        await WidgetReloadCoordinator.widgetCenterReloader(WidgetKind.allCases.map(\.kindIdentifier))
        Analytics.shared.track(.dataDeleted)
        return report
    }

    // MARK: Background work

    /// Opportunistic `BGAppRefreshTask` work: dedupe after sync and push widget reloads.
    func performBackgroundRefresh() async {
        if let stack { _ = try? await DeduplicationService(stack: stack, entityNames: Self.dedupeEntityNames).run() }
        await RemoteFlags().refresh()
        await StudentBackgroundRefresh.run(repository: studentRepository)
        await WellnessBackgroundRefresh.run(repository: wellnessRepository)
        await reloadCoordinator.flushNow()
        scheduleBackgroundRefresh()
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppIdentifiers.backgroundRefreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Expected in the simulator and when Background App Refresh is off.
            logger.info("BG refresh not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startDedupeListener() {
        guard let stack, dedupeTask == nil else { return }
        dedupeTask = Task { [logger] in
            for await _ in stack.remoteChanges() {
                // Coalesce bursts of CloudKit imports.
                try? await Task.sleep(for: .seconds(5))
                do {
                    try await DeduplicationService(stack: stack, entityNames: Self.dedupeEntityNames).run()
                } catch {
                    logger.error("Dedupe failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
