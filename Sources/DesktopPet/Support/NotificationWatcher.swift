import Foundation

/// Watches a local "drop box" folder for status updates and turns each
/// dropped file into a speech bubble over the pet — e.g. a Claude Code hook running
/// `echo "Claude's done!" > ~/Library/Application\ Support/<Pet name>/Notifications/$(date +%s).txt`
/// when a session finishes. Switch off with `pet.json` → `features.statusBubbles`.
///
/// A plain file drop rather than a URL scheme or socket: any shell command
/// can write a file with zero setup, under `swift run` or the packaged app.
final class NotificationWatcher {
    /// `~/Library/Application Support/<Pet name>/`, shared with PhotoLibrary's index.
    static let supportFolder: URL = {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )) ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent(PetConfig.current.name, isDirectory: true)
    }()

    static let folder = supportFolder.appendingPathComponent("Notifications", isDirectory: true)

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var knownFiles: Set<String> = []

    var onMessage: ((String) -> Void)?

    func start() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        stop()
        knownFiles = Set(currentFiles().map(\.lastPathComponent))

        let fd = open(Self.folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            self?.scanForNewFiles()
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func currentFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
    }

    private func scanForNewFiles() {
        for url in currentFiles() {
            let name = url.lastPathComponent
            guard !knownFiles.contains(name) else { continue }
            knownFiles.insert(name)

            defer { try? FileManager.default.removeItem(at: url) } // consumed either way

            guard
                let data = try? Data(contentsOf: url),
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { continue }

            onMessage?(text)
        }
    }
}
