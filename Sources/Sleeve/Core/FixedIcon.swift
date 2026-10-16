import AppKit

/// Sleeve's icon, drawn in a window of its own at a fixed spot in the menu bar.
///
/// A status item can't hold its place on macOS 27: MenuBarAgent lays the bar out
/// right to left, Sleeve's item is created at the left end, and every app revealed to
/// its right shoves it further left — then hiding pulls it all the way back. There is
/// no API to choose an item's position (preferred positions are ignored, synthesized
/// ⌘-drags rejected). So the real status item shrinks to an invisible zero-width
/// placeholder, and the icon lives here instead: at the left end of the area where
/// apps appear, just clear of the notch and Spindle's pill. Revealed apps fill in to
/// its right; it never moves.
@MainActor
final class FixedIconController {
    let panel: FixedIconPanel
    let host: FixedIconHostView

    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    static let size = CGSize(width: 28, height: 24)

    init(iconView: NSView) {
        panel = FixedIconPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        host = FixedIconHostView(frame: CGRect(origin: .zero, size: Self.size))
        panel.contentView = host

        iconView.removeFromSuperview()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])

        host.onEnter = { [weak self] in self?.onEnter?() }
        host.onExit = { [weak self] in self?.onExit?() }
        host.onClick = { [weak self] in self?.onClick?() }
        host.onSecondaryClick = { [weak self] in self?.onSecondaryClick?() }

        place()
        panel.orderFrontRegardless()
    }

    /// The fixed spot, in global AppKit coordinates.
    var frame: CGRect { panel.frame }

    /// Just right of the notch and of the strip Spindle's pill takes beside it (whether
    /// or not the pill is showing, so the icon doesn't move when music stops). On a
    /// display without a notch: a little right of centre.
    func place() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first else { return }
        let bar = MenuBarGeometry.strip(of: screen)
        let x: CGFloat
        if let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            x = right.minX + Self.spindleWingClearance
        } else {
            x = screen.frame.midX + 40
        }
        panel.setFrame(CGRect(x: x, y: bar.midY - Self.size.height / 2,
                              width: Self.size.width, height: Self.size.height), display: true)
    }

    /// Spindle's collapsed pill reaches 64 pt right of the notch; Sleeve keeps a 10 pt
    /// margin around it, and the icon a little more.
    static let spindleWingClearance: CGFloat = 64 + 16

    func show(_ visible: Bool) {
        visible ? panel.orderFrontRegardless() : panel.orderOut(nil)
    }
}

final class FixedIconPanel: NSPanel {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        // In the menu bar with the status items, under Zen and Spindle's notch panel.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Menu bar icons follow the bar's light/dark appearance, not the app's.
        appearance = NSAppearance(named: .vibrantDark)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hover and clicks for the fixed icon. Being our own window, enter/exit and clicks
/// arrive reliably — unlike a status item's tracking area on macOS 27.
final class FixedIconHostView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }

    override func mouseUp(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onSecondaryClick?() } else { onClick?() }
    }

    override func rightMouseUp(with event: NSEvent) { onSecondaryClick?() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
