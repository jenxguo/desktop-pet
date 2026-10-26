import AppKit
import SpriteKit

/// Meal reminder: at breakfast, lunch and dinner time the pet sits by two
/// empty bowls and asks "time to eat?". Drag the kibble bag onto the food
/// bowl and the jug onto the water bowl; once both are full it eats, then
/// reminds you to eat too. Click the bubble to snooze that meal 15 minutes.
final class MealMoment: PetMoment {
    static let id = "meals"
    static let settingsTitleKey = "settingsMeals"
    static let menuTitleKey: String? = "menuMeal"
    static let requiredProps = [
        "bowl-food-empty", "bowl-food-full", "bowl-water-empty", "bowl-water-full", "kibble", "jug",
    ]

    private enum Stage {
        case waiting
        case eating
    }

    private enum Dragged {
        case kibble
        case jug
    }

    private struct MealTime {
        let key: String
        let hour: Int
        let minute: Int
    }

    private unowned let scene: PetScene
    private var stage: Stage = .waiting
    private var activeMealKey: String?
    private var foodFilled = false
    private var waterFilled = false
    private var eatingTimeRemaining: TimeInterval = 0

    private var foodBowlNode: SKSpriteNode?
    private var waterBowlNode: SKSpriteNode?
    private var kibbleProp: SKSpriteNode?
    private var jugProp: SKSpriteNode?
    private var kibbleHome: CGPoint = .zero
    private var jugHome: CGPoint = .zero
    private var bubble: SKNode?

    private var pendingSnoozeClick = false
    private var dragged: Dragged?
    private var dragAnchor: CGPoint = .zero
    private var dragOrigin: CGPoint = .zero

    private static let snoozeDuration: TimeInterval = 15 * 60

    private lazy var bowlFoodEmpty = PetProps.texture("bowl-food-empty")
    private lazy var bowlFoodFull = PetProps.texture("bowl-food-full")
    private lazy var bowlWaterEmpty = PetProps.texture("bowl-water-empty")
    private lazy var bowlWaterFull = PetProps.texture("bowl-water-full")
    private lazy var kibbleTexture = PetProps.texture("kibble")
    private lazy var jugTexture = PetProps.texture("jug")

    init(scene: PetScene) {
        self.scene = scene
    }

    /// Reads live from PetSettings, so a schedule change in the settings
    /// window takes effect without relaunching.
    private var mealTimes: [MealTime] {
        let settings = PetSettings.shared
        return [
            MealTime(key: "breakfast", hour: settings.breakfastHour, minute: settings.breakfastMinute),
            MealTime(key: "lunch", hour: settings.lunchHour, minute: settings.lunchMinute),
            MealTime(key: "dinner", hour: settings.dinnerHour, minute: settings.dinnerMinute),
        ]
    }

    /// Menu bar testing aid. Doesn't touch the real schedule's per-meal
    /// "already happened today" bookkeeping.
    func triggerNow() {
        start(key: "test")
    }

    func wanderTick(now: Date) {
        guard !scene.isGloballySnoozed(now: now) else { return }
        let calendar = Calendar.current
        let defaults = UserDefaults.standard

        for meal in mealTimes {
            if let snoozeUntil = defaults.object(forKey: snoozeKey(meal.key)) as? Date, now < snoozeUntil {
                continue
            }

            guard
                let triggerTime = calendar.date(bySettingHour: meal.hour, minute: meal.minute, second: 0, of: now),
                now >= triggerTime
            else { continue }

            if let last = defaults.object(forKey: lastMealKey(meal.key)) as? Date,
               calendar.isDate(last, inSameDayAs: now) {
                continue // already had this meal today
            }

            start(key: meal.key)
            return // one moment at a time; the rest wait for the next check
        }
    }

    private func snoozeKey(_ meal: String) -> String { scene.defaultsKey("mealSnoozeUntil.\(meal)") }
    private func lastMealKey(_ meal: String) -> String { scene.defaultsKey("lastMealDate.\(meal)") }

    private func start(key: String) {
        guard scene.begin(self) else { return }
        activeMealKey = key
        foodFilled = false
        waterFilled = false
        enter(.waiting)
        spawnProps()
    }

    func update(dt: CGFloat) {
        guard stage == .eating else { return } // .waiting is fully event-driven (drag & drop, or snooze)
        eatingTimeRemaining -= TimeInterval(dt)
        if eatingTimeRemaining <= 0 {
            finish()
        }
    }

    private func enter(_ newStage: Stage) {
        stage = newStage
        scene.resetPose()

        switch newStage {
        case .waiting:
            scene.dog.texture = PetSprites.sit
        case .eating:
            scene.dog.texture = PetSprites.eat
            bubble?.removeFromParent()
            bubble = nil
            // The bowls' job is done once it's actually eating — leaving
            // them sitting there full looked odd under the self-care bubble.
            foodBowlNode?.removeFromParent()
            foodBowlNode = nil
            waterBowlNode?.removeFromParent()
            waterBowlNode = nil
            spawnSelfCareReminder()
        }
    }

    // MARK: - Props

    private func spawnProps() {
        removeProps()
        let base = scene.dog.position
        let width = scene.bodyWidth
        let groundY = scene.groundY

        let foodBowl = makeProp(bowlFoodEmpty, at: CGPoint(x: base.x + width * 0.22, y: groundY + 6), z: 2)
        foodBowlNode = foodBowl

        // "nudges it" — a little rock back and forth, since there's no
        // dedicated nudge animation.
        let nudge = SKAction.repeatForever(SKAction.sequence([
            SKAction.rotate(byAngle: 0.15, duration: 0.15),
            SKAction.rotate(byAngle: -0.3, duration: 0.3),
            SKAction.rotate(byAngle: 0.15, duration: 0.15),
            SKAction.wait(forDuration: 1.2),
        ]))
        foodBowl.run(nudge, withKey: "nudge")

        waterBowlNode = makeProp(bowlWaterEmpty, at: CGPoint(x: base.x + width * 0.38, y: groundY + 6), z: 2)

        kibbleHome = CGPoint(x: base.x - width * 0.46, y: groundY + 14)
        kibbleProp = makeProp(kibbleTexture, at: kibbleHome, z: 5)

        jugHome = CGPoint(x: base.x - width * 0.65, y: groundY + 14)
        jugProp = makeProp(jugTexture, at: jugHome, z: 5)

        let bubble = scene.makeSpeechBubble(text: scene.pet.text("mealBubble"))
        scene.addChild(bubble)
        self.bubble = bubble
    }

    private func makeProp(_ texture: SKTexture, at position: CGPoint, z: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture)
        node.setScale(scene.renderScale)
        node.position = position
        node.zPosition = z
        scene.addChild(node)
        return node
    }

    /// The whole point of a meal reminder is that the pet nudges *you* to
    /// take care of yourself — so once it's fed, turn the reminder around.
    private func spawnSelfCareReminder() {
        let reminder = scene.makeSpeechBubble(text: scene.pet.text("selfCareBubble"))
        scene.addChild(reminder)
        let hold = SKAction.wait(forDuration: 2.5)
        let fade = SKAction.fadeOut(withDuration: 0.6)
        reminder.run(SKAction.sequence([hold, fade, SKAction.removeFromParent()]))
    }

    private func removeProps() {
        for node in [foodBowlNode, waterBowlNode, kibbleProp, jugProp] {
            node?.removeFromParent()
        }
        foodBowlNode = nil
        waterBowlNode = nil
        kibbleProp = nil
        jugProp = nil
        bubble?.removeFromParent()
        bubble = nil
    }

    // MARK: - Mouse

    private var isWaiting: Bool { scene.isActive(self) && stage == .waiting }

    func isInteractive(at point: CGPoint) -> Bool {
        guard isWaiting else { return false }
        if let bubble, scene.isOverNode(bubble, point, padding: 6) { return true }
        if let kibbleProp, scene.isOverNode(kibbleProp, point, padding: 10) { return true }
        if let jugProp, scene.isOverNode(jugProp, point, padding: 10) { return true }
        return false
    }

    func mouseDown(at point: CGPoint, event: NSEvent) -> Bool {
        guard isWaiting else { return false }
        if let bubble, scene.isOverNode(bubble, point, padding: 6) {
            pendingSnoozeClick = true
            return true
        }
        if let kibbleProp, scene.isOverNode(kibbleProp, point, padding: 10) {
            beginDrag(.kibble, node: kibbleProp, at: point)
            return true
        }
        if let jugProp, scene.isOverNode(jugProp, point, padding: 10) {
            beginDrag(.jug, node: jugProp, at: point)
            return true
        }
        return false
    }

    private func beginDrag(_ kind: Dragged, node: SKNode, at point: CGPoint) {
        dragged = kind
        dragAnchor = point
        dragOrigin = node.position
    }

    func mouseDragged(to point: CGPoint, event: NSEvent) {
        guard let dragged else { return }
        let position = CGPoint(x: dragOrigin.x + point.x - dragAnchor.x, y: dragOrigin.y + point.y - dragAnchor.y)
        switch dragged {
        case .kibble: kibbleProp?.position = position
        case .jug: jugProp?.position = position
        }
    }

    func mouseUp(at point: CGPoint, event: NSEvent) {
        if pendingSnoozeClick {
            pendingSnoozeClick = false
            snooze()
            return
        }
        guard let kind = dragged else { return }
        dragged = nil

        switch kind {
        case .kibble:
            guard let kibbleProp else { return }
            if let foodBowlNode, isNear(kibbleProp.position, foodBowlNode.position) {
                fillFood()
            } else {
                returnHome(kibbleProp, home: kibbleHome)
            }
        case .jug:
            guard let jugProp else { return }
            if let waterBowlNode, isNear(jugProp.position, waterBowlNode.position) {
                fillWater()
            } else {
                returnHome(jugProp, home: jugHome)
            }
        }
    }

    private func isNear(_ a: CGPoint, _ b: CGPoint) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < 24
    }

    private func returnHome(_ node: SKSpriteNode, home: CGPoint) {
        let snap = SKAction.move(to: home, duration: 0.2)
        snap.timingMode = .easeOut
        node.run(snap)
    }

    private func fillFood() {
        guard !foodFilled else { return }
        foodFilled = true
        foodBowlNode?.removeAction(forKey: "nudge")
        foodBowlNode?.zRotation = 0
        foodBowlNode?.texture = bowlFoodFull
        kibbleProp?.removeFromParent()
        kibbleProp = nil
        startEatingIfFull()
    }

    private func fillWater() {
        guard !waterFilled else { return }
        waterFilled = true
        waterBowlNode?.texture = bowlWaterFull
        jugProp?.removeFromParent()
        jugProp = nil
        startEatingIfFull()
    }

    private func startEatingIfFull() {
        guard foodFilled && waterFilled else { return }
        if let key = activeMealKey {
            UserDefaults.standard.set(Date(), forKey: lastMealKey(key))
        }
        eatingTimeRemaining = 2.5
        enter(.eating)
    }

    private func snooze() {
        if let key = activeMealKey {
            UserDefaults.standard.set(Date().addingTimeInterval(Self.snoozeDuration), forKey: snoozeKey(key))
        }
        finish()
    }

    private func finish() {
        activeMealKey = nil
        foodFilled = false
        waterFilled = false
        removeProps()
        scene.endMoment()
    }
}
