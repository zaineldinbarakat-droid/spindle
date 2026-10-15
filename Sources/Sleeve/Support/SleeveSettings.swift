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

    /// The look of Sleeve's menu bar icon. Every style has two faces, like Ice's
    /// image sets: one while apps are tucked away, one while they're showing.
    enum ToggleIcon: String, CaseIterable, Identifiable, Codable {
        case eye, dot, ellipsis, chevron, door
        case record = "sleeve"
        case custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .eye: return "Eye"
            case .dot: return "Dot"
            case .ellipsis: return "Ellipsis"
            case .chevron: return "Chevron"
            case .door: return "Door"
            case .record: return "Record"
            case .custom: return "Custom Image"
            }
        }
        /// (hidden, showing) SF Symbol names.
        var faces: (hidden: String, shown: String) {
            switch self {
            // An empty outline while apps are tucked away, filled in while you look.
            case .eye: return ("eye", "eye.fill")
            case .dot: return ("circle", "circle.fill")
            case .ellipsis: return ("ellipsis.circle", "ellipsis.circle.fill")
            case .chevron: return ("chevron.compact.left", "chevron.compact.right")
            case .door: return ("door.left.hand.closed", "door.left.hand.open")
            case .record: return ("smallcircle.filled.circle", "opticaldisc")
            case .custom: return ("", "")
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
    /// Hovering over Sleeve's own icon reveals, like pointing at Ice's icon.
    @Published var revealOnIconHover: Bool { didSet { save(revealOnIconHover, "revealOnIconHover") } }
    /// Two-finger click (secondary click) on Sleeve's icon or an empty part of the
    /// menu bar shows or hides the hidden apps. The menu moves to ⌃-click.
    @Published var revealOnTwoFingerClick: Bool { didSet { save(revealOnTwoFingerClick, "revealOnTwoFingerClick") } }
    /// PNG for the Custom icon style, scaled to menu bar size.
    @Published var customIconData: Data? { didSet { store.set(customIconData, forKey: "customIconData") } }
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
        // v3: icon hover arrived, and the native-hiding switch may have been turned
        // off while the cover froze Sleeve (fixed in v3); bring both to the new
        // defaults once.
        if d.integer(forKey: "settingsVersion") < 3 {
            d.set(3, forKey: "settingsVersion")
            d.set(true, forKey: "useNativeHiding")
            d.set(true, forKey: "revealOnIconHover")
        }
        // v4: the emoji style is gone; whoever had it gets the eye.
        if d.integer(forKey: "settingsVersion") < 4 {
            d.set(4, forKey: "settingsVersion")
            if d.string(forKey: "toggleIcon") == "emoji" { d.set(ToggleIcon.eye.rawValue, forKey: "toggleIcon") }
        }
        toggleIcon = ToggleIcon(rawValue: d.string(forKey: "toggleIcon") ?? "") ?? .eye
        revealOnTwoFingerClick = bool("revealOnTwoFingerClick", true)
        revealOnIconHover = bool("revealOnIconHover", true)
        customIconData = d.data(forKey: "customIconData")
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
