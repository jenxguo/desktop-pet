import AppKit
import SpriteKit

/// The pet's whole world: one SpriteKit scene covering the screen.
///
/// When no moment is active the pet wanders (walk / sit / sniff / sleep),
/// can be clicked to pet and dragged around. Moments (`Moments/`) take over
/// one at a time and use the helpers here to move and pose the pet; status
/// bubbles from NotificationWatcher float above it whatever it's doing.
final class PetScene: SKScene {
    private enum Phase {
        case walking
        case sitting
        case sniffing
        case sleeping
        case dragging
    }

    let pet = PetConfig.current
    let dog = SKSpriteNode(texture: PetSprites.stand)
    /// Child of `dog` at the mouth point from `pet.json`; carried props go here.
    let mouthAnchor = SKNode()

    private(set) var moments: [PetMoment] = []
    private(set) var activeMoment: PetMoment?

    let margin: CGFloat = 32 // keep clear of screen edges before turning
    private let dragStartThreshold: CGFloat = 4

    private(set) var groundY: CGFloat = 0
    var direction: CGFloat = 1
    private var phase: Phase = .walking
    private var phaseTimeRemaining: TimeInterval = 0
    private var lastUpdateTime: TimeInterval?
    private var lastScheduleCheck: TimeInterval = 0

    /// Set from mouseDown until mouseUp. While a click/drag session is active
    /// we must not let the window go back to ignoring the mouse, or we'd lose
    /// the matching mouseDragged/mouseUp events.
    private(set) var isPointerCaptured = false
    private var pointerOwner: PetMoment?
    private var dogDragAnchor: CGPoint?
    private var dogDragOrigin: CGPoint?

    private static let globalSnoozeUntilKey = "globalSnoozeUntil"

    /// A toast from NotificationWatcher's dropped files — e.g. "Claude's
    /// done!" from a Claude Code hook. Independent of moments entirely: it's
    /// a status ping, not something the pet stops to act out.
    private var notificationBubble: SKNode?
    private var notificationQueue: [String] = []

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
        moments = PetMoments.included.map { $0.init(scene: self) }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        groundY = (NSScreen.main?.visibleFrame.minY ?? 0) + 4

        // Anchor the sprite at its feet (not its center) so `dog.position`
        // sits exactly on the ground line.
        let feetFraction = (pet.sprite.frameHeight - pet.sprite.feetY) / pet.sprite.frameHeight
        dog.anchorPoint = CGPoint(x: 0.5, y: feetFraction)
        dog.xScale = renderScale
        dog.yScale = renderScale
        dog.position = CGPoint(x: size.width / 2, y: groundY)
        addChild(dog)

        positionMouthAnchor()
        dog.addChild(mouthAnchor)

        applyAppearance(for: phase)
        scheduleNextPhase()
    }

    private func positionMouthAnchor() {
        let mouth = pet.sprite.mouth.count == 2 ? pet.sprite.mouth : [pet.sprite.frameWidth / 2, 0]
        let mouthFromBottomLeft = CGPoint(x: mouth[0], y: pet.sprite.frameHeight - mouth[1])
        let originFromBottomLeft = CGPoint(
            x: dog.anchorPoint.x * pet.sprite.frameWidth,
            y: dog.anchorPoint.y * pet.sprite.frameHeight
        )
        mouthAnchor.position = CGPoint(
            x: mouthFromBottomLeft.x - originFromBottomLeft.x,
            y: mouthFromBottomLeft.y - originFromBottomLeft.y
        )
    }

    // MARK: - Helpers for moments

    var renderScale: CGFloat { pet.sprite.scale }
    var walkSpeed: CGFloat { pet.movement.walkSpeed }
    var runSpeed: CGFloat { pet.movement.runSpeed }

    /// On-screen width of one frame — moments lay props out relative to it
    /// so they still fit around a bigger or smaller pet.
    var bodyWidth: CGFloat { pet.sprite.frameWidth * renderScale }

    /// Just above the top of the frame, in scene coordinates.
    var headTopY: CGFloat { dog.position.y + (pet.sprite.feetY + 1) * renderScale }

    var isWandering: Bool { activeMoment == nil }

    func isActive(_ moment: PetMoment) -> Bool { activeMoment === moment }

    /// Starts `moment` unless another one is already running.
    @discardableResult
    func begin(_ moment: PetMoment) -> Bool {
        guard activeMoment == nil else { return false }
        if phase == .dragging { return false }
        activeMoment = moment
        resetPose()
        return true
    }

    /// Back to wandering.
    func endMoment() {
        activeMoment = nil
        phase = .walking
        applyAppearance(for: .walking)
        scheduleNextPhase()
    }

    func moment(id: String) -> PetMoment? {
        moments.first { type(of: $0).id == id }
    }

    /// Stops any running animation and resets scale/rotation/alpha so the
    /// next pose starts clean.
    func resetPose() {
        dog.removeAction(forKey: "anim")
        dog.removeAction(forKey: "bob")
        dog.removeAction(forKey: "pet")
        dog.zRotation = 0
        dog.alpha = 1
        dog.xScale = direction * renderScale
        dog.yScale = renderScale
    }

    func loop(_ frames: [SKTexture], timePerFrame: TimeInterval) {
        dog.removeAction(forKey: "anim")
        dog.run(
            SKAction.repeatForever(
                SKAction.animate(with: frames, timePerFrame: timePerFrame, resize: false, restore: false)
            ),
            withKey: "anim"
        )
    }

    func faceDirection() {
        dog.xScale = direction * renderScale
    }

    func clampedX(_ x: CGFloat) -> CGFloat {
        min(max(x, margin), size.width - margin)
    }

    /// Runs along the ground toward `x`. Returns true once there.
    @discardableResult
    func runAlongGround(toward x: CGFloat, dt: CGFloat, speed: CGFloat? = nil) -> Bool {
        if abs(dog.position.x - x) < 4 {
            dog.position.x = x
            return true
        }
        direction = x >= dog.position.x ? 1 : -1
        faceDirection()
        dog.position.x = clampedX(dog.position.x + direction * (speed ?? runSpeed) * dt)
        return false
    }

    /// Moves one step toward `target` in both x and y (most moments only
    /// travel along the ground) and faces the right way. True once arrived.
    @discardableResult
    func travel(toward target: CGPoint, dt: CGFloat, speed: CGFloat) -> Bool {
        let dx = target.x - dog.position.x
        let dy = target.y - dog.position.y
        let distance = hypot(dx, dy)

        if abs(dx) > 1 {
            direction = dx >= 0 ? 1 : -1
            faceDirection()
        }

        let step = speed * dt
        if step >= distance {
            dog.position = target
            return true
        }

        dog.position = CGPoint(x: dog.position.x + dx / distance * step, y: dog.position.y + dy / distance * step)
        return false
    }

    /// A speech bubble just above the pet's head, in the theme's card/ink
    /// colors. Not added to the scene — the caller does that.
    func makeSpeechBubble(text: String) -> SKShapeNode {
        let ink = NSColor(hex: pet.theme.ink)
        let label = SKLabelNode(text: text)
        label.fontSize = 11
        label.fontColor = ink
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        let padding: CGFloat = 10
        let bubbleSize = CGSize(width: label.frame.width + padding * 2, height: label.frame.height + padding)
        let bubble = SKShapeNode(rectOf: bubbleSize, cornerRadius: 10)
        bubble.fillColor = NSColor(hex: pet.theme.card)
        bubble.strokeColor = ink
        bubble.lineWidth = 2
        bubble.zPosition = 6
        bubble.addChild(label)
        bubble.position = CGPoint(x: dog.position.x, y: headTopY + bubbleSize.height / 2 + 6)
        return bubble
    }

    func isOverNode(_ node: SKNode, _ point: CGPoint, padding: CGFloat) -> Bool {
        node.calculateAccumulatedFrame().insetBy(dx: -padding, dy: -padding).contains(point)
    }

    func isOverDog(_ point: CGPoint) -> Bool {
        isOverNode(dog, point, padding: 14)
    }

    /// Namespaced UserDefaults key, for moments' own bookkeeping.
    func defaultsKey(_ name: String) -> String {
        "DesktopPet.\(name)"
    }

    // MARK: - Snooze

    /// Menu bar → "Snooze everything for 30 min".
    func snoozeEverything(minutes: Int = 30) {
        UserDefaults.standard.set(
            Date().addingTimeInterval(TimeInterval(minutes) * 60), forKey: defaultsKey(Self.globalSnoozeUntilKey)
        )
    }

    func isGloballySnoozed(now: Date) -> Bool {
        guard let until = UserDefaults.standard.object(forKey: defaultsKey(Self.globalSnoozeUntilKey)) as? Date else {
            return false
        }
        return now < until
    }

    // MARK: - Hit testing (called by OverlayWindow's cursor poll)

    /// `point` is in this scene's coordinate space (view and scene share the
    /// same size and bottom-left origin, so window-local points map 1:1).
    func isInteractive(at point: CGPoint) -> Bool {
        isOverDog(point) || moments.contains { $0.isInteractive(at: point) }
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        let point = event.location(in: self)

        for moment in moments where moment.mouseDown(at: point, event: event) {
            isPointerCaptured = true
            pointerOwner = moment
            return
        }

        guard isWandering, isOverDog(point) else { return }
        isPointerCaptured = true
        dogDragAnchor = point
        dogDragOrigin = dog.position
    }

    override func mouseDragged(with event: NSEvent) {
        let point = event.location(in: self)
        if let pointerOwner {
            pointerOwner.mouseDragged(to: point, event: event)
            return
        }

        guard let dogDragAnchor, let dogDragOrigin else { return }
        let dx = point.x - dogDragAnchor.x
        let dy = point.y - dogDragAnchor.y
        if phase != .dragging && (abs(dx) > dragStartThreshold || abs(dy) > dragStartThreshold) {
            beginDragging()
        }
        guard phase == .dragging else { return }
        dog.position = CGPoint(
            x: min(max(dogDragOrigin.x + dx, 0), size.width),
            y: min(max(dogDragOrigin.y + dy, 0), size.height)
        )
    }

    override func mouseUp(with event: NSEvent) {
        isPointerCaptured = false
        let point = event.location(in: self)

        if let owner = pointerOwner {
            pointerOwner = nil
            owner.mouseUp(at: point, event: event)
            return
        }

        defer {
            dogDragAnchor = nil
            dogDragOrigin = nil
        }
        if phase == .dragging {
            endDragging()
        } else if dogDragAnchor != nil {
            petTheAnimal()
        }
    }

    private func beginDragging() {
        phase = .dragging
        dog.removeAction(forKey: "pet")
        applyAppearance(for: .dragging)
    }

    private func endDragging() {
        dog.position.x = clampedX(dog.position.x)
        let settle = SKAction.moveTo(y: groundY, duration: 0.18)
        settle.timingMode = .easeOut
        dog.run(settle) { [weak self] in
            guard let self else { return }
            self.phase = .walking
            self.applyAppearance(for: .walking)
            self.scheduleNextPhase()
        }
    }

    private func petTheAnimal() {
        // Absolute scaleX/scaleY targets, not `scale(by:)` — a relative bump
        // compounds if a rapid repeat tap cancels the sequence (via the
        // shared "pet" key) before it reaches its own reset step.
        let facing = direction
        let bump = renderScale * 1.1
        let bounce = SKAction.sequence([
            SKAction.group([
                SKAction.scaleX(to: facing * bump, duration: 0.1),
                SKAction.scaleY(to: bump, duration: 0.1),
            ]),
            SKAction.group([
                SKAction.scaleX(to: facing * renderScale, duration: 0.2),
                SKAction.scaleY(to: renderScale, duration: 0.2),
            ]),
        ])
        let tint = SKAction.sequence([
            SKAction.colorize(with: .white, colorBlendFactor: 0.5, duration: 0.1),
            SKAction.colorize(withColorBlendFactor: 0, duration: 0.2),
        ])
        dog.run(SKAction.group([bounce, tint]), withKey: "pet")
        spawnHearts()
    }

    /// A few pixel-art hearts float up from the head and fade. Added as
    /// children of the scene, not `dog`, so they don't mirror when facing left.
    private func spawnHearts() {
        let headPosition = CGPoint(x: dog.position.x, y: headTopY)

        for _ in 0..<3 {
            let heart = SKSpriteNode(texture: PetSprites.pixelHeart)
            heart.setScale(.random(in: 2.5...3.5)) // keeps the blocky pixel look crisp
            heart.zPosition = 10
            heart.position = CGPoint(x: headPosition.x + .random(in: -6...6), y: headPosition.y)
            addChild(heart)

            let drift = CGFloat.random(in: -16...16)
            let delay = SKAction.wait(forDuration: .random(in: 0...0.15))
            let rise = SKAction.moveBy(x: drift, y: 36, duration: 0.7)
            rise.timingMode = .easeOut
            let fade = SKAction.sequence([SKAction.wait(forDuration: 0.25), SKAction.fadeOut(withDuration: 0.45)])
            heart.run(SKAction.sequence([delay, SKAction.group([rise, fade]), SKAction.removeFromParent()]))
        }
    }

    // MARK: - Status notifications

    /// A short bubble above the pet that fades on its own — for each
    /// NotificationWatcher file, and for moments with a quick thing to say
    /// ("nothing to tidy!"). Queues if one's already showing.
    func showNotification(_ message: String) {
        guard notificationBubble == nil else {
            notificationQueue.append(message)
            return
        }
        presentNotification(message)
    }

    private func presentNotification(_ message: String) {
        let bubble = makeSpeechBubble(text: message)
        bubble.setScale(0.6)
        bubble.alpha = 0
        addChild(bubble)
        notificationBubble = bubble

        let popIn = SKAction.group([
            SKAction.scale(to: 1, duration: 0.25),
            SKAction.fadeIn(withDuration: 0.15),
        ])
        popIn.timingMode = .easeOut
        let hold = SKAction.wait(forDuration: 4)
        let fadeOut = SKAction.fadeOut(withDuration: 0.4)
        let cleanup = SKAction.run { [weak self] in
            self?.notificationBubble?.removeFromParent()
            self?.notificationBubble = nil
            self?.presentNextQueuedNotification()
        }
        bubble.run(SKAction.sequence([popIn, hold, fadeOut, cleanup]))
    }

    private func presentNextQueuedNotification() {
        guard !notificationQueue.isEmpty else { return }
        presentNotification(notificationQueue.removeFirst())
    }

    // MARK: - Wander phase machine

    private func scheduleNextPhase() {
        switch phase {
        case .walking:
            phaseTimeRemaining = .random(in: 4...9)
        case .sitting:
            phaseTimeRemaining = .random(in: 2...5)
        case .sniffing:
            phaseTimeRemaining = .random(in: 2...4)
        case .sleeping:
            phaseTimeRemaining = .random(in: 8...16)
        case .dragging:
            phaseTimeRemaining = .infinity
        }
    }

    private func advancePhase() {
        switch phase {
        case .walking:
            phase = randomIdlePhase()
        case .sitting, .sniffing, .sleeping:
            phase = .walking
        case .dragging:
            return // handled by beginDragging/endDragging instead
        }
        applyAppearance(for: phase)
        scheduleNextPhase()
    }

    private func randomIdlePhase() -> Phase {
        switch Double.random(in: 0..<1) {
        case 0..<0.45: return .sitting
        case 0.45..<0.7: return .sniffing
        case 0.7..<0.85: return .sleeping
        default: return .walking
        }
    }

    private func walk(dt: CGFloat) {
        var position = dog.position
        position.x += direction * walkSpeed * dt

        if position.x > size.width - margin {
            position.x = size.width - margin
            direction = -1
        } else if position.x < margin {
            position.x = margin
            direction = 1
        }

        dog.position = position
        faceDirection()
    }

    private func applyAppearance(for phase: Phase) {
        // Any phase change is also a clean scale reset, so a pet bounce that
        // gets interrupted mid-animation can never leave it stuck at an
        // intermediate size.
        resetPose()
        // Same idea for height: the sniff "bob" below is a relative moveBy
        // loop that almost always gets cut off mid-rise. Hard-resetting y on
        // every phase change stops those leftovers adding up into a slow
        // drift above the Dock.
        dog.position.y = groundY

        switch phase {
        case .walking:
            loop(PetSprites.walk, timePerFrame: pet.movement.walkFrameSeconds)
        case .sitting:
            dog.texture = PetSprites.sit
        case .sniffing:
            dog.texture = PetSprites.sniff
            let bob = SKAction.repeatForever(
                SKAction.sequence([
                    SKAction.moveBy(x: 0, y: 3, duration: 0.3),
                    SKAction.moveBy(x: 0, y: -3, duration: 0.3),
                ])
            )
            dog.run(bob, withKey: "bob")
        case .sleeping:
            dog.texture = PetSprites.sleep
        case .dragging:
            dog.texture = PetSprites.dangle
            dog.zRotation = direction >= 0 ? -0.2 : 0.2
        }
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdateTime = currentTime }
        guard let lastUpdateTime else { return }
        let dt = CGFloat(currentTime - lastUpdateTime)

        if let activeMoment {
            activeMoment.update(dt: dt)
            return
        }

        updateWander(dt: dt, currentTime: currentTime)
        if currentTime - lastScheduleCheck > 5 {
            lastScheduleCheck = currentTime
            let now = Date()
            for moment in moments where isWandering && PetSettings.shared.isEnabled(type(of: moment).id) {
                moment.wanderTick(now: now)
            }
        }
    }

    private func updateWander(dt: CGFloat, currentTime: TimeInterval) {
        if phase != .dragging {
            phaseTimeRemaining -= TimeInterval(dt)
            if phaseTimeRemaining <= 0 {
                advancePhase()
            }
        }

        if phase == .walking {
            walk(dt: dt)
        } else if phase == .sleeping {
            let breathe = 0.85 + 0.15 * CGFloat(sin(currentTime * 1.6))
            dog.alpha = breathe
        } else {
            dog.alpha = 1
        }
    }
}
