import CoreServices
import Foundation

/// Finds screenshot/recording files for the on-demand "Tidy the desktop"
/// menu action (TidyMoment).
enum ScreenshotFinder {
    /// Reads the system's configured screenshot save location
    /// (`com.apple.screencapture`'s `location` default); falls back to the
    /// Desktop if it's unset.
    static func resolveDirectory() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Every screenshot/recording currently sitting in that folder. Doesn't
    /// recurse, so anything already in `Screenshots/` is left alone.
    static func findAll() -> [URL] {
        let directory = resolveDirectory()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter(isScreenshot)
    }

    /// Spotlight tags screenshots with `kMDItemIsScreenCapture`; the
    /// filename-prefix check is a fallback (also catches screen recordings,
    /// which this attribute doesn't always cover).
    static func isScreenshot(_ url: URL) -> Bool {
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let isCapture = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool,
           isCapture {
            return true
        }
        let name = url.lastPathComponent
        return name.hasPrefix("Screenshot") || name.hasPrefix("Screen Recording")
    }
}
