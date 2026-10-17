import AppKit

/// Every mouse event in the login session, whichever app it's meant for.
///
/// NSEvent's global monitors only see events sent to *other* apps, and the local ones
/// only Sleeve's own, so a hover could slip between them depending on which app was in
/// front — the bar stopped responding while some other app had focus. A listen-only
/// event tap sees everything. It's passive: macOS never waits for it, so it can't slow
/// the cursor down. If the tap can't be created, NSEvent monitors stand in.
@MainActor
final class MouseEvents {
    enum Kind {
        case moved
        case leftDown
        case rightDown
        case rightUp
        case scrolled(dy: CGFloat)
    }

    static let shared = MouseEvents()

    private var handlers: [UUID: (Kind) -> Void] = [:]
    private var tap: CFMachPort?
    private var fallbackMonitors: [Any] = []

    private init() {
        start()
    }

    /// Calls `handler` on the main thread for each mouse event. Keep the token to remove it.
    @discardableResult
    func observe(_ handler: @escaping (Kind) -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    func remove(_ id: UUID?) {
        guard let id else { return }
        handlers[id] = nil
    }

    fileprivate func deliver(_ kind: Kind) {
        for handler in handlers.values { handler(kind) }
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func start() {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                    .leftMouseDown, .rightMouseDown, .rightMouseUp, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                       options: .listenOnly, eventsOfInterest: mask,
                                       callback: mouseTapCallback,
                                       userInfo: Unmanaged.passUnretained(self).toOpaque()) {
            self.tap = tap
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            return
        }
        // No tap (no Accessibility permission yet): both kinds of NSEvent monitor.
        let nsMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                          .leftMouseDown, .rightMouseDown, .rightMouseUp, .scrollWheel]
        let handle: (NSEvent) -> Void = { [weak self] event in
            guard let kind = Self.kind(of: event) else { return }
            MainActor.assumeIsolated { self?.deliver(kind) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: nsMask, handler: handle) {
            fallbackMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: nsMask, handler: { handle($0); return $0 }) {
            fallbackMonitors.append(local)
        }
    }

    /// Tries the tap again once Accessibility has been granted.
    func retryTapIfNeeded() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        fallbackMonitors.forEach { NSEvent.removeMonitor($0) }
        fallbackMonitors.removeAll()
        start()
    }

    nonisolated static func kind(of event: NSEvent) -> Kind? {
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged: return .moved
        case .leftMouseDown: return .leftDown
        case .rightMouseDown: return .rightDown
        case .rightMouseUp: return .rightUp
        case .scrollWheel: return .scrolled(dy: event.scrollingDeltaY)
        default: return nil
        }
    }
}

private func mouseTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let events = Unmanaged<MouseEvents>.fromOpaque(userInfo).takeUnretainedValue()
    // The run loop source is on the main run loop, so this is the main thread.
    MainActor.assumeIsolated {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            events.reenable()
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            events.deliver(.moved)
        case .leftMouseDown:
            events.deliver(.leftDown)
        case .rightMouseDown:
            events.deliver(.rightDown)
        case .rightMouseUp:
            events.deliver(.rightUp)
        case .scrollWheel:
            let dy = NSEvent(cgEvent: event)?.scrollingDeltaY ?? 0
            events.deliver(.scrolled(dy: dy))
        default:
            break
        }
    }
    return Unmanaged.passUnretained(event)
}
