import Foundation

/// Finds the daily photos in `~/Pictures/<photosFolderName>/` and avoids
/// repeats within 60 days. Keeps a small JSON index of which photos were
/// shown, in `~/Library/Application Support/<Pet name>/`.
enum PhotoLibrary {
    static let photosFolder: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent(PetConfig.current.photosFolderName, isDirectory: true)
    }()

    private static let indexFile = NotificationWatcher.supportFolder.appendingPathComponent("photo-index.json")
    private static let repeatCooldown: TimeInterval = 60 * 24 * 60 * 60 // 60 days
    private static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]

    /// Creates the photos folder if it doesn't exist yet.
    static func ensureFolderExists() {
        try? FileManager.default.createDirectory(at: photosFolder, withIntermediateDirectories: true)
    }

    /// Picks a random photo not shown in the last 60 days. If every photo in
    /// the folder has been shown recently (e.g. only a handful of sample
    /// photos while developing), falls back to picking from all of them so
    /// the feature still works.
    static func pickPhoto() -> URL? {
        let candidates = allPhotos()
        guard !candidates.isEmpty else { return nil }

        var index = loadIndex()
        let now = Date()
        let eligible = candidates.filter { url in
            guard let lastShown = index[url.lastPathComponent] else { return true }
            return now.timeIntervalSince(lastShown) > repeatCooldown
        }

        guard let picked = (eligible.isEmpty ? candidates : eligible).randomElement() else { return nil }
        index[picked.lastPathComponent] = now
        saveIndex(index)
        return picked
    }

    private static func allPhotos() -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: photosFolder, includingPropertiesForKeys: nil
        )
        return (contents ?? []).filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
    }

    private static func loadIndex() -> [String: Date] {
        guard
            let data = try? Data(contentsOf: indexFile),
            let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func saveIndex(_ index: [String: Date]) {
        try? FileManager.default.createDirectory(at: NotificationWatcher.supportFolder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexFile)
    }
}
