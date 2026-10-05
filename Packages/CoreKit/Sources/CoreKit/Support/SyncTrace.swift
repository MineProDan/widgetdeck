import Foundation
import os

/// A short on-device log of sync and widget events, for debugging widgets that stop updating.
/// Written by the app and the widget extension to the App Group (last ~400 lines). Never leaves the
/// iPhone unless the user shares it from Settings → About → Sync log. Never log calendar contents.
public enum SyncTrace {
    private static let lock = OSAllocatedUnfairLock()
    private static let maxLines = 400

    public static var url: URL { AppGroupContainer.shared.cachesURL.appending(path: "sync-trace.log") }

    public static func log(_ message: String, source: String = Bundle.main.bundleURL.pathExtension == "appex" ? "widget" : "app") {
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeSeparator(.colon))
        let line = "\(stamp) [\(source)] \(message)\n"
        lock.withLock {
            let url = url
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            text += line
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            if lines.count > maxLines { text = lines.suffix(maxLines).joined(separator: "\n") + "\n" }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public static func read() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

    public static func clear() { lock.withLock { try? FileManager.default.removeItem(at: url) } }
}
