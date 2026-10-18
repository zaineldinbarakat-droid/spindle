import SwiftUI
import SpindleSync

struct SettingsView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var notch: NotchViewModel
    @EnvironmentObject private var timer: PomodoroTimer
    @EnvironmentObject private var desktop: DesktopController

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    /// Counts drags of the size slider, so a preview ending late can't cut a new one short.
    @State private var sizePreview = 0
    @AppStorage(ArtworkStyle.storageKey) private var artworkStyle: ArtworkStyle = .vinyl
    @AppStorage(Defaults.Key.fullScreenTimer.rawValue) private var fullScreenTimer = true

    var body: some View {
        Form {
            Section {
                Picker("Look", selection: $notch.style) {
                    ForEach(NotchViewModel.Style.allCases) { style in
                        Text(style.title).tag(style)
                            .disabled(style == .liquidGlass && !NotchViewModel.Style.isGlassAvailable)
                    }
                }
                .pickerStyle(.segmented)
                Text(lookDescription)
                    .font(.caption).foregroundStyle(.secondary)
                if notch.style == .songColor {
                    Toggle("Let the album color reach into the notch itself", isOn: $notch.tintNotch)
                }
                if notch.style == .liquidGlass {
                    LabeledContent("Clarity") {
                        HStack {
                            Text("Frosted").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $notch.glassClarity, in: 0...1)
                            Text("Clear").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Tint the glass with the album's color", isOn: $notch.glassTinted)
                }
                Toggle("Glow behind the album cover", isOn: $notch.coverGlow)
                    .help("Off: around the cover is just the notch's own look, with no colour rising from behind it.")
                LabeledContent("Size") {
                    HStack {
                        Text("Smaller").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $notch.panelScale, in: NotchViewModel.panelScaleRange, step: 0.01,
                               onEditingChanged: previewSize)
                        Text("Larger").font(.caption).foregroundStyle(.secondary)
                        Text("\(Int((notch.panelScale * 100).rounded())) %")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("How big the panel opens — the notch opens while you drag, so you can see it. The closed pill always fits your Mac's notch.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Reset") {
                        withAnimation { notch.panelScale = NotchViewModel.defaultPanelScale }
                    }
                    .disabled(abs(notch.panelScale - NotchViewModel.defaultPanelScale) < 0.005)
                }
                Picker("When closed, show", selection: $notch.collapsedShowsCover) {
                    Text("Album Cover").tag(true)
                    Text("Spinning Record").tag(false)
                }
                .pickerStyle(.segmented)
                Picker("When open, show the song as", selection: $artworkStyle) {
                    ForEach(ArtworkStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Open when the cursor reaches the notch", isOn: $notch.openOnHover)
            } header: {
                Text("Notch")
            }

            Section {
                Toggle("Show the playing indicator", isOn: $notch.showVisualizer)
                if notch.showVisualizer {
                    HStack {
                        Spacer()
                        // Live preview on a slice of black notch, always "playing".
                        RadianceView(isPlaying: true,
                                     color: notch.indicatorColor(accent: player.accent),
                                     style: notch.indicatorStyle,
                                     brightness: notch.indicatorBrightness,
                                     glow: notch.indicatorGlow)
                            .scaleEffect(1.6)
                            .frame(width: 120, height: 44)
                            .background(Capsule().fill(Color.black))
                        Spacer()
                    }
                    Picker("Style", selection: $notch.indicatorStyle) {
                        ForEach(NotchViewModel.IndicatorStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Color", selection: $notch.indicatorColorMode) {
                        ForEach(NotchViewModel.IndicatorColor.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if notch.indicatorColorMode == .custom {
                        ColorPicker("Custom color", selection: $notch.indicatorCustomColor, supportsOpacity: false)
                    }
                    LabeledContent("Brightness") {
                        HStack {
                            Text("Soft").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $notch.indicatorBrightness, in: 0.3...1)
                            Text("Bright").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Glow") {
                        HStack {
                            Text("None").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $notch.indicatorGlow, in: 0...1)
                            Text("Strong").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Playing indicator")
            } footer: {
                Text("The little glow on the right of the closed notch while music plays.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Picker("Desktop wallpaper", selection: Binding(
                    get: { desktop.isBackdropVisible },
                    set: { desktop.setBackdrop(visible: $0) }
                )) {
                    Text("My wallpaper").tag(false)
                    Text("Retro turntable").tag(true)
                }
                .pickerStyle(.segmented)
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
                Stepper("Lock in: \(timer.focusMinutes) min", value: $timer.focusMinutes, in: 1...120)
                Stepper("Short break: \(timer.shortBreakMinutes) min", value: $timer.shortBreakMinutes, in: 1...60)
                Stepper("Long break: \(timer.longBreakMinutes) min", value: $timer.longBreakMinutes, in: 1...90)
                Stepper("Long break every \(timer.sessionsBeforeLongBreak) sessions",
                        value: $timer.sessionsBeforeLongBreak, in: 2...8)
                Toggle("Start the next phase automatically", isOn: $timer.autoStartNextPhase)
                Toggle("Drop the notch open when a phase ends", isOn: $timer.peekNotchOnPhaseEnd)
                Toggle("Pause music during breaks", isOn: $timer.pauseMusicOnBreak)
                Toggle("Start music when you lock in", isOn: $timer.resumeMusicOnFocus)
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
                Toggle("Show the focus timer on the full-screen turntable", isOn: $fullScreenTimer)
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
        .frame(width: 480, height: 700)
    }

    /// Opens the notch while the size slider is held, and closes it a moment after
    /// letting go (unless the cursor has gone up to it).
    private func previewSize(_ editing: Bool) {
        sizePreview += 1
        if editing {
            notch.isPreviewingSize = true
            notch.expand()
            return
        }
        let preview = sizePreview
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard preview == sizePreview else { return }
            notch.isPreviewingSize = false
            if !notch.metrics.liveZone().contains(NSEvent.mouseLocation) { notch.collapse() }
        }
    }

    private var lookDescription: String {
        switch notch.style {
        case .black: return "Pure black, one with the hardware notch."
        case .songColor: return "The open panel takes on the album's color; the notch itself stays black unless you allow it below."
        case .liquidGlass: return "macOS's Liquid Glass. Clear is see-through glass that bends the light at its edges; Frosted blurs what's behind it."
        }
    }
}
