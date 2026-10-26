import AppKit
import SwiftUI

/// Settings: Schedule, Moments toggles, the photo folder, and where
/// screenshots go. Sections for moments that `pet.json` leaves out are hidden.
struct SettingsView: View {
    @ObservedObject var settings: PetSettings
    @State private var photoThumbnails: [NSImage] = []

    private let pet = PetConfig.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if hasSchedule {
                    scheduleSection
                }
                momentsSection
                if pet.isIncluded(PhotoDropMoment.id) {
                    photosSection
                }
                if pet.isIncluded(TidyMoment.id) {
                    screenshotsSection
                }
            }
            .padding(24)
        }
        .frame(width: 420, height: 560)
        .background(pet.theme.backgroundColor)
        .tint(pet.theme.accentColor)
        .onAppear(perform: loadThumbnails)
    }

    private var hasSchedule: Bool {
        [MealMoment.id, PhotoDropMoment.id, FetchMoment.id].contains(where: pet.isIncluded)
    }

    private var scheduleSection: some View {
        SettingsSection(title: "Schedule", pet: pet) {
            if pet.isIncluded(MealMoment.id) {
                timeRow("Breakfast", hour: $settings.breakfastHour, minute: $settings.breakfastMinute)
                timeRow("Lunch", hour: $settings.lunchHour, minute: $settings.lunchMinute)
                timeRow("Dinner", hour: $settings.dinnerHour, minute: $settings.dinnerMinute)
            }
            if pet.isIncluded(PhotoDropMoment.id) {
                timeRow("Daily photo", hour: $settings.photoDropHour, minute: $settings.photoDropMinute)
            }
            if pet.isIncluded(FetchMoment.id) {
                HStack {
                    Text("Break every")
                    Stepper(value: $settings.breakIntervalMinutes, in: 5...180, step: 5) {
                        Text("\(settings.breakIntervalMinutes) min of active use")
                    }
                }
            }
        }
    }

    private var momentToggles: [(id: String, titleKey: String)] {
        PetMoments.included.map { ($0.id, $0.settingsTitleKey) }
    }

    private var momentsSection: some View {
        SettingsSection(title: "Moments", pet: pet) {
            ForEach(momentToggles, id: \.id) { toggle in
                Toggle(pet.text(toggle.titleKey), isOn: Binding(
                    get: { settings.isEnabled(toggle.id) },
                    set: { settings.setEnabled(toggle.id, $0) }
                ))
            }
            Toggle("Open at login", isOn: $settings.openAtLoginEnabled)
        }
    }

    private var photosSection: some View {
        SettingsSection(title: pet.text("settingsPhotosSection"), pet: pet) {
            if photoThumbnails.isEmpty {
                Text("No photos yet — add some to the folder below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(photoThumbnails.indices, id: \.self) { index in
                        Image(nsImage: photoThumbnails[index])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            Button(pet.text("menuPhotosFolder")) {
                PhotoLibrary.ensureFolderExists()
                NSWorkspace.shared.open(PhotoLibrary.photosFolder)
            }
        }
    }

    private var screenshotsSection: some View {
        SettingsSection(title: "Screenshots go to", pet: pet) {
            Text(settings.screenshotsDestinationPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button("Change folder…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.directoryURL = settings.screenshotsDestination
                if panel.runModal() == .OK, let url = panel.url {
                    settings.screenshotsDestinationPath = url.path
                }
            }
        }
    }

    private func timeRow(_ label: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
            DatePicker(
                "",
                selection: Binding(
                    get: { Self.date(hour: hour.wrappedValue, minute: minute.wrappedValue) },
                    set: { newValue in
                        let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        hour.wrappedValue = components.hour ?? hour.wrappedValue
                        minute.wrappedValue = components.minute ?? minute.wrappedValue
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func loadThumbnails() {
        PhotoLibrary.ensureFolderExists()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: PhotoLibrary.photosFolder, includingPropertiesForKeys: nil
        )) ?? []
        photoThumbnails = contents.compactMap { NSImage(contentsOf: $0) }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let pet: PetConfig
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(pet.theme.inkColor)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(14)
            .background(pet.theme.cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(pet.theme.borderColor, lineWidth: 1))
        }
    }
}

/// A normal (non-overlay) window hosting `SettingsView`, like
/// `PolaroidCardWindow` — the overlay panel is nonactivating and
/// click-through by design, so real UI like this gets its own window.
final class SettingsWindow: NSWindow {
    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = PetConfig.current.text("settingsTitle")
        isReleasedWhenClosed = false
        level = .floating
        contentView = NSHostingView(rootView: SettingsView(settings: .shared))
        center()
    }
}
