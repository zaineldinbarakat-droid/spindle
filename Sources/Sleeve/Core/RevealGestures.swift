import AppKit

/// Hover, scroll and click-on-empty-bar reveal.
///
/// "Empty" means the stretch of menu bar between the end of the app menus and the
/// first status icon — never over a menu title, an icon, the notch, or Spindle's pill,
/// so a reveal can't fire while the user is reaching for something else.
@MainActor
final class RevealGestures {
    private unowned let sections: SectionManager
    private unowned let spindle: SpindleBridge
    private let settings = SleeveSettings.shared
    private var monitors: [Any] = []
    private var appMenusEnd: CGFloat = 0
    private var lastScrollToggle = Date.distantPast

    /// Called instead of an in-place reveal when the Sleeve Bar is enabled.
    var showBar: (() -> Void)?
    var hideBar: (() -> Void)?

    init(sections: SectionManager, spindle: SpindleBridge) {
        self.sections = sections
        self.spindle = spindle

        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in self?.mouseMoved() }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let dy = event.scrollingDeltaY
            Task { @MainActor in self?.scrolled(dy) }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.clicked() }
        } as Any)
        // On release, not press: a menu opened on the press is closed again by the
        // release that follows a moment later — it flashed up and vanished.
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .rightMouseUp) { [weak self] _ in
            Task { @MainActor in self?.twoFingerClicked() }
        } as Any)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAppMenus() }
        }
        refreshAppMenus()
    }

    private func refreshAppMenus() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let end = MenuBarScanner.appMenusMaxX() ?? 0
            Task { @MainActor in self?.appMenusEnd = end }
        }
    }

    private func isOverEmptyBar(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first,
              point.x >= screen.frame.minX, point.x <= screen.frame.maxX,
              MenuBarGeometry.isInMenuBar(point) else {
            return false
        }
        if spindle.owns(point) { return false }
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0, point.x > l.maxX - 4, point.x < r.minX + 4 {
            return false
        }
        let start = appMenusEnd + 8
        // Hide-all (Ice-style): the whole right side of the bar is the trigger —
        // what's left there is just Sleeve and Apple's own icons. It doesn't depend on
        // where the active app's menus end: some apps report menus far beyond their
        // real extent (or spill past the notch), which shrank the zone to nothing and
        // made hover dead whenever such an app was in front.
        if settings.hideAllApps {
            if let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
                return point.x > right.minX + 4
            }
            return point.x > screen.frame.midX
        }
        let end = (sections.leftmostVisibleX ?? screen.frame.maxX) - 8
        return point.x > start && point.x < end
    }

    private func isInBar(_ point: CGPoint) -> Bool {
        MenuBarGeometry.isInMenuBar(point) && !spindle.owns(point)
    }

    private func reveal() {
        if settings.useSleeveBar { return showBar?() ?? () }
        sections.reveal(settings.hideAllApps ? .all : .hidden)
    }

    private func conceal() {
        if settings.useSleeveBar { return hideBar?() ?? () }
        sections.collapse()
    }

    private func mouseMoved() {
        let point = NSEvent.mouseLocation
        // Hovering Sleeve's own icon. Checked here, from the global cursor stream,
        // because on macOS 27 the cursor over a status item is reported to the global
        // monitor while the button's own tracking area is unreliable.
        let overIcon = sections.toggleFrame.map { $0.insetBy(dx: -1, dy: -6).contains(point) } ?? false
        if overIcon != sections.isHoveringIcon {
            overIcon ? sections.iconHoverBegan() : sections.iconHoverEnded()
        }
        // Leaving the bar re-arms hover (see SectionManager.isHoverArmed).
        if !MenuBarGeometry.isInMenuBar(point, margin: 6) {
            sections.isHoverArmed = true
            return
        }
        guard settings.revealOnHover, sections.isHoverArmed,
              sections.state == .collapsed, isOverEmptyBar(point) else { return }
        // No dwell: reaching the bar is enough.
        reveal()
    }

    /// Two-finger click on an empty stretch of the bar shows or hides the hidden apps.
    /// Never over an icon: other apps' icons keep their own right-click menus.
    private func twoFingerClicked() {
        guard settings.revealOnTwoFingerClick else { return }
        let point = NSEvent.mouseLocation
        // On macOS 27 a secondary click on Sleeve's own icon arrives here too (the
        // button often never sees it). On the icon it opens Sleeve's menu; anywhere
        // else on the empty bar it shows or hides.
        if let icon = sections.toggleFrame, icon.insetBy(dx: -2, dy: -6).contains(point) {
            sections.showMenu()
            return
        }
        guard isInBar(point), !isOverAnyIcon(point), point.x > appMenusEnd + 8 else { return }
        if let screen = NSScreen.screens.first, let l = screen.auxiliaryTopLeftArea,
           let r = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0,
           point.x > l.maxX - 4, point.x < r.minX + 4 {
            return
        }
        sections.toggleForUser()
    }

    private func isOverAnyIcon(_ point: CGPoint) -> Bool {
        sections.items.contains { item in
            sections.isLive(item) && !item.isOverflowed && item.frame.insetBy(dx: -2, dy: -4).contains(point)
        }
    }

    private func scrolled(_ dy: CGFloat) {
        guard settings.revealOnScroll, abs(dy) > 2, isInBar(NSEvent.mouseLocation) else { return }
        // One scroll gesture produces dozens of events; act once per gesture.
        guard Date.now.timeIntervalSince(lastScrollToggle) > 0.5 else { return }
        lastScrollToggle = .now
        // Natural scrolling: swipe down pulls the hidden items out, swipe up tucks them in.
        if dy < 0 { reveal() } else { conceal() }
    }

    private func clicked() {
        guard settings.revealOnEmptyClick, isOverEmptyBar(NSEvent.mouseLocation) else { return }
        if sections.state == .collapsed { reveal() } else { conceal() }
    }

    func tearDown() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}
