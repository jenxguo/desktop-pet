import AppKit
import SpriteKit

/// Screenshot tidy, on demand from the menu bar: the pet runs up to the
/// top-right of the screen, grabs a thumbnail of a screenshot in its mouth
/// and carries it down to a folder by the Dock. The file move into the
/// Settings → Screenshots folder is real (the carrying is theater); a toast
/// offers Undo, and clicking the pet mid-trip cancels.
final class TidyMoment: PetMoment {
    static let id = "tidy"
    static let settingsTitleKey = "settingsTidy"
    static let menuTitleKey: String? = "menuTidy"
    static let requiredProps = ["folder"]

    private enum Stage {
        case goingToIcon // traveling (in 2D) to where the screenshot "is"
        case carryingBack // carrying its thumbnail back to the folder spot
    }

    private unowned let scene: PetScene
    private var stage: Stage = .goingToIcon

    private lazy var folderNode: SKSpriteNode = {
        let node = SKSpriteNode(texture: PetProps.texture("folder"))
        node.setScale(scene.renderScale)
        node.zPosition = 1
        return node
    }()

    private var folderSpot: CGPoint { CGPoint(x: 70, y: scene.groundY) }
    private var iconSpot: CGPoint = .zero
    private var pendingURLs: [URL] = []
    private var queuedURLs: [URL] = []
    private var thumbnail: SKNode?
    private var toast: SKNode?
    private var undoFiles: [(from: URL, to: URL)] = []
    private var pendingCancelClick = false
    private var pendingUndoClick = false

    init(scene: PetScene) {
        self.scene = scene
    }

    /// Menu bar → "Tidy the desktop": a sweep of every screenshot and
    /// recording currently sitting there. Queues if another moment's running.
    func triggerNow() {
        let urls = ScreenshotFinder.findAll()
        guard !urls.isEmpty else {
            scene.showNotification(scene.pet.text("nothingToTidyBubble"))
            return
        }
        start(urls: urls)
    }

    func wanderTick(now: Date) {
        startQueued()
    }

    private func start(urls: [URL]) {
        guard scene.begin(self) else {
            queuedURLs.append(contentsOf: urls)
            return
        }

        pendingURLs = urls
        iconSpot = randomIconSpot()
        // Guard against a leftover fade-and-remove sequence from a prior
        // cycle firing later and removing this fresh instance.
        folderNode.removeAllActions()
        folderNode.removeFromParent()
        folderNode.position = CGPoint(
            x: folderSpot.x, y: scene.groundY + folderNode.size.height * scene.renderScale / 2
        )
        folderNode.alpha = 0
        scene.addChild(folderNode)
        folderNode.run(SKAction.fadeIn(withDuration: 0.2))
        enter(.goingToIcon)
    }

    private func startQueued() {
        guard scene.isWandering, !queuedURLs.isEmpty else { return }
        let next = queuedURLs
        queuedURLs = []
        start(urls: next)
    }

    /// Where it heads to "grab" the screenshot. The app can't know where
    /// Finder draws an icon, so this picks a fresh spot in the upper-right
    /// (where new Desktop icons land) each trip rather than the same pixel.
    private func randomIconSpot() -> CGPoint {
        let size = scene.size
        return CGPoint(
            x: .random(in: size.width * 0.55...(size.width - 50)),
            y: .random(in: size.height * 0.55...(size.height - 50))
        )
    }

    func update(dt: CGFloat) {
        let speed = scene.pet.movement.tidySpeed
        switch stage {
        case .goingToIcon:
            if scene.travel(toward: iconSpot, dt: dt, speed: speed) {
                attachThumbnail()
                enter(.carryingBack)
            }
        case .carryingBack:
            if scene.travel(toward: folderSpot, dt: dt, speed: speed) {
                finish()
            }
        }
    }

    private func enter(_ newStage: Stage) {
        stage = newStage
        scene.resetPose()
        scene.loop(PetSprites.run, timePerFrame: 0.085)
    }

    /// A tiny thumbnail of the actual screenshot, pinned to the mouth.
    private func attachThumbnail() {
        removeThumbnail()
        guard let url = pendingURLs.first, let image = NSImage(contentsOf: url) else { return }

        let thumb = SKSpriteNode(texture: SKTexture(image: image), size: CGSize(width: 20, height: 14))
        thumb.position = .zero
        thumb.zPosition = 4
        thumb.setScale(1 / scene.renderScale) // cancel the scale inherited via mouthAnchor -> dog
        scene.mouthAnchor.addChild(thumb)
        thumbnail = thumb
    }

    private func removeThumbnail() {
        thumbnail?.removeFromParent()
        thumbnail = nil
    }

    // MARK: - Mouse

    func isInteractive(at point: CGPoint) -> Bool {
        isOverToast(point)
    }

    /// The undo toast outlives the moment itself, so it isn't gated on being active.
    private func isOverToast(_ point: CGPoint) -> Bool {
        guard let toast else { return false }
        return scene.isOverNode(toast, point, padding: 6)
    }

    func mouseDown(at point: CGPoint, event: NSEvent) -> Bool {
        if isOverToast(point) {
            pendingUndoClick = true
            return true
        }
        if scene.isActive(self), scene.isOverDog(point) {
            pendingCancelClick = true
            return true
        }
        return false
    }

    func mouseUp(at point: CGPoint, event: NSEvent) {
        if pendingUndoClick {
            pendingUndoClick = false
            undo()
        } else if pendingCancelClick {
            pendingCancelClick = false
            cancel()
        }
    }

    // MARK: - Finishing

    /// Clicking mid-trip — before the real move — cancels it entirely.
    /// Nothing moves; those files wait for the next "Tidy the desktop".
    private func cancel() {
        guard scene.isActive(self) else { return }
        pendingURLs = []
        removeThumbnail()
        folderNode.removeFromParent()
        scene.endMoment()
        startQueued()
    }

    private func finish() {
        removeThumbnail()
        let moved = performMove(urls: pendingURLs)
        pendingURLs = []
        if !moved.isEmpty {
            showUndoToast(movedFiles: moved)
        }

        // Linger a moment next to the toast ("that's where it went"), then go.
        folderNode.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.5),
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent(),
        ]))

        scene.endMoment()
        startQueued()
    }

    /// The actual, real file move — everything else here is theater.
    private func performMove(urls: [URL]) -> [(from: URL, to: URL)] {
        let folder = PetSettings.shared.screenshotsDestination
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var moved: [(from: URL, to: URL)] = []
        for url in urls {
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.moveItem(at: url, to: destination)
                moved.append((from: url, to: destination))
            } catch {
                continue // best effort; leave this one where it is
            }
        }
        return moved
    }

    private func showUndoToast(movedFiles: [(from: URL, to: URL)]) {
        toast?.removeFromParent()
        undoFiles = movedFiles

        let count = movedFiles.count
        let message = count == 1
            ? scene.pet.text("tidyToastOne")
            : scene.pet.text("tidyToastMany", ["count": String(count)])
        let toast = scene.makeSpeechBubble(text: message)
        toast.position = CGPoint(x: scene.size.width / 2, y: scene.size.height - 50)
        scene.addChild(toast)
        self.toast = toast

        let hold = SKAction.wait(forDuration: 8)
        let fade = SKAction.fadeOut(withDuration: 0.6)
        let clear = SKAction.run { [weak self] in
            self?.toast = nil
            self?.undoFiles = []
        }
        toast.run(SKAction.sequence([hold, fade, clear, SKAction.removeFromParent()]))
    }

    private func undo() {
        for move in undoFiles {
            try? FileManager.default.moveItem(at: move.to, to: move.from)
        }
        undoFiles = []
        toast?.removeFromParent()
        toast = nil
    }
}
