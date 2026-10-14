import AppKit
import SwiftUI

/// A plain `NSWindow` rather than a SwiftUI `Settings` scene, because an accessory app
/// with no Dock icon has no reliable way to bring that scene forward.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView()
            .environmentObject(AppEnvironment.shared.player)
            .environmentObject(AppEnvironment.shared.notch)
            .environmentObject(AppEnvironment.shared.timer)
            .environmentObject(AppEnvironment.shared.desktop)

        let created = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        created.title = "Spindle Settings"
        created.contentView = NSHostingView(rootView: view)
        created.isReleasedWhenClosed = false
        created.center()

        window = created
        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)
    }
}
