import AppKit
import CoreGraphics
import SpriteKit

/// Break fetch: after N minutes of active computer use (Settings → Break
/// every), the pet trots over, drops a ball and play-bows. Drag and fling
/// the ball; the pet chases it and brings it back, `fetchThrows` times. Click
/// "later?" to snooze 10 minutes. Uses the `play_bow` and `carry_ball_N` frames.
final class FetchMoment: PetMoment {
    static let id = "fetch"
    static let settingsTitleKey = "settingsFetch"
    static let menuTitleKey: String? = "menuFetch"
    static let requiredProps = ["ball"]

    private enum Stage {
        case arriving // trotting to the fetch spot with the ball
        case invite // ball dropped, play-bowing then waiting to be thrown
        case flying // ball's in the air/rolling; the pet's chasing it
        case returning // caught it, carrying it back to the fetch spot
    }

    private unowned let scene: PetScene
    private var stage: Stage = .arriving

    private static let snoozeDuration: TimeInterval = 10 * 60
    private static let friction: CGFloat = 0.985 // per-frame multiplicative decay at 60fps
    private static let gravity: CGFloat = -900 // points/sec^2
    private static let bounceDamping: CGFloat = 0.55
    private static let catchDistance: CGFloat = 20
    private static let catchSpeed: CGFloat = 40 // only catchable once it's slowed down this much

    private lazy var ballTexture = PetProps.texture("ball")
    /// On screen, for edge bounces and resting height.
    private var ballRadius: CGFloat { ballTexture.size().height * scene.renderScale / 2 }

    /// Seconds of active (non-idle) system use accumulated since the last fetch.
    private var activeUseSeconds: TimeInterval = 0
    private var throwsRemaining = 0
    private var fetchSpot: CGPoint = .zero
    private var ballNode: SKSpriteNode?
    private var ballVelocity = CGVector.zero
    private var laterBubble: SKNode?
    private var pendingLaterClick = false

    /// Recent drag samples, used to compute a release velocity on mouseUp —
    /// an actual fling, not just a teleport-and-drop.
    private var isDraggingBall = false
    private var dragAnchor: CGPoint = .zero
    private var dragOrigin: CGPoint = .zero
    private var dragSample: (point: CGPoint, time: TimeInterval)?
    private var flingVelocity = CGVector.zero

    private var snoozeKey: String { scene.defaultsKey("fetchSnoozeUntil") }

    init(scene: PetScene) {
        self.scene = scene
    }

    /// Menu bar testing aid. Doesn't touch `activeUseSeconds`'s accumulation.
    func triggerNow() {
        start()
    }

    func wanderTick(now: Date) {
        // Counts this 5s tick as active use only if there was real input
        // somewhere on the system within it, so stepping away pauses the
        // count instead of firing fetch the moment you're back.
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        if idleSeconds < 5 {
            activeUseSeconds += 5
        }

        if let snoozeUntil = UserDefaults.standard.object(forKey: snoozeKey) as? Date, now < snoozeUntil {
            return
        }
        guard !scene.isGloballySnoozed(now: now) else { return }

        if activeUseSeconds >= TimeInterval(PetSettings.shared.breakIntervalMinutes) * 60 {
            start()
        }
    }

    private func start() {
        guard scene.begin(self) else { return }
        throwsRemaining = max(1, scene.pet.schedule.fetchThrows)

        let travel = CGFloat.random(in: 60...140) * (Bool.random() ? 1 : -1)
        fetchSpot = CGPoint(x: scene.clampedX(scene.dog.position.x + travel), y: scene.groundY)
        scene.direction = fetchSpot.x >= scene.dog.position.x ? 1 : -1

        enter(.arriving)
    }

    func update(dt: CGFloat) {
        switch stage {
        case .arriving:
            if scene.runAlongGround(toward: fetchSpot.x, dt: dt) {
                enter(.invite)
            }
        case .invite:
            break // event-driven: drag-and-fling the ball, or click "later?"
        case .flying:
            updateBallPhysics(dt: dt)
            chaseBall(dt: dt)
        case .returning:
            if scene.runAlongGround(toward: fetchSpot.x, dt: dt) {
                finishReturn()
            }
        }
    }

    private func enter(_ newStage: Stage) {
        stage = newStage
        scene.resetPose()

        switch newStage {
        case .arriving, .flying:
            scene.loop(PetSprites.run, timePerFrame: scene.pet.movement.runFrameSeconds)
        case .invite:
            scene.dog.texture = PetSprites.playBow
            spawnInviteProps()
        case .returning:
            scene.loop(PetSprites.carryBall, timePerFrame: 0.1)
        }
    }

    private func spawnInviteProps() {
        removeProps()

        let ball = SKSpriteNode(texture: ballTexture)
        ball.setScale(scene.renderScale)
        ball.zPosition = 5
        ball.position = CGPoint(
            x: scene.dog.position.x - scene.direction * scene.bodyWidth * 0.2,
            y: scene.groundY + ballRadius
        )
        scene.addChild(ball)
        ballNode = ball
        ballVelocity = .zero

        let bubble = scene.makeSpeechBubble(text: scene.pet.text("fetchLaterBubble"))
        scene.addChild(bubble)
        laterBubble = bubble
    }

    // MARK: - Mouse

    private var isInviting: Bool { scene.isActive(self) && stage == .invite }

    func isInteractive(at point: CGPoint) -> Bool {
        guard isInviting else { return false }
        if let laterBubble, scene.isOverNode(laterBubble, point, padding: 6) { return true }
        if let ballNode, scene.isOverNode(ballNode, point, padding: 10) { return true }
        return false
    }

    func mouseDown(at point: CGPoint, event: NSEvent) -> Bool {
        guard isInviting else { return false }
        if let laterBubble, scene.isOverNode(laterBubble, point, padding: 6) {
            pendingLaterClick = true
            return true
        }
        if let ballNode, scene.isOverNode(ballNode, point, padding: 10) {
            isDraggingBall = true
            dragAnchor = point
            dragOrigin = ballNode.position
            dragSample = (point, event.timestamp)
            flingVelocity = .zero
            return true
        }
        return false
    }

    func mouseDragged(to point: CGPoint, event: NSEvent) {
        guard isDraggingBall else { return }
        ballNode?.position = CGPoint(x: dragOrigin.x + point.x - dragAnchor.x, y: dragOrigin.y + point.y - dragAnchor.y)
        // Track velocity from the most recent drag segment, not the whole
        // gesture, so a release reflects the actual flick.
        if let sample = dragSample {
            let interval = event.timestamp - sample.time
            if interval > 0.004 {
                flingVelocity = CGVector(
                    dx: (point.x - sample.point.x) / interval,
                    dy: (point.y - sample.point.y) / interval
                )
                dragSample = (point, event.timestamp)
            }
        }
    }

    func mouseUp(at point: CGPoint, event: NSEvent) {
        if pendingLaterClick {
            pendingLaterClick = false
            snooze()
            return
        }
        guard isDraggingBall else { return }
        isDraggingBall = false
        dragSample = nil
        throwBall(velocity: flingVelocity)
    }

    // MARK: - Ball

    /// A real flick carries its release velocity (capped); a plain
    /// drop-and-release still tosses it gently so it's not a dead end.
    private func throwBall(velocity: CGVector) {
        guard isInviting, ballNode != nil else { return }
        laterBubble?.removeFromParent()
        laterBubble = nil

        let minSpeed: CGFloat = 60
        let speed = hypot(velocity.dx, velocity.dy)
        if speed < minSpeed {
            let angle = CGFloat.random(in: 0.3...2.8) // up and outward, not straight into the ground
            ballVelocity = CGVector(dx: cos(angle) * 220, dy: sin(angle) * 220)
        } else {
            let scale = min(speed, 900) / speed
            ballVelocity = CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)
        }

        enter(.flying)
    }

    private func updateBallPhysics(dt: CGFloat) {
        guard let ballNode else { return }

        // Gravity guarantees the ball always ends up resting on the ground,
        // within reach — without it, it could settle mid-air.
        ballVelocity.dy += Self.gravity * dt

        var position = ballNode.position
        position.x += ballVelocity.dx * dt
        position.y += ballVelocity.dy * dt

        let minX = ballRadius
        let maxX = scene.size.width - ballRadius
        let floor = scene.groundY + ballRadius
        let ceiling = scene.size.height - ballRadius

        if position.x < minX {
            position.x = minX
            ballVelocity.dx = -ballVelocity.dx * Self.bounceDamping
        } else if position.x > maxX {
            position.x = maxX
            ballVelocity.dx = -ballVelocity.dx * Self.bounceDamping
        }

        if position.y < floor {
            position.y = floor
            ballVelocity.dy = -ballVelocity.dy * Self.bounceDamping
            ballVelocity.dx *= Self.bounceDamping // a bounce scrubs horizontal speed too
            if abs(ballVelocity.dy) < 40 {
                ballVelocity.dy = 0 // stop micro-bouncing forever and actually settle
            }
        } else if position.y > ceiling {
            position.y = ceiling
            ballVelocity.dy = -ballVelocity.dy * Self.bounceDamping
        }

        // Rolling friction only really applies once it's down on the ground.
        if position.y <= floor {
            ballVelocity.dx *= pow(Self.friction, dt * 60)
        }

        ballNode.position = position
        ballNode.zRotation += (ballVelocity.dx / ballRadius) * dt // simple rolling spin
    }

    private func chaseBall(dt: CGFloat) {
        guard let ballNode else { return }
        let dog = scene.dog

        scene.direction = ballNode.position.x >= dog.position.x ? 1 : -1
        scene.faceDirection()

        let distance = hypot(ballNode.position.x - dog.position.x, ballNode.position.y - dog.position.y)
        let ballSpeed = hypot(ballVelocity.dx, ballVelocity.dy)
        if distance < Self.catchDistance && ballSpeed < Self.catchSpeed {
            catchBall()
            return
        }

        dog.position.x = scene.clampedX(dog.position.x + scene.direction * scene.runSpeed * dt)
    }

    private func catchBall() {
        ballNode?.removeFromParent()
        ballNode = nil
        ballVelocity = .zero
        enter(.returning)
    }

    private func finishReturn() {
        throwsRemaining -= 1
        if throwsRemaining > 0 {
            enter(.invite)
        } else {
            finish()
        }
    }

    private func snooze() {
        UserDefaults.standard.set(Date().addingTimeInterval(Self.snoozeDuration), forKey: snoozeKey)
        finish()
    }

    private func removeProps() {
        ballNode?.removeFromParent()
        ballNode = nil
        laterBubble?.removeFromParent()
        laterBubble = nil
    }

    private func finish() {
        removeProps()
        activeUseSeconds = 0
        scene.endMoment()
    }
}
