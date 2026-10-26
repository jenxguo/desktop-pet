import AppKit
import SwiftUI

/// The daily photo, opened big: just the photo and one "Thanks, <pet>"
/// button — no caption, date or favorites.
struct PolaroidCardView: View {
    let image: NSImage
    let onDismiss: () -> Void

    private let pet = PetConfig.current

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 300, maxHeight: 300)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(pet.theme.inkColor, lineWidth: 2)
                )

            Button(pet.text("thanksButton"), action: onDismiss)
                .buttonStyle(.borderedProminent)
                .tint(pet.theme.accentColor)
                .controlSize(.large)
                .frame(minHeight: 44)
        }
        .padding(28)
        .frame(width: 360)
        .background(pet.theme.backgroundColor)
    }
}

/// Floating panel that hosts `PolaroidCardView`. Not an `NSPanel`/nonactivating
/// window like the overlay — this one is a normal small dialog the person
/// actually interacts with, so it can become key and take focus.
final class PolaroidCardWindow: NSWindow, NSWindowDelegate {
    private var onDismiss: (() -> Void)?

    convenience init(image: NSImage, onDismiss: @escaping () -> Void) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.onDismiss = onDismiss
        title = PetConfig.current.name
        isReleasedWhenClosed = false
        level = .floating
        delegate = self

        let view = PolaroidCardView(image: image) { [weak self] in
            self?.close()
        }
        contentView = NSHostingView(rootView: view)
        center()
    }

    func windowWillClose(_ notification: Notification) {
        onDismiss?()
        onDismiss = nil
    }
}
