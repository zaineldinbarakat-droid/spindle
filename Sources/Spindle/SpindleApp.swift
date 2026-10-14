import AppKit
import SwiftUI

/// Manual AppKit entry point.
///
/// The SwiftUI `App` lifecycle wants to own windows, but everything here is a panel we
/// place ourselves against the notch, so driving `NSApplication` directly is less
/// fighting for the same result.
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let environment = AppEnvironment.shared

            environment.player.start()
            environment.player.requestAuthorizationIfNeeded()

            let controller = NotchWindowController(viewModel: environment.notch,
                                                   player: environment.player)
            controller.show()
            notchController = controller

            installStatusItem()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppEnvironment.shared.player.stop()
            notchController?.tearDown()
        }
    }

    // MARK: - Status item

    @MainActor
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "smallcircle.filled.circle",
                                     accessibilityDescription: "Spindle")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Player",
                     action: #selector(togglePanel),
                     keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…",
                     action: #selector(openSettings),
                     keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Grant Music Permissions…",
                     action: #selector(openAutomationSettings),
                     keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Spindle",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        item.menu = menu
        statusItem = item
    }

    @MainActor @objc private func togglePanel() {
        AppEnvironment.shared.notch.toggle()
    }

    @MainActor @objc private func openSettings() {
        SettingsWindow.show()
    }

    @MainActor @objc private func openAutomationSettings() {
        AppEnvironment.shared.player.openAutomationSettings()
    }
}
