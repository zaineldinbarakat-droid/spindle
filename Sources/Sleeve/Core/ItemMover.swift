import AppKit

/// Moves status items between sections by performing the gesture a person would:
/// a ⌘-drag from the icon to just past the target divider.
///
/// There is no API for rearranging other apps' status items. ⌘-drag is the supported
/// way for a *person* to do it, so we synthesize exactly that with CGEvents, then put
/// the cursor back where it was. It needs the Accessibility grant Sleeve already has.
@MainActor
enum ItemMover {
    enum MoveError: Error, LocalizedError {
        case notTrusted, notOnScreen, didNotMove
        var errorDescription: String? {
            switch self {
            case .notTrusted: return "Sleeve needs Accessibility access to move icons."
            case .notOnScreen: return "That icon isn't on screen, so it can't be dragged."
            case .didNotMove: return "macOS didn't accept the move. Try again, or ⌘-drag it by hand."
            }
        }
    }

    /// Converts AppKit global coordinates (bottom-left origin) to CG event space
    /// (top-left origin of the primary display).
    private static func cgPoint(_ p: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    static func click(at point: CGPoint) {
        let p = cgPoint(point)
        let source = CGEventSource(stateID: .hidSystemState)
        let saved = CGEvent(source: nil)?.location
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        if let saved { CGWarpMouseCursorPosition(saved) }
    }

    /// Moves `item` into `section`. Everything is revealed for the duration, because
    /// you can't drag what's off screen.
    static func move(_ item: MenuBarItem, to section: MenuBarSection, using manager: SectionManager) async throws {
        guard AXIsProcessTrusted() else { throw MoveError.notTrusted }
        let previous = manager.state
        manager.reveal(.all)
        await manager.rescanSoon()

        guard let current = manager.items.first(where: { $0.id == item.id }),
              NSScreen.screens.contains(where: { $0.frame.contains(CGPoint(x: current.frame.midX, y: current.frame.midY)) })
        else {
            restore(previous, manager)
            throw MoveError.notOnScreen
        }

        guard let target = dropPoint(for: section, item: current, manager: manager) else {
            restore(previous, manager)
            throw MoveError.didNotMove
        }

        drag(from: CGPoint(x: current.frame.midX, y: current.frame.midY), to: target)
        await manager.rescanSoon()

        let moved = manager.items.first(where: { $0.id == item.id }).map { manager.section(of: $0) == section } ?? false
        restore(previous, manager)
        if !moved { throw MoveError.didNotMove }
    }

    private static func restore(_ state: SectionManager.RevealState, _ manager: SectionManager) {
        state == .collapsed ? manager.collapse() : manager.reveal(state)
    }

    /// Just across the divider that bounds `section` on the right.
    private static func dropPoint(for section: MenuBarSection, item: MenuBarItem,
                                  manager: SectionManager) -> CGPoint? {
        let y = item.frame.midY
        switch section {
        case .visible:
            guard let toggle = manager.toggleFrame else { return nil }
            return CGPoint(x: toggle.maxX + 3, y: y)
        case .hidden:
            guard let divider = manager.dividerFrame else { return nil }
            return CGPoint(x: divider.minX - 3, y: y)
        case .alwaysHidden:
            guard let always = manager.alwaysDividerFrame else { return nil }
            return CGPoint(x: always.minX - 3, y: y)
        }
    }

    private static func drag(from start: CGPoint, to end: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let from = cgPoint(start)
        let to = cgPoint(end)
        let saved = CGEvent(source: nil)?.location

        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: type,
                                mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }

        post(.leftMouseDown, from)
        usleep(60_000)
        // Several intermediate points: the menu bar only starts a drag after it sees
        // real motion, and only re-orders as the cursor passes each neighbour.
        let steps = 14
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y))
            usleep(12_000)
        }
        usleep(80_000)
        post(.leftMouseUp, to)
        usleep(60_000)
        if let saved { CGWarpMouseCursorPosition(saved) }
    }
}
