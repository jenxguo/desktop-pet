import AppKit
import SpriteKit

/// A self-care "moment": the pet leaves its idle wander, does one thing,
/// and goes back to wandering once you respond or ignore it long enough.
///
/// To add one, write a `final class` conforming to this, then add it to
/// `PetMoments.all` below. It gets a menu bar item, a Settings toggle and a
/// `pet.json` `features` switch for free. docs/ADDING_A_MOMENT.md walks
/// through an example.
///
/// Only one moment runs at a time: call `scene.begin(self)` to start (it
/// refuses if another one is active) and `scene.endMoment()` when done.
protocol PetMoment: AnyObject {
    /// Stable id for `pet.json` → `features`, and the Settings toggle.
    static var id: String { get }
    /// `pet.json` `text` key for the Settings → Moments toggle label.
    static var settingsTitleKey: String { get }
    /// `pet.json` `text` key for the menu bar item that starts it right
    /// now, or nil for no menu item.
    static var menuTitleKey: String? { get }
    /// Files in `Pet/props/` (without .png) this moment loads. Checked at
    /// launch so a missing one is reported right away, not at 6pm.
    static var requiredProps: [String] { get }

    init(scene: PetScene)

    /// The menu bar item. Expected to ignore the request if another moment
    /// is already running.
    func triggerNow()

    /// Polled every ~5s while the pet is wandering and this moment is
    /// switched on in Settings — the place to check a schedule and call
    /// `scene.begin(self)`.
    func wanderTick(now: Date)

    /// Every frame while this is the active moment.
    func update(dt: CGFloat)

    /// Whether the overlay should catch the mouse at `point` (it's
    /// click-through everywhere else). Can be true outside the active
    /// moment, e.g. a toast that outlives it.
    func isInteractive(at point: CGPoint) -> Bool

    /// Return true to take this click; the drag and mouse-up then come here too.
    func mouseDown(at point: CGPoint, event: NSEvent) -> Bool
    func mouseDragged(to point: CGPoint, event: NSEvent)
    func mouseUp(at point: CGPoint, event: NSEvent)
}

extension PetMoment {
    static var id: String { String(describing: self) }
    static var menuTitleKey: String? { nil }
    static var requiredProps: [String] { [] }
    func wanderTick(now: Date) {}
    func update(dt: CGFloat) {}
    func isInteractive(at point: CGPoint) -> Bool { false }
    func mouseDown(at point: CGPoint, event: NSEvent) -> Bool { false }
    func mouseDragged(to point: CGPoint, event: NSEvent) {}
    func mouseUp(at point: CGPoint, event: NSEvent) {}
}

enum PetMoments {
    /// Every moment the app knows about, in menu order. Earlier entries also
    /// get first pick of clicks.
    static let all: [PetMoment.Type] = [
        PhotoDropMoment.self,
        MealMoment.self,
        FetchMoment.self,
        TidyMoment.self,
    ]

    /// The ones `pet.json` → `features` doesn't switch off.
    static var included: [PetMoment.Type] {
        all.filter { PetConfig.current.isIncluded($0.id) }
    }
}
