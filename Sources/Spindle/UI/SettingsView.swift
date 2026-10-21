import SwiftUI
import SpindleSync

/// Settings opens on a short list of categories; each opens its own page of options,
/// with a back button, so there's never more on screen than the one thing being edited.
struct SettingsView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var notch: NotchViewModel
    @EnvironmentObject private var timer: PomodoroTimer
    @EnvironmentObject private var desktop: DesktopController

    @State private var page: SettingsPage?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    /// Counts drags of the size slider, so a preview ending late can't cut a new one short.
    @State private var sizePreview = 0
    @AppStorage(ArtworkStyle.storageKey) private var artworkStyle: ArtworkStyle = .vinyl
    @AppStorage(Defaults.Key.fullScreenTimer.rawValue) private var fullScreenTimer = true
    @AppStorage(Defaults.Key.showsSpindlePin.rawValue) private var showsPin = true
    @AppStorage(Defaults.Key.recordLabelSize.rawValue) private var labelSize = Double(Theme.Record.labelFraction)

    var body: some View {
        ZStack {
            if let page {
                detail(page)
                    .transition(.move(edge: .trailing))
            } else {
                home
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: page)
        .clipped()
        .frame(width: 540, height: 720)
    }

    // MARK: - Home

    private var home: some View {
        Form {
            ForEach(SettingsPage.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.pages) { page in
                        CategoryRow(page: page, summary: summary(for: page)) { self.page = page }
                    }
                }
            }

            Section {
                Text("Spindle reads and controls Music and Spotify through Apple Events. "
                     + "It never connects to a streaming service itself, so nothing leaves this Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// The current state of a category, in a few words, under its name.
    private func summary(for page: SettingsPage) -> String {
        switch page {
        case .notch:
            return "\(notch.style.title) · " + (notch.openOnHover ? "opens on hover" : "opens on click")
        case .panel:
            return "\(notch.currentPreset?.name ?? "Custom") · \(notch.motion.title) motion"
        case .record:
            guard artworkStyle == .vinyl else { return "Album cover" }
            return "Vinyl record · art \(Int((labelSize * 100).rounded())) %" + (showsPin ? "" : " · no pin")
        case .waves:
            guard notch.showVisualizer || notch.panelWaves else { return "Off" }
            return "\(notch.indicatorStyle.title) · " + (notch.liveWaves ? "react to the music" : "steady rhythm")
        case .music:
            return player.pinnedProvider?.displayName ?? "Whatever is playing"
        case .focus:
            return "\(timer.focusMinutes) min lock-in · \(timer.shortBreakMinutes) min breaks"
        case .desktop:
            let widgets = DesktopWidgetKind.allCases.filter { desktop.isWidgetVisible($0) }.count
            let wallpaper = desktop.isBackdropVisible ? "Turntable wallpaper" : "Your wallpaper"
            return wallpaper + " · " + (widgets == 0 ? "no widgets" : widgets == 1 ? "1 widget" : "\(widgets) widgets")
        case .general:
            return launchAtLogin ? "Launches at login" : "Doesn't launch at login"
        case .updates:
            return "Version \(AppEnvironment.shared.updater.currentVersion)"
        }
    }

    // MARK: - A category's page

    private func detail(_ page: SettingsPage) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Text(page.title).font(.headline)
                HStack {
                    Button { self.page = nil } label: {
                        Label("Settings", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("Back to all settings (Esc)")
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Form {
                content(for: page)
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func content(for page: SettingsPage) -> some View {
        switch page {
        case .notch: notchSection
        case .panel: PanelSettings(preview: previewPanel, previewBriefly: previewBriefly)
        case .record: recordSection
        case .waves: wavesSection
        case .music: musicSection
        case .focus: focusSection
        case .desktop: desktopSection
        case .general: generalSection
        case .updates:
            Section { UpdatesRow(updater: AppEnvironment.shared.updater) }
        }
    }

    // MARK: - Sections

    private var notchSection: some View {
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
            Picker("When closed, show", selection: $notch.collapsedShowsCover) {
                Text("Album Cover").tag(true)
                Text("Spinning Record").tag(false)
            }
            .pickerStyle(.segmented)
            Toggle("Open when the cursor reaches the notch", isOn: $notch.openOnHover)
        }
    }

    private var recordSection: some View {
        Section {
            HStack {
                Spacer()
                // The record as it looks right now, pin and all.
                VinylView(artwork: player.artwork, accent: player.accent, isSpinning: player.snapshot.isPlaying)
                    .frame(width: 132, height: 132)
                    .opacity(artworkStyle == .vinyl ? 1 : 0.35)
                Spacer()
            }
            .padding(.vertical, 6)
            Picker("When open, show the song as", selection: $artworkStyle) {
                ForEach(ArtworkStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            LabeledContent("Album art") {
                HStack {
                    Text("Smaller").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $labelSize, in: Theme.Record.labelFractionRange)
                    Text("Larger").font(.caption).foregroundStyle(.secondary)
                    Text("\(Int((labelSize * 100).rounded())) %")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .disabled(artworkStyle != .vinyl)
            Toggle("Spindle pin through the middle of the record", isOn: $showsPin)
                .disabled(artworkStyle != .vinyl)
        } footer: {
            Text("Album art sets how much of the record the cover's label fills; the grooves and the tonearm make room for it. Turn the pin off for nothing over the art. Both apply to every record: the notch, the widgets and the turntable wallpaper.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var wavesSection: some View {
        Section {
            Toggle("Show the playing indicator in the closed notch", isOn: $notch.showVisualizer)
            Toggle("Show the waves in the open panel, beside the controls", isOn: $notch.panelWaves)
            Toggle("React to the music", isOn: $notch.liveWaves)
            if notch.liveWaves {
                LabeledContent("Expression") {
                    HStack {
                        Text("Calm").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $notch.waveIntensity, in: 0...1)
                        Text("Wild").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("The waves move with the song's actual sound — bass on the left, treble on the right. Loud hits make them jump and glow, high notes make the right side leap; Expression sets how dramatic it gets. macOS asks once to let Spindle hear the audio your Mac plays — it only measures how loud the music is; nothing is recorded or saved.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if notch.liveWaves, let failure = AudioLevels.shared.failure {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(failure + " The waves use their usual rhythm instead.").font(.callout)
                        Button("Open Privacy Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                        .buttonStyle(.link)
                    }
                }
            }
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
        } footer: {
            Text("The waves of the song playing: small on the right of the closed notch, larger beside the controls when it's open. Style, colour, brightness and glow apply to both.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var musicSection: some View {
        Section {
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
    }

    private var focusSection: some View {
        Section {
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
    }

    private var desktopSection: some View {
        Section {
            Picker("Desktop wallpaper", selection: Binding(
                get: { desktop.isBackdropVisible },
                set: { desktop.setBackdrop(visible: $0) }
            )) {
                Text("My wallpaper").tag(false)
                Text("Retro turntable").tag(true)
            }
            .pickerStyle(.segmented)
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
    }

    private var generalSection: some View {
        Section {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    // Re-read: registration can fail (e.g. quarantined app).
                    if !LaunchAtLogin.set(enabled) {
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
        }
    }

    // MARK: - Panel previews

    /// Opens the notch while a panel slider is held, and closes it a moment after
    /// letting go (unless the cursor has gone up to it).
    private func previewPanel(_ editing: Bool) {
        sizePreview += 1
        if editing {
            notch.isPreviewingSize = true
            notch.expand()
            return
        }
        endPreview(after: 1.2)
    }

    /// Shows the panel for a moment — after picking a preset or a motion style.
    /// For motion it closes and reopens, so the new spring is what you see.
    private func previewBriefly(reopen: Bool) {
        sizePreview += 1
        let preview = sizePreview
        if reopen && notch.isExpanded {
            notch.isPreviewingSize = false
            notch.collapse()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard preview == sizePreview else { return }
                notch.isPreviewingSize = true
                notch.expand()
                endPreview(after: 1.4)
            }
            return
        }
        notch.isPreviewingSize = true
        notch.expand()
        endPreview(after: 1.6)
    }

    private func endPreview(after delay: TimeInterval) {
        let preview = sizePreview
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
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

/// The categories on Settings' first page, in the order shown.
enum SettingsPage: String, CaseIterable, Identifiable {
    case notch, panel, record, waves
    case music, focus, desktop
    case general, updates

    var id: String { rawValue }

    static let groups: [(title: String, pages: [SettingsPage])] = [
        ("Look", [.notch, .panel, .record, .waves]),
        ("Features", [.music, .focus, .desktop]),
        ("Spindle", [.general, .updates])
    ]

    var title: String {
        switch self {
        case .notch: return "Notch"
        case .panel: return "Panel"
        case .record: return "Record"
        case .waves: return "Waves"
        case .music: return "Music Source"
        case .focus: return "Focus Timer"
        case .desktop: return "Desktop"
        case .general: return "General"
        case .updates: return "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .notch: return "macbook"
        case .panel: return "rectangle.expand.vertical"
        case .record: return "opticaldisc.fill"
        case .waves: return "waveform"
        case .music: return "music.note"
        case .focus: return "timer"
        case .desktop: return "menubar.dock.rectangle"
        case .general: return "gearshape.fill"
        case .updates: return "arrow.down.circle.fill"
        }
    }

    /// The icon tile's colour, System Settings style.
    var tint: Color {
        switch self {
        case .notch: return Color(white: 0.25)
        case .panel: return .indigo
        case .record: return Color(red: 0.91, green: 0.45, blue: 0.36)
        case .waves: return .pink
        case .music: return .red
        case .focus: return .orange
        case .desktop: return .teal
        case .general: return .gray
        case .updates: return .blue
        }
    }
}

/// One category on the first page: icon, name and current state, opening its page.
private struct CategoryRow: View {
    var page: SettingsPage
    var summary: String
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(page.tint.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .opacity(isHovering ? 0.8 : 1)
    }
}

/// Settings → Panel: the open panel's shape and feel, with presets and a live preview.
private struct PanelSettings: View {
    @EnvironmentObject private var notch: NotchViewModel
    var preview: (Bool) -> Void
    var previewBriefly: (Bool) -> Void

    var body: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(PanelPreset.all) { preset in
                    PresetTile(preset: preset, isSelected: notch.currentPreset == preset) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { notch.apply(preset) }
                        previewBriefly(false)
                    }
                }
            }
            .padding(.vertical, 2)

            slider("Size", value: $notch.panelScale, in: NotchViewModel.panelScaleRange,
                   low: "Smaller", high: "Larger", readout: percent)
            slider("Width", value: $notch.panelWidth, in: NotchViewModel.panelWidthRange,
                   low: "Narrower", high: "Wider", readout: percent)
            slider("Height", value: $notch.panelHeight, in: NotchViewModel.panelHeightRange,
                   low: "Shorter", high: "Taller", readout: percent)
            slider("Corners", value: $notch.panelCornerRadius, in: NotchViewModel.cornerRadiusRange,
                   low: "Square", high: "Round", readout: { "\(Int($0.rounded())) pt" })
            slider("Cover", value: $notch.coverScale, in: NotchViewModel.coverScaleRange,
                   low: "Smaller", high: "Larger", readout: percent)

            Picker("Motion", selection: $notch.motion) {
                ForEach(NotchMotion.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: notch.motion) { _, _ in previewBriefly(true) }
            Text(notch.motion == .macOS
                 ? "Opens like a macOS menu or popover: a quick, clean grow and fade."
                 : "Springier than macOS's own pop-ups — Bouncy most of all.")
                .font(.caption).foregroundStyle(.secondary)

            slider("Closing", value: $notch.closeDelay, in: NotchViewModel.closeDelayRange,
                   low: "Instantly", high: "Relaxed", readout: { String(format: "%.2f s", $0) })

            HStack(alignment: .firstTextBaseline) {
                Text("Width and Height give the panel more room — the cover and controls keep their size. Size scales everything. The notch opens while you adjust, so you can see it; the closed pill always fits your Mac's notch.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Reset All") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        notch.apply(.standard)
                        notch.motion = .macOS
                        notch.closeDelay = 0.08
                    }
                    previewBriefly(false)
                }
                .disabled(notch.currentPreset == .standard && notch.motion == .macOS && abs(notch.closeDelay - 0.08) < 0.005)
            }
        } header: {
            Text("Panel")
        }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }

    /// Continuous (a stepped slider draws tick marks); the readout rounds.
    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                        low: String, high: String,
                        readout: @escaping (Double) -> String) -> some View {
        LabeledContent(title) {
            HStack {
                Text(low).font(.caption).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                Slider(value: value, in: range, onEditingChanged: preview)
                    .frame(minWidth: 150)
                Text(high).font(.caption).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                Text(readout(value.wrappedValue))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
            // One width for every row, so the sliders line up.
            .frame(width: 380)
        }
    }
}

/// A preset as a little panel silhouette hanging from a notch, in its proportions.
private struct PresetTile: View {
    var preset: PanelPreset
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    let height = 13 * preset.height * preset.scale / 0.9
                    UnevenRoundedRectangle(bottomLeadingRadius: preset.cornerRadius * 0.22,
                                           bottomTrailingRadius: preset.cornerRadius * 0.22, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.55))
                        .frame(width: height * preset.aspect, height: height)
                    Capsule().fill(Color.black).frame(width: 12, height: 3)
                }
                .frame(width: 64, height: 32, alignment: .top)
                Text(preset.name).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
