# Adding a moment

A *moment* is one self-care interaction: the pet stops wandering, does one thing, and goes back to wandering. The four that ship are in `Sources/DesktopPet/Moments/`:

| File | Moment |
| --- | --- |
| `PhotoDropMoment.swift` | Daily photo in a polaroid |
| `MealMoment.swift` | Drag kibble and water to the bowls at mealtimes |
| `FetchMoment.swift` | Fling a ball after N minutes of screen time |
| `TidyMoment.swift` | Carry screenshots into a folder |

Each is self-contained: its own state, props, timers and mouse handling. Removing one is one line. Adding one is one file plus one line.

## The shape of a moment

```swift
final class StretchMoment: PetMoment {
    static let id = "stretch"                    // pet.json → features.stretch, Settings toggle
    static let settingsTitleKey = "settingsStretch"
    static let menuTitleKey: String? = "menuStretch"
    static let requiredProps: [String] = []      // files in Pet/props/ this needs

    private unowned let scene: PetScene
    private var timeLeft: TimeInterval = 0

    init(scene: PetScene) { self.scene = scene }

    /// Menu bar item.
    func triggerNow() {
        guard scene.begin(self) else { return }  // refuses if another moment is running
        scene.dog.texture = PetSprites.playBow   // the closest thing to a stretch
        let bubble = scene.makeSpeechBubble(text: scene.pet.text("stretchBubble"))
        scene.addChild(bubble)
        bubble.run(.sequence([.wait(forDuration: 4), .fadeOut(withDuration: 0.5), .removeFromParent()]))
        timeLeft = 4
    }

    /// Every ~5 s while wandering, if switched on in Settings.
    func wanderTick(now: Date) {
        let minute = Calendar.current.component(.minute, from: now)
        if minute == 0 && !scene.isGloballySnoozed(now: now) { triggerNow() }  // on the hour
    }

    /// Every frame while active.
    func update(dt: CGFloat) {
        timeLeft -= TimeInterval(dt)
        if timeLeft <= 0 { scene.endMoment() }
    }
}
```

Then:

1. Add `StretchMoment.self` to `PetMoments.all` in `Moments/PetMoment.swift`. Its position sets the menu order.
2. Add the strings to `defaultsJSON` in `Pet/PetConfig.swift`:

   ```json
   "menuStretch": "Stretch with {name}",
   "settingsStretch": "Hourly stretch",
   "stretchBubble": "stretch time!"
   ```

That's it. You get a menu item, a Settings toggle, and a `features.stretch` switch in `pet.json`.

(This example fires every 5 seconds for the whole minute after the hour. A real one should remember the last time it ran, like `PhotoDropMoment` does with `lastPhotoDropDate`.)

## What the scene gives you

`PetScene` (in `Scene/PetScene.swift`) owns the pet and the wander behavior. A moment uses:

| | |
| --- | --- |
| `scene.dog` | The pet's sprite node. `dog.position` is at its feet. |
| `scene.mouthAnchor` | Child node at the mouth. `addChild` a prop to carry it (scale it by `1 / scene.renderScale`). |
| `scene.begin(self)` / `scene.endMoment()` | Take over from wandering / give control back |
| `scene.isActive(self)`, `scene.isWandering` | Who's in charge right now |
| `scene.resetPose()` | Stop animations, reset scale, rotation and alpha. Call it before a new pose. |
| `scene.loop(frames, timePerFrame:)` | Play an animation on repeat |
| `scene.runAlongGround(toward: x, dt:)` | Run toward an x position. Returns true on arrival. |
| `scene.travel(toward: point, dt:, speed:)` | Move anywhere on screen (tidy uses this) |
| `scene.direction`, `scene.faceDirection()` | 1 = right, -1 = left |
| `scene.groundY`, `scene.bodyWidth`, `scene.headTopY` | Layout helpers, so props fit any size of pet |
| `scene.makeSpeechBubble(text:)` | A themed bubble above the head (you add it to the scene) |
| `scene.showNotification(text)` | A quick bubble that pops up and fades on its own, e.g. "nothing to tidy!" |
| `scene.isOverNode(_:_:padding:)`, `scene.isOverDog(_:)` | Hit testing |
| `scene.isGloballySnoozed(now:)` | Respect "Snooze everything" |
| `scene.defaultsKey("name")` | Namespaced UserDefaults key for your own bookkeeping |
| `scene.pet` | The loaded `pet.json`: `pet.text("key")`, `pet.theme`, `pet.movement`… |

## Mouse

The overlay window is click-through everywhere except where something says it's interactive. Implement:

- `isInteractive(at:)`: true over the things you want clickable (polaroid, bubble, props).
- `mouseDown(at:event:)`: return `true` to take the click. The drag and mouse-up then come to you.
- `mouseDragged(to:event:)` and `mouseUp(at:event:)`.

`MealMoment` (drag props onto targets) and `FetchMoment` (fling with velocity) are good examples.

## New art

A new pose: load it in `Pet/PetSprites.swift` with `optional("stretch", fallback: stand)` so pets without it still work, and add it to the frames table in `docs/MAKE_YOUR_OWN_PET.md`. A new prop: `PetProps.texture("yoga-mat")`, listed in `requiredProps` so the app can warn at launch when it's missing.
