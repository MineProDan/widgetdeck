import Foundation
import os

/// A privacy-first analytics event: a name plus a few **non-identifying** string parameters.
///
/// Rules: no user content (event titles, notes, photos), no identifiers (IDFA, device IDs, emails),
/// no precise timestamps beyond what the sink adds. We never show an ATT prompt.
public struct AnalyticsEvent: Sendable, Equatable {
    public let name: String
    public let parameters: [String: String]

    public init(_ name: String, parameters: [String: String] = [:]) {
        self.name = name
        self.parameters = parameters
    }

    // Common events (feature packages define their own with the same initializer).
    public static func sectionOpened(_ section: AppSection) -> AnalyticsEvent {
        AnalyticsEvent("section_opened", parameters: ["section": section.rawValue])
    }
    public static let paywallShown = AnalyticsEvent("paywall_shown")
    public static func purchaseCompleted(productID: String) -> AnalyticsEvent {
        AnalyticsEvent("purchase_completed", parameters: ["product": productID])
    }
    public static let dataExported = AnalyticsEvent("data_exported")
    public static let dataDeleted = AnalyticsEvent("data_deleted")
}

/// Where events go. The default is `NoOpAnalyticsSink`; a vendor sink (e.g. TelemetryDeck) can be
/// added later without touching call sites.
public protocol AnalyticsSink: Sendable {
    func record(_ event: AnalyticsEvent)
}

/// Discards everything (default: nothing leaves the device).
public struct NoOpAnalyticsSink: AnalyticsSink {
    public init() {}
    public func record(_ event: AnalyticsEvent) {}
}

/// Logs events to the unified log (debug builds / Console.app). Nothing leaves the device.
public struct LoggingAnalyticsSink: AnalyticsSink {
    private let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Analytics")
    public init() {}
    public func record(_ event: AnalyticsEvent) {
        logger.debug("event \(event.name, privacy: .public) \(event.parameters.description, privacy: .public)")
    }
}

/// Facade used by all features. Respects the user's opt-out.
public final class Analytics: Sendable {
    public static let shared = Analytics()

    private let state = OSAllocatedUnfairLock(initialState: State(sink: NoOpAnalyticsSink(), isEnabled: true))

    private struct State {
        var sink: any AnalyticsSink
        var isEnabled: Bool
    }

    public init() {}

    /// Replaces the sink (call once at launch).
    public func configure(sink: any AnalyticsSink) {
        state.withLock { $0.sink = sink }
    }

    /// User-controlled opt-out (Settings → Privacy).
    public var isEnabled: Bool {
        get { state.withLock { $0.isEnabled } }
        set { state.withLock { $0.isEnabled = newValue } }
    }

    public func track(_ event: AnalyticsEvent) {
        let (sink, enabled) = state.withLock { ($0.sink, $0.isEnabled) }
        guard enabled else { return }
        sink.record(event)
    }
}
