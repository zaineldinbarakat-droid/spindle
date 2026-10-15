import AppKit
import Combine
import SwiftUI
import SpindleSync

/// Sleeve: a menu bar manager that keeps Spindle company.
@main
enum SleeveMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = SleeveAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Long-lived objects, shared by the menu bar, the panels and Settings.
@MainActor
final class SleeveEnvironment: ObservableObject {
    static let shared = SleeveEnvironment()

    let settings = SleeveSettings.shared
    let spindle = SpindleBridge()
    let sections = SectionManager()
    lazy var automation = AutomationEngine(sections: sections)
    lazy var bar = SleeveBarController(sections: sections, spindle: spindle)
    lazy var search = SearchController(sections: sections)
    lazy var zen = ZenController(spindle: spindle, sections: sections)
    lazy var overlay = MenuBarOverlayController(sections: sections, spindle: spindle)
    lazy var gestures = RevealGestures(sections: sections, spindle: spindle)
    lazy var cover = CoverController(sections: sections)
    let updater = Updater(appName: "Sleeve")

    @Published var settingsTab: SettingsTab = .general

    private init() {}
}

final class SleeveAppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let env = SleeveEnvironment.shared

            env.sections.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
            env.sections.onToggleClickedForBar = { env.bar.toggle() }
            env.sections.onHoverRevealForBar = { env.bar.open() }
            env.gestures.showBar = { env.bar.open() }
            env.gestures.hideBar = { env.bar.close() }
            // One dropdown at a time.
            env.spindle.onSpindleExpanded = { env.bar.close() }

            _ = env.automation
            env.overlay.refresh()
            if SectionManager.isModernMenuBar {
                env.cover.onClick = {
                    env.settings.useSleeveBar ? env.bar.open() : env.sections.reveal(.hidden)
                }
                env.cover.update()
            }

            HotkeyCenter.shared.handler = { action in
                switch action {
                case .toggleHidden:
                    (env.settings.useSleeveBar && !env.settings.hideAllApps) ? env.bar.toggle() : env.sections.toggle()
                case .showAll:
                    env.settings.useSleeveBar ? env.bar.toggle(includeAlwaysHidden: true) : env.sections.toggleAll()
                case .search: env.search.toggle()
                case .zen: env.zen.toggle()
                }
            }
            HotkeyCenter.shared.register(env.settings.hotkeys)
            env.settings.$hotkeys
                .dropFirst()
                .sink { HotkeyCenter.shared.register($0) }
                .store(in: &cancellables)

            // Without the Accessibility grant Sleeve can't hide anything, so say so at
            // every launch until it's fixed — Settings explains and has the fix button.
            if !AXIsProcessTrusted() {
                SleeveSettingsWindow.show()
            }
            env.updater.checkInBackgroundIfDue()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            let env = SleeveEnvironment.shared
            env.zen.disable()
            env.spindle.sleeveTerminating()
            env.sections.tearDown()
            env.overlay.tearDown()
            env.cover.tearDown()
            env.gestures.tearDown()
        }
    }

    /// Reopening the app from Finder or Spotlight opens Settings — the only way back
    /// in if the toggle has been lost off-screen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { SleeveSettingsWindow.show() }
        return true
    }

    @MainActor
    private func makeMenu() -> NSMenu {
        let env = SleeveEnvironment.shared
        let menu = NSMenu()
        func add(_ title: String, _ key: String = "", action: @escaping () -> Void) -> NSMenuItem {
            let item = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
            menu.addItem(item)
            return item
        }

        _ = add(env.sections.state == .collapsed ? "Show Hidden Icons" : "Hide Icons") { env.sections.toggle() }
        _ = add(env.sections.state == .all ? "Hide Always Hidden Icons" : "Show All Icons") { env.sections.toggleAll() }
        _ = add("Search Menu Bar…") { env.search.open() }
        menu.addItem(.separator())
        let zen = add("Zen Mode") { env.zen.toggle() }
        zen.state = env.zen.isOn ? .on : .off

        let colorItem = NSMenuItem(title: "Menu Bar Color", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for (name, style) in MenuBarStyle.presets {
            let entry = ClosureMenuItem(title: name, keyEquivalent: "") {
                env.settings.appearance.light = style
                if env.settings.appearance.separateDarkStyle { env.settings.appearance.dark = style }
            }
            entry.state = env.settings.appearance.light == style ? .on : .off
            colorMenu.addItem(entry)
        }
        colorMenu.addItem(.separator())
        colorMenu.addItem(ClosureMenuItem(title: "Customize…", keyEquivalent: "") {
            SleeveSettingsWindow.show(tab: .appearance)
        })
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)
        menu.addItem(.separator())
        _ = add("Settings…", ",") { SleeveSettingsWindow.show() }
        _ = add("Check for Updates…") { env.updater.checkNow() }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sleeve", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
}

/// NSMenuItem that runs a closure, so menus can be built inline.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}
