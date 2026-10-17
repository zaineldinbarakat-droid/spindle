import AppKit
import SwiftUI
import UserNotifications
import SpindleSync

/// Manual AppKit entry point.
///
/// The SwiftUI `App` lifecycle wants to own windows, but everything here is a panel we
/// place ourselves against the notch or the desktop, so driving `NSApplication`
/// directly is less fighting for the same result.
@main
enum SpindleMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // `.accessory`: no Dock icon, no menu bar of our own.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?
    /// Sleeve has been asked to show every app before the icon goes in.
    private var addingIconAfterSleeve = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let environment = AppEnvironment.shared

            environment.player.start()
            environment.player.requestAuthorizationIfNeeded()

            let controller = NotchWindowController(viewModel: environment.notch,
                                                   player: environment.player,
                                                   timer: environment.timer)
            controller.show()
            notchController = controller

            environment.timer.onPhaseChange = { [weak controller] _ in
                guard AppEnvironment.shared.timer.peekNotchOnPhaseEnd else { return }
                controller?.peek(tab: .focus)
            }

            environment.desktop.restore()
            UNUserNotificationCenter.current().delegate = self

            installStatusItem()
            environment.updater.checkInBackgroundIfDue()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppEnvironment.shared.player.stop()
            AppEnvironment.shared.desktop.tearDown()
            notchController?.tearDown()
        }
    }

    /// Show timer banners even on the rare occasion Spindle is the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Status item

    @MainActor
    private func installStatusItem() {
        // With Sleeve hiding the other apps, an icon added now would land among
        // Apple's, far from the rest: ask Sleeve to show them all first.
        let sleeveRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: SyncChannel.sleeveBundleID).isEmpty
        guard !sleeveRunning || addingIconAfterSleeve else {
            SyncChannel.post(SyncChannel.spindleAddingIcon)
            addingIconAfterSleeve = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.installStatusItem() }
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "smallcircle.filled.circle",
                                     accessibilityDescription: "Spindle")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Rebuilt on every open so titles and checkmarks reflect the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { rebuild(menu) }
    }

    @MainActor
    private func rebuild(_ menu: NSMenu) {
        let environment = AppEnvironment.shared
        let player = environment.player
        let timer = environment.timer
        let desktop = environment.desktop

        menu.removeAllItems()

        add(to: menu, "Show Player", #selector(togglePanel))
        add(to: menu, "Open \(player.sourceProvider.displayName)", #selector(openSourceApp))

        menu.addItem(.separator())

        let focusTitle = timer.isActive
            ? "Focus Timer — \(timer.phase.title) \(timer.remainingString)"
            : "Focus Timer"
        let focusItem = NSMenuItem(title: focusTitle, action: nil, keyEquivalent: "")
        let focusMenu = NSMenu()
        add(to: focusMenu, timer.isRunning ? "Pause" : (timer.isPaused ? "Resume" : "Lock In"),
            #selector(toggleTimer))
        add(to: focusMenu, "Skip to Next Phase", #selector(skipPhase))
        add(to: focusMenu, "Reset", #selector(resetTimer))
        focusMenu.addItem(.separator())
        for preset in PomodoroTimer.Preset.all {
            let entry = add(to: focusMenu, preset.name, #selector(applyPreset(_:)))
            entry.representedObject = preset.name
            entry.state = timer.currentPreset == preset ? .on : .off
        }
        focusMenu.addItem(.separator())
        add(to: focusMenu, "Show in Notch", #selector(showFocusTab))
        focusItem.submenu = focusMenu
        menu.addItem(focusItem)

        menu.addItem(.separator())

        let widgetsItem = NSMenuItem(title: "Desktop Widgets", action: nil, keyEquivalent: "")
        let widgetsMenu = NSMenu()
        for kind in DesktopWidgetKind.allCases {
            let entry = add(to: widgetsMenu, kind.title, #selector(toggleWidget(_:)))
            entry.representedObject = kind.rawValue
            entry.state = desktop.isWidgetVisible(kind) ? .on : .off
        }
        widgetsItem.submenu = widgetsMenu
        menu.addItem(widgetsItem)

        let styleItem = NSMenuItem(title: "Show Song As", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        let currentStyle = ArtworkStyle(rawValue: UserDefaults.standard.string(forKey: ArtworkStyle.storageKey) ?? "") ?? .vinyl
        for style in ArtworkStyle.allCases {
            let entry = add(to: styleMenu, style.title, #selector(setArtworkStyle(_:)))
            entry.representedObject = style.rawValue
            entry.state = style == currentStyle ? .on : .off
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        let lookItem = NSMenuItem(title: "Notch Look", action: nil, keyEquivalent: "")
        let lookMenu = NSMenu()
        for style in NotchViewModel.Style.allCases {
            let entry = add(to: lookMenu, style.title, #selector(setNotchStyle(_:)))
            entry.representedObject = style.rawValue
            entry.state = environment.notch.style == style ? .on : .off
            if style == .liquidGlass && !NotchViewModel.Style.isGlassAvailable {
                entry.action = nil
                entry.title += " (macOS 26+)"
            }
        }
        lookMenu.addItem(.separator())
        add(to: lookMenu, "Album Color Reaches Into the Notch", #selector(toggleTintNotch))
            .state = environment.notch.tintNotch ? .on : .off
        lookItem.submenu = lookMenu
        menu.addItem(lookItem)

        let wallpaperItem = NSMenuItem(title: "Desktop Wallpaper", action: nil, keyEquivalent: "")
        let wallpaperMenu = NSMenu()
        add(to: wallpaperMenu, "My Wallpaper", #selector(useOwnWallpaper))
            .state = desktop.isBackdropVisible ? .off : .on
        add(to: wallpaperMenu, "Retro Turntable", #selector(useRetroWallpaper))
            .state = desktop.isBackdropVisible ? .on : .off
        wallpaperItem.submenu = wallpaperMenu
        menu.addItem(wallpaperItem)
        add(to: menu, desktop.isFullScreenVisible ? "Exit Full-Screen Turntable" : "Full-Screen Turntable",
            #selector(toggleFullScreen), key: "f")

        menu.addItem(.separator())

        add(to: menu, "Settings…", #selector(openSettings), key: ",")
        add(to: menu, "Check for Updates…", #selector(checkForUpdates))
        add(to: menu, "Grant Music Permissions…", #selector(openAutomationSettings))

        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit Spindle",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
    }

    @MainActor @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @MainActor @objc private func togglePanel() {
        AppEnvironment.shared.notch.tab = .player
        AppEnvironment.shared.notch.toggle()
    }

    @MainActor @objc private func openSourceApp() {
        AppEnvironment.shared.player.openSourceApp()
    }

    @MainActor @objc private func toggleTimer() { AppEnvironment.shared.timer.toggle() }
    @MainActor @objc private func skipPhase() { AppEnvironment.shared.timer.skip() }
    @MainActor @objc private func resetTimer() { AppEnvironment.shared.timer.reset() }

    @MainActor @objc private func showFocusTab() {
        notchController?.peek(tab: .focus, for: 6)
    }

    @MainActor @objc private func toggleWidget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = DesktopWidgetKind(rawValue: raw) else { return }
        AppEnvironment.shared.desktop.toggleWidget(kind)
    }

    @MainActor @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let preset = PomodoroTimer.Preset.all.first(where: { $0.name == name }) else { return }
        AppEnvironment.shared.timer.apply(preset)
    }

    @MainActor @objc private func toggleTintNotch() {
        AppEnvironment.shared.notch.tintNotch.toggle()
    }

    @MainActor @objc private func setNotchStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = NotchViewModel.Style(rawValue: raw) else { return }
        AppEnvironment.shared.notch.style = style
    }

    @MainActor @objc private func useOwnWallpaper() {
        AppEnvironment.shared.desktop.setBackdrop(visible: false)
    }

    @MainActor @objc private func useRetroWallpaper() {
        AppEnvironment.shared.desktop.setBackdrop(visible: true)
    }

    @MainActor @objc private func setArtworkStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: ArtworkStyle.storageKey)
    }

    @MainActor @objc private func toggleFullScreen() {
        AppEnvironment.shared.desktop.toggleFullScreen()
    }

    @MainActor @objc private func checkForUpdates() {
        AppEnvironment.shared.updater.checkNow()
    }

    @MainActor @objc private func openSettings() {
        SettingsWindow.show()
    }

    @MainActor @objc private func openAutomationSettings() {
        AppEnvironment.shared.player.openAutomationSettings()
    }
}
