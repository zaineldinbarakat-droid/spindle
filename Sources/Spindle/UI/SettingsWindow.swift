import AppKit
import SwiftUI

/// A plain `NSWindow` rather than a SwiftUI `Settings` scene, because an accessory app
/// with no Dock icon has no reliable way to bring that scene forward.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

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
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        created.title = "Spindle Settings"
        created.contentView = NSHostingView(rootView: view)
        created.isReleasedWhenClosed = false
        created.center()

        window = created
        // Closed, Settings lets go of its views. Kept alive, they redrew with every tick
        // of the song and the timer (and spun the record preview), with nobody looking.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: created, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
                closeObserver = nil
                window?.contentView = nil
                window = nil
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)
    }
}
