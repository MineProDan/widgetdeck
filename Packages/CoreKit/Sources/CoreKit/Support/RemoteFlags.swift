import Foundation
import os

/// Remote feature flags (release process): risky features ship behind flags so they can be
/// switched off without a new build. Flags are Bools written to the App Group defaults as
/// `flag.<name>` (e.g. `flag.T-03.cpuMemory`), so the app and widgets read them without networking.
///
/// Sources, lowest priority first: compiled-in defaults → the last successful remote fetch. When
/// `remoteURL` is nil (no CDN yet) only the defaults are written.
public struct RemoteFlags {
    /// Flags JSON on GitHub Pages: `{"T-03.cpuMemory": true, ...}`. Source: `docs/github-pages/flags.json`
    /// (publish steps in that folder's README). Until the site is live the fetch fails quietly and
    /// the stored values / defaults stay in effect.
    public static let remoteURL: URL? = URL(string: "https://mineprodan.github.io/flags.json")

    /// Defaults used until (and whenever) the remote file can't be fetched.
    public static let defaults: [String: Bool] = [
        "T-03.cpuMemory": true,
    ]

    public static func key(_ name: String) -> String { "flag.\(name)" }

    private let client: HTTPClient
    private let store: UserDefaults
    private let url: URL?
    private static let logger = Logger(subsystem: AppIdentifiers.appBundleID, category: "Flags")

    public init(client: HTTPClient = HTTPClient(), store: UserDefaults = AppGroupContainer.shared.userDefaults,
                url: URL? = RemoteFlags.remoteURL) {
        self.client = client
        self.store = store
        self.url = url
    }

    /// Writes any missing defaults, then applies the remote file if one is configured. Never throws:
    /// on failure the previously stored values stay in effect.
    public func refresh() async {
        for (name, value) in Self.defaults where store.object(forKey: Self.key(name)) == nil {
            store.set(value, forKey: Self.key(name))
        }
        guard let url else { return }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadRevalidatingCacheData
            let remote = try await client.send(request, decoding: [String: Bool].self)
            for (name, value) in remote { store.set(value, forKey: Self.key(name)) }
        } catch {
            Self.logger.info("Flags fetch failed, keeping stored values: \(error.localizedDescription, privacy: .public)")
        }
    }
}
