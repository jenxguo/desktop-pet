import AppKit
import SpriteKit

/// Daily photo drop: once a day, after the time set in Settings, the pet
/// runs up with a polaroid of a random photo from `~/Pictures/<Pet> Photos/`
/// in its mouth and drops it. Click the polaroid to open it big; ignored for
/// two minutes, the pet picks it back up.
final class PhotoDropMoment: PetMoment {
    static let id = "photoDrop"
    static let settingsTitleKey = "settingsPhotoDrop"
    static let menuTitleKey: String? = "menuPhoto"

    private enum Stage {
        case running
        case waiting
        case pickingUp
    }

    private unowned let scene: PetScene
    private var stage: Stage = .running
    private var stageTimeRemaining: TimeInterval = 0
    private var runDestinationX: CGFloat = 0
    private var photoURL: URL?
    private var polaroidNode: SKNode?
    private var pendingPolaroidClick = false
    private var activeCardWindow: PolaroidCardWindow?

    private let polaroidCardSize = CGSize(width: 40, height: 48)
    private let polaroidPhotoSize = CGSize(width: 34, height: 34)
    /// Half size while carried, versus once it's down on the ground.
    private let carriedPolaroidScale: CGFloat = 0.5
    private var lastDropDateKey: String { scene.defaultsKey("lastPhotoDropDate") }

    init(scene: PetScene) {
        self.scene = scene
    }

    /// Menu bar → "Bring me a photo now". Does nothing if another moment is
    /// running or the photo folder is empty.
    func triggerNow() {
        guard scene.isWandering, let url = PhotoLibrary.pickPhoto() else { return }
        UserDefaults.standard.set(Date(), forKey: lastDropDateKey)
        start(photoURL: url)
    }

    func wanderTick(now: Date) {
        guard !scene.isGloballySnoozed(now: now) else { return }

        let calendar = Calendar.current
        let settings = PetSettings.shared
        guard
            let todayTrigger = calendar.date(
                bySettingHour: settings.photoDropHour, minute: settings.photoDropMinute, second: 0, of: now
            ),
            now >= todayTrigger
        else { return }

        if let last = UserDefaults.standard.object(forKey: lastDropDateKey) as? Date,
           calendar.isDate(last, inSameDayAs: now) {
            return // already dropped today
        }

        triggerNow()
    }

    private func start(photoURL: URL) {
        guard scene.begin(self) else { return }
        self.photoURL = photoURL

        let travel = CGFloat.random(in: 80...180) * (Bool.random() ? 1 : -1)
        runDestinationX = scene.clampedX(scene.dog.position.x + travel)
        scene.direction = runDestinationX >= scene.dog.position.x ? 1 : -1

        enter(.running)
        attachPolaroidToMouth(photoURL: photoURL)
    }

    func update(dt: CGFloat) {
        switch stage {
        case .running:
            if scene.runAlongGround(toward: runDestinationX, dt: dt) {
                stageTimeRemaining = 120 // 2 minutes
                enter(.waiting)
            }
        case .waiting:
            stageTimeRemaining -= TimeInterval(dt)
            if stageTimeRemaining <= 0 {
                stageTimeRemaining = 0.6
                enter(.pickingUp)
            }
        case .pickingUp:
            stageTimeRemaining -= TimeInterval(dt)
            if stageTimeRemaining <= 0 {
                finish()
            }
        }
    }

    private func enter(_ newStage: Stage) {
        stage = newStage
        scene.resetPose()

        switch newStage {
        case .running:
            scene.loop(PetSprites.run, timePerFrame: scene.pet.movement.runFrameSeconds)
        case .waiting:
            scene.dog.texture = PetSprites.sit
            dropPolaroidToGround()
        case .pickingUp:
            scene.dog.texture = PetSprites.stand
            removePolaroid()
        }
    }

    // MARK: - Mouse

    func isInteractive(at point: CGPoint) -> Bool {
        isOverDroppedPolaroid(point)
    }

    func mouseDown(at point: CGPoint, event: NSEvent) -> Bool {
        guard isOverDroppedPolaroid(point) else { return false }
        pendingPolaroidClick = true
        return true
    }

    func mouseUp(at point: CGPoint, event: NSEvent) {
        guard pendingPolaroidClick else { return }
        pendingPolaroidClick = false
        openPolaroidCard()
    }

    /// Only once it's actually been dropped — while it's riding along in the
    /// mouth it's parented under `mouthAnchor`, a different coordinate space.
    private func isOverDroppedPolaroid(_ point: CGPoint) -> Bool {
        guard scene.isActive(self), stage == .waiting, let polaroidNode else { return false }
        return scene.isOverNode(polaroidNode, point, padding: 6)
    }

    // MARK: - Polaroid

    /// Builds the real photo as a little polaroid card and pins it to the
    /// mouth while running.
    private func attachPolaroidToMouth(photoURL: URL) {
        removePolaroid()
        guard let image = NSImage(contentsOf: photoURL) else { return }
        let card = makePolaroidCard(image: image)
        card.position = .zero
        // `mouthAnchor` is a child of `dog`, which is rendered at the pet's
        // scale — compensate so the card doesn't inherit it.
        card.setScale(carriedPolaroidScale / scene.renderScale)
        scene.mouthAnchor.addChild(card)
        polaroidNode = card
    }

    /// Reparents the polaroid from the mouth to the scene at wherever it
    /// currently is, then animates it down to the ground beside the pet,
    /// growing to full size.
    private func dropPolaroidToGround() {
        guard let card = polaroidNode else { return }

        let currentScenePosition = scene.convert(.zero, from: card)
        card.removeFromParent()
        card.position = currentScenePosition
        card.setScale(carriedPolaroidScale)
        scene.addChild(card)

        let groundSpot = CGPoint(
            x: scene.dog.position.x - scene.direction * scene.bodyWidth * 0.24,
            y: scene.groundY + polaroidCardSize.height / 2
        )
        let move = SKAction.move(to: groundSpot, duration: 0.25)
        move.timingMode = .easeIn
        let growToFullSize = SKAction.scale(to: 1, duration: 0.25)
        growToFullSize.timingMode = .easeIn
        card.run(SKAction.group([move, growToFullSize]))
    }

    private func makePolaroidCard(image: NSImage) -> SKShapeNode {
        let card = SKShapeNode(rectOf: polaroidCardSize, cornerRadius: 2)
        card.fillColor = NSColor(hex: scene.pet.theme.card)
        card.strokeColor = NSColor(hex: scene.pet.theme.ink)
        card.lineWidth = 1.5
        card.zPosition = 4

        let photo = SKSpriteNode(texture: SKTexture(image: image), size: polaroidPhotoSize)
        photo.position = CGPoint(x: 0, y: 4)
        card.addChild(photo)
        return card
    }

    private func removePolaroid() {
        polaroidNode?.removeFromParent()
        polaroidNode = nil
    }

    private func openPolaroidCard() {
        guard
            scene.isActive(self), stage == .waiting,
            let url = photoURL,
            let image = NSImage(contentsOf: url)
        else { return }

        stageTimeRemaining = .infinity // the 2-min pickup timeout no longer applies once it's open

        let window = PolaroidCardWindow(image: image) { [weak self] in
            self?.activeCardWindow = nil
            self?.finish()
        }
        activeCardWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        removePolaroid()
        photoURL = nil
        if scene.isActive(self) { scene.endMoment() }
    }
}
