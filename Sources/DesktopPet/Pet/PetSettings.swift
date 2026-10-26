import Foundation
import ServiceManagement

/// The user's own settings from the Settings window, backed by UserDefaults
/// so they persist and the scene's moments can read them live. Defaults come
/// from `pet.json`'s `schedule`. A single shared instance, since both the
/// SwiftUI side and PetScene (which isn't a SwiftUI view) need it.
final class PetSettings: ObservableObject {
    static let shared = PetSettings()

    @Published var breakfastHour: Int { didSet { save() } }
    @Published var breakfastMinute: Int { didSet { save() } }
    @Published var lunchHour: Int { didSet { save() } }
    @Published var lunchMinute: Int { didSet { save() } }
    @Published var dinnerHour: Int { didSet { save() } }
    @Published var dinnerMinute: Int { didSet { save() } }
    @Published var photoDropHour: Int { didSet { save() } }
    @Published var photoDropMinute: Int { didSet { save() } }
    @Published var breakIntervalMinutes: Int { didSet { save() } }

    /// Moment id → switched on. Missing ids count as on, so a newly added
    /// moment starts enabled.
    @Published private var enabledMoments: [String: Bool] { didSet { save() } }

    @Published var openAtLoginEnabled: Bool {
        didSet {
            save()
            guard openAtLoginEnabled != oldValue else { return }
            applyLoginItemRegistration()
        }
    }

    /// Where tidied screenshots land. Defaults to `~/Desktop/Screenshots`.
    @Published var screenshotsDestinationPath: String { didSet { save() } }

    var screenshotsDestination: URL {
        URL(fileURLWithPath: screenshotsDestinationPath, isDirectory: true)
    }

    func isEnabled(_ momentID: String) -> Bool {
        enabledMoments[momentID] ?? true
    }

    func setEnabled(_ momentID: String, _ enabled: Bool) {
        enabledMoments[momentID] = enabled
    }

    private static let defaultsKey = "DesktopPet.settings.v1"

    private struct Stored: Codable {
        var breakfastHour: Int
        var breakfastMinute: Int
        var lunchHour: Int
        var lunchMinute: Int
        var dinnerHour: Int
        var dinnerMinute: Int
        var photoDropHour: Int
        var photoDropMinute: Int
        var breakIntervalMinutes: Int
        var enabledMoments: [String: Bool]
        var openAtLoginEnabled: Bool
        var screenshotsDestinationPath: String
    }

    private init() {
        let defaultDestination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
            .path

        let schedule = PetConfig.current.schedule
        let breakfast = PetConfig.hourMinute(schedule.breakfast)
        let lunch = PetConfig.hourMinute(schedule.lunch)
        let dinner = PetConfig.hourMinute(schedule.dinner)
        let photo = PetConfig.hourMinute(schedule.photoDrop)
        let defaults = Stored(
            breakfastHour: breakfast.hour, breakfastMinute: breakfast.minute,
            lunchHour: lunch.hour, lunchMinute: lunch.minute,
            dinnerHour: dinner.hour, dinnerMinute: dinner.minute,
            photoDropHour: photo.hour, photoDropMinute: photo.minute,
            breakIntervalMinutes: schedule.breakIntervalMinutes,
            enabledMoments: [:],
            openAtLoginEnabled: false,
            screenshotsDestinationPath: defaultDestination
        )

        let stored: Stored
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        } else {
            stored = defaults
        }

        breakfastHour = stored.breakfastHour
        breakfastMinute = stored.breakfastMinute
        lunchHour = stored.lunchHour
        lunchMinute = stored.lunchMinute
        dinnerHour = stored.dinnerHour
        dinnerMinute = stored.dinnerMinute
        photoDropHour = stored.photoDropHour
        photoDropMinute = stored.photoDropMinute
        breakIntervalMinutes = stored.breakIntervalMinutes
        enabledMoments = stored.enabledMoments
        openAtLoginEnabled = stored.openAtLoginEnabled
        screenshotsDestinationPath = stored.screenshotsDestinationPath
    }

    private func save() {
        let stored = Stored(
            breakfastHour: breakfastHour, breakfastMinute: breakfastMinute,
            lunchHour: lunchHour, lunchMinute: lunchMinute,
            dinnerHour: dinnerHour, dinnerMinute: dinnerMinute,
            photoDropHour: photoDropHour, photoDropMinute: photoDropMinute,
            breakIntervalMinutes: breakIntervalMinutes,
            enabledMoments: enabledMoments,
            openAtLoginEnabled: openAtLoginEnabled,
            screenshotsDestinationPath: screenshotsDestinationPath
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    /// `SMAppService` needs a real .app bundle with a stable bundle
    /// identifier — it works from `scripts/build-app.sh`'s app, and silently
    /// no-ops under `swift run`. The setting itself persists either way.
    private func applyLoginItemRegistration() {
        do {
            if openAtLoginEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Best effort; there's no error-reporting UI in the settings window for this.
        }
    }
}
