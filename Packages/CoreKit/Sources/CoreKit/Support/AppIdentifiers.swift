import Foundation

/// Every identifier that is registered with Apple lives here, so no other file hard-codes one.
///
/// These values are permanent (the iCloud container in particular can never be renamed or deleted).
/// Do not change them without updating the entitlements files and the Apple Developer portal.
public enum AppIdentifiers {
    public static let appBundleID = "io.github.mineprodan.iospremium"
    public static let widgetBundleID = "io.github.mineprodan.iospremium.widgets"
    public static let appGroup = "group.io.github.mineprodan.iospremium"
    public static let iCloudContainer = "iCloud.io.github.mineprodan.iospremium"

    /// Keychain access group without the team prefix. The full group is
    /// `$(AppIdentifierPrefix)io.github.mineprodan.iospremium.shared`.
    public static let keychainGroupSuffix = "io.github.mineprodan.iospremium.shared"

    /// `BGAppRefreshTask` identifier (also listed in the app's Info.plist).
    public static let backgroundRefreshTask = "io.github.mineprodan.iospremium.refresh"

    /// Custom URL scheme used for widget deep links (`widgetx://section/tech`).
    public static let urlScheme = "widgetx"

    /// Full keychain access group, resolved from the `AppIdentifierPrefix` Info.plist key
    /// (set to `$(AppIdentifierPrefix)` in both targets). Returns `nil` when the key is missing,
    /// e.g. in unit tests, in which case Keychain items use the process's default group.
    public static func keychainAccessGroup(bundle: Bundle = .main) -> String? {
        guard let prefix = bundle.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !prefix.isEmpty, !prefix.contains("$(") else { return nil }
        return prefix + keychainGroupSuffix
    }
}
