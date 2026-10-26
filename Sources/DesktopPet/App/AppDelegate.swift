import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: OverlayWindow?
    private var settingsWindow: SettingsWindow?
    private let notificationWatcher = NotificationWatcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon, no regular app window.
        NSApp.setActivationPolicy(.accessory)

        let missingProps = PetProps.missing()
        guard missingProps.isEmpty else {
            // Deferred a tick: a modal run straight from didFinishLaunching
            // returns immediately while SwiftUI is still setting up the menu bar.
            DispatchQueue.main.async { Self.reportMissingArt(missingProps) }
            return
        }

        if PetConfig.current.isIncluded(PhotoDropMoment.id) {
            PhotoLibrary.ensureFolderExists()
        }

        let window = OverlayWindow()
        window.orderFrontRegardless()
        overlayWindow = window

        if PetConfig.current.isIncluded("statusBubbles") {
            notificationWatcher.onMessage = { [weak self] message in
                self?.overlayWindow?.scene.showNotification(message)
            }
            notificationWatcher.start()
        }
    }

    private static func reportMissingArt(_ files: [String]) {
        let alert = NSAlert()
        alert.messageText = "\(PetConfig.current.name) is missing some art"
        alert.informativeText = "Add these to \(PetConfig.directory.path), or switch those moments off "
            + "under \"features\" in pet.json:\n\n" + files.joined(separator: "\n")
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }

    /// A moment's menu bar item, e.g. "Bring me a photo now" — also handy
    /// for testing without waiting for the schedule.
    func trigger(momentID: String) {
        overlayWindow?.scene.moment(id: momentID)?.triggerNow()
    }

    /// Menu bar → "Snooze everything for 30 min".
    func snoozeEverything() {
        overlayWindow?.scene.snoozeEverything(minutes: 30)
    }

    /// Menu bar → "Send <pet> to bed" (hide) / "Wake <pet> up" (show).
    func setAsleep(_ asleep: Bool) {
        guard let overlayWindow else { return }
        if asleep {
            overlayWindow.orderOut(nil)
        } else {
            overlayWindow.orderFrontRegardless()
        }
    }

    /// Menu bar → "Open <Pet> Photos folder".
    func openPhotosFolder() {
        PhotoLibrary.ensureFolderExists()
        NSWorkspace.shared.open(PhotoLibrary.photosFolder)
    }

    /// Menu bar → "Settings…".
    func showSettings() {
        let window = settingsWindow ?? SettingsWindow()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
