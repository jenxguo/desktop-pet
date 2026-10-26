import SwiftUI

@main
struct DesktopPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = PetSettings.shared
    // Plain @State, not a read off AppDelegate — AppDelegate's own
    // @Published didn't reliably refresh MenuBarExtra's label when the
    // window's shown/hidden from outside the view hierarchy.
    @State private var isAsleep = false

    private let pet = PetConfig.current

    var body: some Scene {
        MenuBarExtra(pet.name, systemImage: pet.menuBarSymbol) {
            MenuHeader(greeting: pet.text("greeting"))

            Divider()

            // One item per moment that's in this build and switched on.
            ForEach(menuMoments, id: \.id) { moment in
                Button(pet.text(moment.titleKey)) {
                    appDelegate.trigger(momentID: moment.id)
                }
            }

            Divider()

            Button(pet.text("menuSnooze")) {
                appDelegate.snoozeEverything()
            }

            Button(isAsleep ? pet.text("menuWake") : pet.text("menuSleep")) {
                isAsleep.toggle()
                appDelegate.setAsleep(isAsleep)
            }

            if pet.isIncluded(PhotoDropMoment.id) {
                Button(pet.text("menuPhotosFolder")) {
                    appDelegate.openPhotosFolder()
                }
            }

            Button(pet.text("menuSettings")) {
                appDelegate.showSettings()
            }
            .keyboardShortcut(",")

            Divider()

            Button(pet.text("menuQuit")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var menuMoments: [(id: String, titleKey: String)] {
        PetMoments.included.compactMap { moment in
            guard let key = moment.menuTitleKey, settings.isEnabled(moment.id) else { return nil }
            return (moment.id, key)
        }
    }
}

/// Portrait + greeting at the top of the menu.
private struct MenuHeader: View {
    let greeting: String

    var body: some View {
        HStack(spacing: 8) {
            if let portrait = PetSprites.portrait {
                Image(nsImage: portrait)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            }
            Text(greeting)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.vertical, 2)
    }
}
