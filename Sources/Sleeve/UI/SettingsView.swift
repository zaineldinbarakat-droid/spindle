import AppKit
import ServiceManagement
import SwiftUI

@MainActor
enum SleeveSettingsWindow {
    private static var window: NSWindow?

    static func show(tab: SettingsTab = .general) {
        let env = SleeveEnvironment.shared
        env.settingsTab = tab
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = SleeveSettingsView()
            .environmentObject(env)
            .environmentObject(env.settings)
            .environmentObject(env.sections)
            .environmentObject(env.automation)
            .environmentObject(env.spindle)
        let created = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 560),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
        created.title = "Sleeve"
        created.contentView = NSHostingView(rootView: view)
        created.isReleasedWhenClosed = false
        created.center()
        window = created
        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, layout, appearance, hotkeys, automation, spindle
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .layout: return "Layout"
        case .appearance: return "Appearance"
        case .hotkeys: return "Hotkeys"
        case .automation: return "Automation"
        case .spindle: return "Spindle"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .layout: return "rectangle.split.3x1"
        case .appearance: return "paintpalette"
        case .hotkeys: return "command"
        case .automation: return "bolt.badge.clock"
        case .spindle: return "opticaldisc"
        }
    }
}

struct SleeveSettingsView: View {
    @EnvironmentObject private var env: SleeveEnvironment
    @EnvironmentObject private var sections: SectionManager

    var body: some View {
        VStack(spacing: 0) {
            if !sections.isAccessibilityTrusted {
                PermissionBanner()
            }
            TabView(selection: $env.settingsTab) {
                GeneralTab().tabItem { Label("General", systemImage: SettingsTab.general.symbol) }.tag(SettingsTab.general)
                LayoutTab().tabItem { Label("Layout", systemImage: SettingsTab.layout.symbol) }.tag(SettingsTab.layout)
                AppearanceTab().tabItem { Label("Appearance", systemImage: SettingsTab.appearance.symbol) }.tag(SettingsTab.appearance)
                HotkeysTab().tabItem { Label("Hotkeys", systemImage: SettingsTab.hotkeys.symbol) }.tag(SettingsTab.hotkeys)
                AutomationTab().tabItem { Label("Automation", systemImage: SettingsTab.automation.symbol) }.tag(SettingsTab.automation)
                SpindleTab().tabItem { Label("Spindle", systemImage: SettingsTab.spindle.symbol) }.tag(SettingsTab.spindle)
            }
            .padding(12)
        }
        .frame(minWidth: 600, minHeight: 520)
    }
}

private struct PermissionBanner: View {
    @EnvironmentObject private var sections: SectionManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Sleeve needs Accessibility access").font(.headline)
                Text("It's how Sleeve sees which icons are where. If Sleeve is already listed and switched on but this message stays, an older build's entry is in the way: select Sleeve in the list, click −, then click Grant Access again.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button("Grant Access…") {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    AXIsProcessTrustedWithOptions(options)
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("Restart Sleeve") { SleeveRelauncher.relaunch() }
                    .help("Some macOS versions only notice a new grant after a restart")
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject private var settings: SleeveSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Toggle") {
                Picker("Icon", selection: $settings.toggleIcon) {
                    ForEach(SleeveSettings.ToggleIcon.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show hidden icons in the Sleeve Bar (recommended on notched Macs)", isOn: $settings.useSleeveBar)
                Text("Click the toggle to reveal · ⌥-click shows Always Hidden too · right-click for the menu")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Also reveal when") {
                Toggle("Hovering over an empty part of the menu bar", isOn: $settings.revealOnHover)
                Toggle("Scrolling or swiping on the menu bar", isOn: $settings.revealOnScroll)
                Toggle("Clicking an empty part of the menu bar", isOn: $settings.revealOnEmptyClick)
            }
            Section("Hide again") {
                Picker("Rehide", selection: $settings.rehideMode) {
                    ForEach(SleeveSettings.RehideMode.allCases) { Text($0.title).tag($0) }
                }
                if settings.rehideMode == .timed {
                    HStack {
                        Slider(value: $settings.rehideDelay, in: 2...60, step: 1)
                        Text("\(Int(settings.rehideDelay)) s").monospacedDigit().frame(width: 40)
                    }
                }
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Layout

private struct LayoutTab: View {
    @EnvironmentObject private var sections: SectionManager
    @State private var moving: String?
    @State private var error: String?
    @State private var spacing: Double = Double(MenuBarSpacing.current ?? 8)
    @State private var usesDefaultSpacing = MenuBarSpacing.current == nil
    @State private var confirmRelaunch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if SectionManager.usesCoverHiding {
                Label {
                    Text("To move an icon, hold **⌘** and drag it in the menu bar itself: left of the first faint │ next to Sleeve's icon is **Hidden**, left of the second is **Always Hidden**. macOS 27 doesn't let apps move other apps' icons, so dragging here can't do it for you.")
                } icon: {
                    Image(systemName: "command")
                }
                .font(.callout)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
            } else {
                Text("Drag icons between sections. Sleeve moves the real icon for you (it ⌘-drags it, so you'll see the cursor jump for a moment). You can also ⌘-drag icons in the menu bar yourself.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(MenuBarSection.allCases) { section in
                    SectionColumn(section: section,
                                  items: sections.items(in: section),
                                  moving: moving) { id in
                        move(id, to: section)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
            }

            GroupBox("Icon spacing") {
                HStack {
                    Toggle("System default", isOn: $usesDefaultSpacing)
                    Slider(value: $spacing, in: 0...20, step: 1).disabled(usesDefaultSpacing)
                    Text(usesDefaultSpacing ? "—" : "\(Int(spacing)) pt").monospacedDigit().frame(width: 44)
                    Button("Apply…") { confirmRelaunch = true }
                }
                Text("Takes effect once the apps that own menu bar icons restart. Apply restarts them for you.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .confirmationDialog("Restart menu bar apps?", isPresented: $confirmRelaunch) {
            Button("Apply and Restart Apps") {
                MenuBarSpacing.set(usesDefaultSpacing ? nil : Int(spacing))
                MenuBarSpacing.relaunch(MenuBarSpacing.appsToRelaunch(from: sections.items))
            }
            Button("Apply Without Restarting") {
                MenuBarSpacing.set(usesDefaultSpacing ? nil : Int(spacing))
            }
        } message: {
            let names = MenuBarSpacing.appsToRelaunch(from: sections.items)
                .compactMap(\.localizedName).joined(separator: ", ")
            Text("These will quit and reopen: \(names)")
        }
    }

    private func move(_ id: String, to section: MenuBarSection) {
        guard let item = sections.items.first(where: { $0.id == id }),
              sections.section(of: item) != section else { return }
        if SectionManager.usesCoverHiding {
            error = "On macOS 27, ⌘-drag “\(item.displayName)” in the menu bar itself — apps can't move it for you."
            return
        }
        moving = id
        error = nil
        Task {
            do {
                try await ItemMover.move(item, to: section, using: sections)
            } catch {
                self.error = error.localizedDescription
            }
            moving = nil
        }
    }
}

private struct SectionColumn: View {
    var section: MenuBarSection
    var items: [MenuBarItem]
    var moving: String?
    var onDrop: (String) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(section.title).font(.headline)
                Spacer()
                Text("\(items.count)").foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Image(nsImage: item.icon)
                                .resizable()
                                .renderingMode(item.isSystemItem ? .template : .original)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                            Text(item.displayName).lineLimit(1).font(.system(size: 12))
                            Spacer(minLength: 0)
                            if moving == item.id { ProgressView().controlSize(.small) }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
                        .draggable(item.id)
                    }
                    if items.isEmpty {
                        Text("Drop icons here").font(.caption).foregroundStyle(.tertiary).padding(.top, 20)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(targeted ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: targeted ? 2 : 1))
        .dropDestination(for: String.self) { ids, _ in
            ids.first.map(onDrop)
            return true
        } isTargeted: { targeted = $0 }
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @EnvironmentObject private var settings: SleeveSettings
    @State private var target = "light"

    private var targets: [(String, String)] {
        var list = [("light", settings.appearance.separateDarkStyle ? "Light Mode" : "All Modes")]
        if settings.appearance.separateDarkStyle { list.append(("dark", "Dark Mode")) }
        for screen in NSScreen.screens { list.append(("display:" + screen.localizedName, screen.localizedName)) }
        return list
    }

    private var binding: Binding<MenuBarStyle> {
        Binding(
            get: {
                switch target {
                case "dark": return settings.appearance.dark
                case let t where t.hasPrefix("display:"):
                    let name = String(t.dropFirst(8))
                    return settings.appearance.displayOverrides[name] ?? settings.appearance.light
                default: return settings.appearance.light
                }
            },
            set: { new in
                switch target {
                case "dark": settings.appearance.dark = new
                case let t where t.hasPrefix("display:"):
                    settings.appearance.displayOverrides[String(t.dropFirst(8))] = new
                default: settings.appearance.light = new
                }
            })
    }

    var body: some View {
        Form {
            Section {
                MenuBarStyleView(style: binding.wrappedValue, layout: BarLayout(
                    size: CGSize(width: 540, height: 40), barHeight: 30,
                    appMenusEnd: 170, statusStart: 360, notch: nil))
                    .frame(width: 540, height: 40)
                    .background(LinearGradient(colors: [.blue.opacity(0.5), .purple.opacity(0.4)],
                                               startPoint: .leading, endPoint: .trailing))
                    .overlay(alignment: .topLeading) { previewContents }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Section {
                Toggle("Different style in Dark Mode", isOn: $settings.appearance.separateDarkStyle)
                Picker("Editing", selection: $target) {
                    ForEach(targets, id: \.0) { Text($0.1).tag($0.0) }
                }
                if target.hasPrefix("display:") {
                    let name = String(target.dropFirst(8))
                    if settings.appearance.displayOverrides[name] != nil {
                        Button("Stop overriding this display") { settings.appearance.displayOverrides[name] = nil }
                    } else {
                        Text("Changing anything here gives this display its own style.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Presets")
                    ForEach(MenuBarStyle.presets, id: \.0) { preset in
                        Button(preset.0) { binding.wrappedValue = preset.1 }
                    }
                }
            }

            Section("Fill") {
                Picker("Fill", selection: binding.fill) {
                    ForEach(MenuBarStyle.Fill.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if binding.wrappedValue.fill != .none {
                    ColorPicker("Color", selection: colorBinding(binding.color1))
                }
                if binding.wrappedValue.fill == .gradient {
                    ColorPicker("Second color", selection: colorBinding(binding.color2))
                }
            }

            Section("Shape") {
                Picker("Shape", selection: binding.shape) {
                    ForEach(MenuBarStyle.Shape.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if binding.wrappedValue.shape != .full {
                    LabeledContent("Corner radius") { Slider(value: binding.cornerRadius, in: 0...20) }
                    LabeledContent("Inset") { Slider(value: binding.inset, in: 0...8) }
                }
            }

            Section("Shadow & Border") {
                Toggle("Drop shadow", isOn: binding.shadow)
                if binding.wrappedValue.shadow {
                    LabeledContent("Strength") { Slider(value: binding.shadowOpacity, in: 0.05...0.8) }
                }
                Toggle("Border", isOn: binding.border)
                if binding.wrappedValue.border {
                    ColorPicker("Border color", selection: colorBinding(binding.borderColor))
                    LabeledContent("Width") { Slider(value: binding.borderWidth, in: 0.5...3) }
                }
            }

            Section {
                Text("Styles draw behind the menu bar, so they need the system menu bar background off (System Settings → Menu Bar → Show menu bar background).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var previewContents: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo")
            Text("Finder").bold()
            Text("File")
            Text("Edit")
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("12:00")
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    private func colorBinding(_ rgba: Binding<RGBA>) -> Binding<Color> {
        Binding(get: { rgba.wrappedValue.color }, set: { rgba.wrappedValue = RGBA($0) })
    }
}

// MARK: - Hotkeys

private struct HotkeysTab: View {
    @EnvironmentObject private var settings: SleeveSettings

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    LabeledContent(action.title) {
                        HotkeyRecorder(combo: Binding(
                            get: { settings.hotkeys[action] },
                            set: { settings.hotkeys[action] = $0 }))
                    }
                }
            }
            Section {
                Button("Restore Defaults") { settings.hotkeys = HotkeyAction.defaults }
            }
        }
        .formStyle(.grouped)
    }
}

private struct HotkeyRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(recording ? "Type shortcut…" : (combo?.displayString ?? "None")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 110)
            if combo != nil && !recording {
                Button { combo = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }

    private func start() {
        recording = true
        HotkeyCenter.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }  // esc cancels
            if let new = KeyCombo(event: event) {
                combo = new
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotkeyCenter.shared.register(SleeveSettings.shared.hotkeys)
    }
}

// MARK: - Automation

private struct AutomationTab: View {
    @EnvironmentObject private var settings: SleeveSettings
    @EnvironmentObject private var automation: AutomationEngine

    var body: some View {
        Form {
            Section {
                Text("While a rule's condition is true, Sleeve keeps that section of the menu bar open.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach($settings.rules) { $rule in
                    RuleRow(rule: $rule, isActive: automation.activeRuleIDs.contains(rule.id)) {
                        settings.rules.removeAll { $0.id == rule.id }
                    }
                }
                Menu("Add Rule") {
                    Button("Battery is low") { add(.batteryBelow(percent: 20)) }
                    Button("Connected to a Wi-Fi network") { add(.wifiNetwork(ssid: "")) }
                    Button("A Focus mode is on") { add(.focusActive) }
                    Button("A script succeeds") { add(.script(path: "")) }
                }
                .fixedSize()
            }
            if automation.wifiNeedsLocation {
                Section {
                    Label("macOS only tells apps the Wi-Fi network name if they have Location access. Allow Sleeve in Privacy & Security → Location Services.",
                          systemImage: "location")
                        .font(.caption)
                }
            }
            if automation.focusNeedsFullDiskAccess {
                Section {
                    Label("macOS has no public Focus API; Sleeve reads Focus state from a system file that needs Full Disk Access (Privacy & Security → Full Disk Access).",
                          systemImage: "moon")
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.rules) { _, _ in automation.evaluate() }
    }

    private func add(_ condition: TriggerRule.Condition) {
        settings.rules.append(TriggerRule(condition: condition))
    }
}

private struct RuleRow: View {
    @Binding var rule: TriggerRule
    var isActive: Bool
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(isActive ? Color.green : Color.secondary.opacity(0.3)).frame(width: 8, height: 8)
                    .help(isActive ? "Condition is true right now" : "Condition is false")
                Toggle(rule.condition.title, isOn: $rule.isEnabled)
                Spacer()
                Picker("", selection: $rule.action) {
                    ForEach(TriggerRule.Action.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            switch rule.condition {
            case .batteryBelow(let percent):
                HStack {
                    Text("Below")
                    Slider(value: Binding(get: { Double(percent) },
                                          set: { rule.condition = .batteryBelow(percent: Int($0)) }),
                           in: 5...95, step: 5)
                    Text("\(percent)%").monospacedDigit().frame(width: 40)
                }
            case .wifiNetwork(let ssid):
                TextField("Network name (leave empty for any)", text: Binding(
                    get: { ssid }, set: { rule.condition = .wifiNetwork(ssid: $0) }))
            case .script(let path):
                HStack {
                    TextField("Path to an executable script", text: Binding(
                        get: { path }, set: { rule.condition = .script(path: $0) }))
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            rule.condition = .script(path: url.path)
                        }
                    }
                }
            case .focusActive:
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Spindle

private struct SpindleTab: View {
    @EnvironmentObject private var settings: SleeveSettings
    @EnvironmentObject private var spindle: SpindleBridge

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "opticaldisc").font(.title2)
                    VStack(alignment: .leading) {
                        Text("Spindle").font(.headline)
                        Text(spindle.state != nil ? "Running and in sync" :
                                (spindle.isSpindleRunning ? "Running — waiting for it to check in" : "Not running"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(spindle.state != nil ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 9, height: 9)
                }
            }
            Section("Working together") {
                Toggle("Keep out of Spindle's notch area (hover, styling, Sleeve Bar)", isOn: $settings.avoidSpindle)
                Toggle("Zen mode hides Spindle too", isOn: $settings.zenHidesSpindle)
                Text("Only one dropdown opens at a time: opening the Sleeve Bar closes Spindle's panel and the other way round.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
