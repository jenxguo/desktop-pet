import AppKit
import SwiftUI

/// Everything that makes the pet *this* pet — name, pronouns, sprite
/// geometry, which moments exist, default schedule, colors and every line of
/// text — read from `Pet/pet.json`.
///
/// `pet.json` only needs the keys you want to change: it's deep-merged over
/// `PetConfig.defaultsJSON` below, so a minimal file can be just
/// `{ "name": "Biscuit" }`.
struct PetConfig: Decodable {
    struct Pronouns: Decodable {
        var they: String
        var them: String
        var their: String
    }

    struct Sprite: Decodable {
        /// Every frame in `Pet/sprites/` is this size, facing right.
        var frameWidth: CGFloat
        var frameHeight: CGFloat
        /// Pixel row (from the top of the frame) where the feet touch the ground.
        var feetY: CGFloat
        /// [x, y] pixel (from the top-left) where carried props sit.
        var mouth: [CGFloat]
        /// On-screen scale. Frames are drawn with nearest-neighbor filtering.
        var scale: CGFloat
    }

    struct Movement: Decodable {
        var walkSpeed: CGFloat // points per second
        var runSpeed: CGFloat
        var tidySpeed: CGFloat
        var walkFrameSeconds: TimeInterval
        var runFrameSeconds: TimeInterval
    }

    struct Schedule: Decodable {
        var breakfast: String // "HH:mm", 24-hour
        var lunch: String
        var dinner: String
        var photoDrop: String
        var breakIntervalMinutes: Int
        var fetchThrows: Int
    }

    struct Theme: Decodable {
        var background: String
        var card: String
        var ink: String
        var border: String
        var accent: String
    }

    var name: String
    var pronouns: Pronouns
    /// SF Symbol shown in the menu bar, e.g. "pawprint.fill", "cat.fill", "hare.fill".
    var menuBarSymbol: String
    /// Folder under ~/Pictures the daily photo comes from.
    var photosFolderName: String
    var sprite: Sprite
    var movement: Movement
    /// Moment id → included in this build at all. A moment that's `false`
    /// here has no menu item, no settings toggle, and never runs.
    var features: [String: Bool]
    var schedule: Schedule
    var theme: Theme
    /// Every user-facing string. `{name}`, `{they}`, `{them}`, `{their}` and
    /// `{photosFolder}` are filled in by `text(_:)`.
    var strings: [String: String]

    private enum CodingKeys: String, CodingKey {
        case name, pronouns, menuBarSymbol, photosFolderName, sprite, movement, features, schedule, theme
        case strings = "text"
    }

    func isIncluded(_ featureID: String) -> Bool {
        features[featureID] ?? true
    }

    /// Looks up a string by key and fills in its placeholders, e.g.
    /// `text("menuSleep")` → "Send Mars to her bed".
    func text(_ key: String, _ extra: [String: String] = [:]) -> String {
        var result = strings[key] ?? key
        var values = [
            "name": name,
            "they": pronouns.they,
            "them": pronouns.them,
            "their": pronouns.their,
            "photosFolder": photosFolderName,
        ]
        values.merge(extra) { _, new in new }
        for (placeholder, value) in values {
            result = result.replacingOccurrences(of: "{\(placeholder)}", with: value)
        }
        return result
    }

    /// Parses a schedule time like "18:30".
    static func hourMinute(_ value: String) -> (hour: Int, minute: Int) {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return (9, 0) }
        return (parts[0], parts[1])
    }
}

// MARK: - Loading

extension PetConfig {
    static let current: PetConfig = load()

    /// The pet folder: `$PET_DIR` if set, else `Pet/` inside the .app's
    /// Resources (see scripts/build-app.sh), else `Pet/` at the project root
    /// when running with `swift run`.
    static let directory: URL = {
        if let override = ProcessInfo.processInfo.environment["PET_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Pet", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("pet.json").path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath) // Sources/DesktopPet/Pet/PetConfig.swift
            .deletingLastPathComponent() // Sources/DesktopPet/Pet
            .deletingLastPathComponent() // Sources/DesktopPet
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // project root
            .appendingPathComponent("Pet", isDirectory: true)
    }()

    private static func load() -> PetConfig {
        let url = directory.appendingPathComponent("pet.json")
        var merged = parse(Data(defaultsJSON.utf8), source: "built-in defaults")

        if let data = try? Data(contentsOf: url) {
            merged = deepMerge(merged, parse(data, source: url.path))
        } else {
            FileHandle.standardError.write(Data("⚠️  No pet.json at \(url.path) — using built-in defaults.\n".utf8))
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: merged)
            return try JSONDecoder().decode(PetConfig.self, from: data)
        } catch {
            fatalError("pet.json has a value of the wrong type: \(error)")
        }
    }

    private static func parse(_ data: Data, source: String) -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                fatalError("\(source) must be a JSON object")
            }
            return object
        } catch {
            fatalError("\(source) isn't valid JSON: \(error.localizedDescription)")
        }
    }

    private static func deepMerge(_ base: [String: Any], _ override: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in override {
            if let baseDict = result[key] as? [String: Any], let overrideDict = value as? [String: Any] {
                result[key] = deepMerge(baseDict, overrideDict)
            } else {
                result[key] = value
            }
        }
        return result
    }

    /// The full set of keys, with generic values. `Pet/pet.json` overrides
    /// any of them; see docs/MAKE_YOUR_OWN_PET.md for what each one does.
    static let defaultsJSON = """
    {
      "name": "Pet",
      "pronouns": { "they": "they", "them": "them", "their": "their" },
      "menuBarSymbol": "pawprint.fill",
      "photosFolderName": "Pet Photos",
      "sprite": { "frameWidth": 68, "frameHeight": 46, "feetY": 43, "mouth": [53, 18], "scale": 2.25 },
      "movement": {
        "walkSpeed": 36, "runSpeed": 110, "tidySpeed": 320,
        "walkFrameSeconds": 0.12, "runFrameSeconds": 0.09
      },
      "features": { "photoDrop": true, "meals": true, "fetch": true, "tidy": true, "statusBubbles": true },
      "schedule": {
        "breakfast": "09:00", "lunch": "12:30", "dinner": "18:30", "photoDrop": "10:00",
        "breakIntervalMinutes": 50, "fetchThrows": 3
      },
      "theme": {
        "background": "#F6F1E7", "card": "#FFFDF8", "ink": "#3B2219", "border": "#E6DCCB", "accent": "#62BCCB"
      },
      "text": {
        "greeting": "Hi, I'm {name}!",
        "menuPhoto": "Bring me a photo now",
        "menuMeal": "Feed {name}",
        "menuFetch": "Play fetch",
        "menuTidy": "Tidy the desktop",
        "menuSnooze": "Snooze everything for 30 min",
        "menuSleep": "Send {name} to {their} bed",
        "menuWake": "Wake {name} up",
        "menuPhotosFolder": "Open {photosFolder} folder",
        "menuSettings": "Settings…",
        "menuQuit": "Quit {name}",
        "settingsTitle": "{name} Settings",
        "settingsPhotoDrop": "Daily photo drop",
        "settingsMeals": "Meal reminders",
        "settingsFetch": "Break fetch",
        "settingsTidy": "Tidy screenshots",
        "settingsPhotosSection": "Photos of {name}",
        "mealBubble": "time to eat?",
        "selfCareBubble": "now you eat too!",
        "fetchLaterBubble": "later?",
        "thanksButton": "Thanks, {name}",
        "tidyToastOne": "{name} tidied 1 screenshot  ·  Undo",
        "tidyToastMany": "{name} tidied {count} screenshots  ·  Undo",
        "noPhotosBubble": "add photos to {photosFolder} first!",
        "nothingToTidyBubble": "nothing to tidy!"
      }
    }
    """
}

// MARK: - Theme colors

extension PetConfig.Theme {
    var backgroundColor: Color { Color(nsColor: NSColor(hex: background)) }
    var cardColor: Color { Color(nsColor: NSColor(hex: card)) }
    var inkColor: Color { Color(nsColor: NSColor(hex: ink)) }
    var borderColor: Color { Color(nsColor: NSColor(hex: border)) }
    var accentColor: Color { Color(nsColor: NSColor(hex: accent)) }
}

extension NSColor {
    /// "#RRGGBB" → color; anything unparseable comes back magenta so it's obvious.
    convenience init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self.init(calibratedRed: 1, green: 0, blue: 1, alpha: 1)
            return
        }
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
