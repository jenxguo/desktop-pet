import AppKit
import SpriteKit

/// Loads the pet's frames from `Pet/sprites/*.png` as nearest-filtered
/// SpriteKit textures. Every frame is `sprite.frameWidth × frameHeight`,
/// transparent and facing right; the scene flips `xScale` to face left.
///
/// Animations are numbered (`walk_0.png`, `walk_1.png`, …) and can have any
/// number of frames. Loaded straight off disk rather than as an SPM resource
/// bundle, so swapping art never needs a recompile.
///
/// `tools/check_pet.py` checks a pet folder against this list.
enum PetSprites {
    static let stand = required("stand")
    static let walk = animation("walk", fallback: [stand])
    static let run = animation("run", fallback: walk)
    static let sit = optional("sit", fallback: stand)
    static let sleep = optional("sleep", fallback: sit)
    /// Wander's idle sniff. Without its own frame it bobs the `stand` frame.
    static let sniff = optional("sniff", fallback: stand)
    /// Shown while being dragged around (tilted).
    static let dangle = optional("dangle", fallback: stand)
    static let eat = optional("eat", fallback: sit)
    static let playBow = optional("play_bow", fallback: stand)
    static let carryBall = animation("carry_ball", fallback: run)

    /// Front-facing portrait for the menu header (and the app icon, via
    /// scripts/build-app.sh).
    static let portrait: NSImage? = {
        for name in ["portrait.png", "portrait.svg"] {
            if let image = NSImage(contentsOf: directory.appendingPathComponent(name)) {
                return image
            }
        }
        return nil
    }()

    /// A tiny procedural pixel-art heart for the pet reaction — pink and
    /// white, blocky like the rest of the sprites, rather than the system's
    /// smooth color emoji.
    static let pixelHeart: SKTexture = makePixelHeart()

    static var directory: URL { PetConfig.directory.appendingPathComponent("sprites", isDirectory: true) }

    private static func required(_ name: String) -> SKTexture {
        guard let texture = load(directory.appendingPathComponent("\(name).png")) else {
            fatalError("Missing required sprite \(name).png in \(directory.path)")
        }
        return texture
    }

    private static func optional(_ name: String, fallback: SKTexture) -> SKTexture {
        if let texture = load(directory.appendingPathComponent("\(name).png")) { return texture }
        warnMissing("\(name).png")
        return fallback
    }

    /// `name_0.png`, `name_1.png`, … up to the first gap.
    private static func animation(_ name: String, fallback: [SKTexture]) -> [SKTexture] {
        var frames: [SKTexture] = []
        while let texture = load(directory.appendingPathComponent("\(name)_\(frames.count).png")) {
            frames.append(texture)
        }
        if frames.isEmpty {
            warnMissing("\(name)_0.png")
            return fallback
        }
        return frames
    }

    private static func warnMissing(_ file: String) {
        FileHandle.standardError.write(Data("ℹ️  No \(file) — using a stand-in frame.\n".utf8))
    }

    static func load(_ url: URL) -> SKTexture? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }

    /// 7×6 grid: 1 = hot pink, 2 = white sparkle, 0 = transparent.
    private static func makePixelHeart() -> SKTexture {
        let pattern: [[UInt8]] = [
            [0, 1, 1, 0, 1, 1, 0],
            [1, 2, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 1],
            [0, 1, 1, 1, 1, 1, 0],
            [0, 0, 1, 1, 1, 0, 0],
            [0, 0, 0, 1, 0, 0, 0],
        ]
        let rows = pattern.count
        let cols = pattern[0].count

        let image = NSImage(size: CGSize(width: cols, height: rows))
        image.lockFocus()
        let hotPink = NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.69, alpha: 1)
        for (rowIndex, row) in pattern.enumerated() {
            for (colIndex, value) in row.enumerated() where value != 0 {
                (value == 2 ? NSColor.white : hotPink).setFill()
                // Image coordinates are bottom-left; the pattern above is top-down.
                let y = rows - 1 - rowIndex
                NSRect(x: colIndex, y: y, width: 1, height: 1).fill()
            }
        }
        image.unlockFocus()

        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }
}

/// Prop art from `Pet/props/*.png`, pixel art at 1× — rendered at the
/// pet's `sprite.scale` so everything shares the same pixel density. Each
/// moment only loads the props it uses, so a pet without fetch doesn't need
/// a ball (see `PetMoment.requiredProps`).
enum PetProps {
    /// Props the included moments need that aren't in `Pet/props/`.
    static func missing() -> [String] {
        let folder = PetConfig.directory.appendingPathComponent("props")
        return PetMoments.included.flatMap { moment in
            moment.requiredProps.filter {
                !FileManager.default.fileExists(atPath: folder.appendingPathComponent("\($0).png").path)
            }.map { "props/\($0).png (for \(moment.id))" }
        }
    }

    static func texture(_ name: String) -> SKTexture {
        let url = PetConfig.directory.appendingPathComponent("props/\(name).png")
        guard let texture = PetSprites.load(url) else {
            fatalError("Missing prop \(name).png in \(url.deletingLastPathComponent().path)")
        }
        return texture
    }
}
