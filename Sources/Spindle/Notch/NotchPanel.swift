import AppKit

/// Borderless, non-activating panel that floats above the menu bar.
final class NotchPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        // Above the menu bar, so the panel can spill over it when open.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Keep the panel out of screenshots of "windows" and out of Mission Control.
        animationBehavior = .none
    }

    // A widget must never take keyboard focus away from whatever the user is doing.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
