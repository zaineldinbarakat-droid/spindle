import AppKit
import Combine
import SwiftUI

/// Every user-facing preference, persisted to UserDefaults by hand.
///
/// `@AppStorage` inside an ObservableObject writes but never fires objectWillChange, so
/// changes wouldn't reach the menu bar until relaunch; `didSet` + `@Published` does.
@MainActor
final class SleeveSettings: ObservableObject {
    static let shared = SleeveSettings()

    private let store = UserDefaults.standard

    // MARK: Reveal

    enum ToggleIcon: String, CaseIterable, Identifiable, Codable {
        case dot, chevron, sleeve
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dot: return "Dot"
            case .chevron: return "Chevron"
            case .sleeve: return "Record"
            }
        }
    }

    enum RehideMode: String, CaseIterable, Identifiable, Codable {
        /// When the cursor leaves the menu bar and no menu is open.
        case smart
        /// After a fixed delay.
        case timed
        case never
        var id: String { rawValue }
        var title: String {
            switch self {
            case .smart: return "When the cursor leaves the menu bar"
            case .timed: return "After a delay"
            case .never: return "Never"
            }
        }
    }

    @Published var toggleIcon: ToggleIcon { didSet { save(toggleIcon.rawValue, "toggleIcon") } }
    @Published var revealOnHover: Bool { didSet { save(revealOnHover, "revealOnHover") } }
    @Published var revealOnScroll: Bool { didSet { save(revealOnScroll, "revealOnScroll") } }
    @Published var revealOnEmptyClick: Bool { didSet { save(revealOnEmptyClick, "revealOnEmptyClick") } }
    @Published var rehideMode: RehideMode { didSet { save(rehideMode.rawValue, "rehideMode") } }
    @Published var rehideDelay: Double { didSet { save(rehideDelay, "rehideDelay") } }

    /// Show hidden items in a floating bar under the menu bar instead of in place.
    /// On notched Macs this is what keeps them from disappearing behind the camera.
    @Published var useSleeveBar: Bool { didSet { save(useSleeveBar, "useSleeveBar") } }
    /// macOS 27: hide icons with macOS's own (private) restriction so they leave the
    /// bar, instead of painting over them. Falls back to covering if unavailable.
    @Published var useNativeHiding: Bool { didSet { save(useNativeHiding, "useNativeHiding") } }

    /// Ice-style: every app icon is hidden until the cursor reaches the menu bar.
    /// Apple's own items and `alwaysShownBundles` stay. When off, only icons the user
    /// ⌘-dragged into the Hidden sections are hidden.
    @Published var hideAllApps: Bool { didSet { save(hideAllApps, "hideAllApps") } }
    /// Apps kept visible even with `hideAllApps` on.
    @Published var alwaysShownBundles: [String] { didSet { save(alwaysShownBundles, "alwaysShownBundles") } }

    // MARK: Spindle

    @Published var avoidSpindle: Bool { didSet { save(avoidSpindle, "avoidSpindle") } }
    @Published var zenHidesSpindle: Bool { didSet { save(zenHidesSpindle, "zenHidesSpindle") } }

    // MARK: Hotkeys

    @Published var hotkeys: [HotkeyAction: KeyCombo] {
        didSet {
            if let data = try? JSONEncoder().encode(hotkeys) { store.set(data, forKey: "hotkeys") }
        }
    }

    // MARK: Appearance

    @Published var appearance: AppearanceProfiles {
        didSet {
            if let data = try? JSONEncoder().encode(appearance) { store.set(data, forKey: "appearance") }
        }
    }

    // MARK: Automation

    @Published var rules: [TriggerRule] {
        didSet {
            if let data = try? JSONEncoder().encode(rules) { store.set(data, forKey: "rules") }
        }
    }

    private init() {
        let d = UserDefaults.standard
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
        }
        toggleIcon = ToggleIcon(rawValue: d.string(forKey: "toggleIcon") ?? "") ?? .chevron
        revealOnHover = bool("revealOnHover", true)
        revealOnScroll = bool("revealOnScroll", true)
        revealOnEmptyClick = bool("revealOnEmptyClick", false)
        rehideMode = RehideMode(rawValue: d.string(forKey: "rehideMode") ?? "") ?? .smart
        rehideDelay = d.object(forKey: "rehideDelay") == nil ? 8 : d.double(forKey: "rehideDelay")
        // Default on for notched Macs, where in-place reveal can push items under the
        // camera — except on macOS 27, where hidden icons never move (they're covered,
        // not pushed), so revealing them in place is always safe.
        let hasNotch = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
        useSleeveBar = bool("useSleeveBar", hasNotch && !SectionManager.isModernMenuBar)
        useNativeHiding = bool("useNativeHiding", true)
        // First launch of the version that introduced hide-all: it only makes sense
        // with hover-to-reveal, so switch that on once, whatever was saved before.
        if d.object(forKey: "hideAllApps") == nil {
            d.set(true, forKey: "hideAllApps")
            d.set(true, forKey: "revealOnHover")
            revealOnHover = true
        }
        hideAllApps = bool("hideAllApps", true)
        alwaysShownBundles = d.stringArray(forKey: "alwaysShownBundles") ?? []
        avoidSpindle = bool("avoidSpindle", true)
        zenHidesSpindle = bool("zenHidesSpindle", true)

        if let data = d.data(forKey: "hotkeys"),
           let decoded = try? JSONDecoder().decode([HotkeyAction: KeyCombo].self, from: data) {
            hotkeys = decoded
        } else {
            hotkeys = HotkeyAction.defaults
        }
        if let data = d.data(forKey: "appearance"),
           let decoded = try? JSONDecoder().decode(AppearanceProfiles.self, from: data) {
            appearance = decoded
        } else {
            appearance = AppearanceProfiles()
        }
        if let data = d.data(forKey: "rules"),
           let decoded = try? JSONDecoder().decode([TriggerRule].self, from: data) {
            rules = decoded
        } else {
            rules = []
        }
    }

    private func save(_ value: Any, _ key: String) {
        store.set(value, forKey: key)
    }
}
