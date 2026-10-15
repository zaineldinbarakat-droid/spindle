import SwiftUI
import SpindleSync

struct SettingsView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var notch: NotchViewModel
    @EnvironmentObject private var timer: PomodoroTimer
    @EnvironmentObject private var desktop: DesktopController

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(ArtworkStyle.storageKey) private var artworkStyle: ArtworkStyle = .vinyl

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Show the song as", selection: $artworkStyle) {
                    ForEach(ArtworkStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Notch look", selection: $notch.style) {
                    ForEach(NotchViewModel.Style.allCases) { style in
                        Text(style.title).tag(style)
                            .disabled(style == .liquidGlass && !NotchViewModel.Style.isGlassAvailable)
                    }
                }
                .pickerStyle(.segmented)
                if notch.style == .songColor {
                    Toggle("Let the album color reach into the notch", isOn: $notch.tintNotch)
                }
                Picker("Collapsed notch shows", selection: $notch.collapsedShowsCover) {
                    Text("Album Cover").tag(true)
                    Text("Spinning Record").tag(false)
                }
                .pickerStyle(.segmented)

                Picker("Desktop wallpaper", selection: Binding(
                    get: { desktop.isBackdropVisible },
                    set: { desktop.setBackdrop(visible: $0) }
                )) {
                    Text("My wallpaper").tag(false)
                    Text("Retro turntable").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section("Behaviour") {
                Toggle("Open when the cursor reaches the notch", isOn: $notch.openOnHover)
                Toggle("Show the glowing playing indicator in the collapsed notch", isOn: $notch.showVisualizer)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        // Re-read: registration can fail (e.g. quarantined app).
                        if !LaunchAtLogin.set(enabled) {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            }

            Section("Music source") {
                Picker("Follow", selection: Binding(
                    get: { player.pinnedProvider },
                    set: { player.pinnedProvider = $0 }
                )) {
                    Text("Whatever is playing").tag(ProviderID?.none)
                    ForEach(ProviderID.allCases) { provider in
                        Text(provider.displayName).tag(ProviderID?.some(provider))
                    }
                }
                .pickerStyle(.radioGroup)

                if !player.deniedProviders.isEmpty {
                    let names = player.deniedProviders.map(\.displayName).sorted().joined(separator: ", ")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Spindle can't control \(names).")
                                .font(.callout)
                            Button("Open Automation Settings") {
                                player.openAutomationSettings()
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }

            Section("Focus timer") {
                Picker("Preset", selection: Binding(
                    get: { timer.currentPreset?.name ?? "custom" },
                    set: { name in
                        if let preset = PomodoroTimer.Preset.all.first(where: { $0.name == name }) {
                            timer.apply(preset)
                        }
                    }
                )) {
                    ForEach(PomodoroTimer.Preset.all) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                    if timer.currentPreset == nil {
                        Text("Custom").tag("custom")
                    }
                }
                Stepper("Focus: \(timer.focusMinutes) min", value: $timer.focusMinutes, in: 1...120)
                Stepper("Short break: \(timer.shortBreakMinutes) min", value: $timer.shortBreakMinutes, in: 1...60)
                Stepper("Long break: \(timer.longBreakMinutes) min", value: $timer.longBreakMinutes, in: 1...90)
                Stepper("Long break every \(timer.sessionsBeforeLongBreak) sessions",
                        value: $timer.sessionsBeforeLongBreak, in: 2...8)
                Toggle("Start the next phase automatically", isOn: $timer.autoStartNextPhase)
                Toggle("Drop the notch open when a phase ends", isOn: $timer.peekNotchOnPhaseEnd)
                Toggle("Pause music during breaks", isOn: $timer.pauseMusicOnBreak)
                Toggle("Start music when focus begins", isOn: $timer.resumeMusicOnFocus)
            }

            Section("Desktop") {
                ForEach(DesktopWidgetKind.allCases) { kind in
                    Toggle("\(kind.title) widget", isOn: Binding(
                        get: { desktop.isWidgetVisible(kind) },
                        set: { $0 ? desktop.showWidget(kind) : desktop.hideWidget(kind) }
                    ))
                }
                Button(desktop.isFullScreenVisible ? "Exit Full-Screen Turntable" : "Open Full-Screen Turntable") {
                    desktop.toggleFullScreen()
                }
                Text("Drag a widget by its wooden edge to move it; right-click to remove it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                UpdatesRow(updater: AppEnvironment.shared.updater)
            }

            Section {
                Text("Spindle reads and controls Music and Spotify through Apple Events. "
                     + "It never connects to a streaming service itself, so nothing leaves this Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
    }
}
