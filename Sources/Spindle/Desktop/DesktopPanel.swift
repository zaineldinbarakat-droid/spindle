import AppKit

/// A borderless, non-activating panel pinned to the desktop layer.
///
/// Used for both the widgets (just above the desktop icons, below every app window —
/// where macOS's own desktop widgets live) and the backdrop (at wallpaper level, below
/// the icons).
final class DesktopPanel: NSPanel {
    enum Layer {
        /// Above desktop icons, under normal windows. Clickable.
        case widget
        /// Wallpaper level, under the desktop icons. Never receives clicks: Finder's
        /// icon layer sits on top of it.
        case wallpaper

        var level: NSWindow.Level {
            switch self {
            case .widget:
                return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            case .wallpaper:
                return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            }
        }
    }

    init(contentRect: CGRect, layer: Layer) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = layer.level
        // Stationary: Mission Control and Show Desktop leave it where it is, like a widget.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = (layer == .wallpaper)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets SwiftUI move its own borderless window by dragging the background.
///
/// `isMovableByWindowBackground` can't be used: it would also move the window when the
/// user grabs the tonearm. Tracking the cursor in screen coordinates instead of the
/// gesture's translation keeps the drag from chasing the window as it moves.
@MainActor
final class WindowMover: ObservableObject {
    weak var window: NSWindow?
    private var start: (origin: CGPoint, mouse: CGPoint)?

    func drag() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        if start == nil { start = (window.frame.origin, mouse) }
        guard let start else { return }
        window.setFrameOrigin(CGPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                      y: start.origin.y + mouse.y - start.mouse.y))
    }

    func end() {
        start = nil
        // Autosave only writes on move/resize notifications from AppKit itself.
        window?.saveFrame(usingName: window?.frameAutosaveName ?? "")
    }
}
