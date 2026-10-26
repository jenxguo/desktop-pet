import AppKit
import SpriteKit

/// Borderless, transparent panel that covers the main display and floats
/// above every other window. Mouse events pass through to whatever's
/// underneath except when the cursor is over the pet or a prop — a
/// timer polls the cursor ~20x/sec and toggles `ignoresMouseEvents` from a
/// hit test.
final class OverlayWindow: NSPanel {
    let scene: PetScene
    private var cursorPollTimer: Timer?

    init() {
        let screenFrame = NSScreen.main?.frame ?? .zero

        let skView = SKView(frame: NSRect(origin: .zero, size: screenFrame.size))
        let scene = PetScene(size: screenFrame.size)
        self.scene = scene

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        #if DEBUG
        skView.showsFPS = false
        skView.showsNodeCount = false
        #endif

        skView.presentScene(scene)
        contentView = skView

        startCursorPolling()
    }

    deinit {
        cursorPollTimer?.invalidate()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// ~20Hz: the window only ever sees mouse events it stops ignoring, so we
    /// have to decide *before* a click arrives whether the cursor is over
    /// something interactive. `NSEvent.mouseLocation` works globally and
    /// doesn't require us to already be accepting events.
    private func startCursorPolling() {
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.pollCursor()
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorPollTimer = timer
    }

    private func pollCursor() {
        let global = NSEvent.mouseLocation
        let local = CGPoint(x: global.x - frame.origin.x, y: global.y - frame.origin.y)

        if scene.isPointerCaptured {
            // Mid click-or-drag: never flip back to ignoring, or we'd lose
            // the matching mouseDragged/mouseUp events.
            ignoresMouseEvents = false
        } else {
            ignoresMouseEvents = !scene.isInteractive(at: local)
        }
    }
}
