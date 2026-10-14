import AppKit
import Combine
import SwiftUI

/// Owns everything Spindle puts on the desktop: the widgets, the wallpaper-level
/// backdrop, and the full-screen turntable.
@MainActor
final class DesktopController: ObservableObject {
    private let player: PlayerManager
    private let timer: PomodoroTimer

    private var widgets: [DesktopWidgetKind: DesktopPanel] = [:]
    private var backdrop: DesktopPanel?
    private var fullScreen: FullScreenWindow?
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var visibleWidgets: Set<DesktopWidgetKind> = []
    @Published private(set) var isBackdropVisible = false
    @Published private(set) var isFullScreenVisible = false

    init(player: PlayerManager, timer: PomodoroTimer) {
        self.player = player
        self.timer = timer
    }

    /// Restores whatever was on screen at last quit.
    func restore() {
        for kind in DesktopWidgetKind.allCases where Defaults.bool(kind.defaultsKey, default: false) {
            showWidget(kind)
        }
        if Defaults.bool(.desktopBackdropVisible, default: false) {
            setBackdrop(visible: true)
        }

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.screensChanged() }
            .store(in: &cancellables)
    }

    func tearDown() {
        widgets.values.forEach { $0.orderOut(nil) }
        backdrop?.orderOut(nil)
        fullScreen?.close()
    }

    private func environment<V: View>(_ view: V) -> some View {
        view
            .environmentObject(player)
            .environmentObject(timer)
    }

    // MARK: - Widgets

    func isWidgetVisible(_ kind: DesktopWidgetKind) -> Bool { visibleWidgets.contains(kind) }

    func toggleWidget(_ kind: DesktopWidgetKind) {
        isWidgetVisible(kind) ? hideWidget(kind) : showWidget(kind)
    }

    func showWidget(_ kind: DesktopWidgetKind) {
        if let existing = widgets[kind] {
            existing.orderFrontRegardless()
            return
        }

        let size = kind.size
        let panel = DesktopPanel(contentRect: CGRect(origin: defaultOrigin(for: kind), size: size),
                                 layer: .widget)
        let mover = WindowMover()
        mover.window = panel

        let content: AnyView
        switch kind {
        case .record: content = AnyView(RecordWidgetView())
        case .turntable: content = AnyView(TurntableWidgetView())
        }
        let root = WidgetChrome(mover: mover, onRemove: { [weak self] in self?.hideWidget(kind) }) {
            content
        }
        let hosting = NSHostingView(rootView: environment(root))
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.contentView = hosting

        // Remembers where the user dragged it. Must come after the content is set, and
        // `setFrameAutosaveName` restores a saved frame on its own if there is one.
        panel.setFrameAutosaveName("SpindleWidget.\(kind.rawValue)")
        panel.setContentSize(size)
        keepOnScreen(panel)
        panel.orderFrontRegardless()

        widgets[kind] = panel
        visibleWidgets.insert(kind)
        Defaults.set(kind.defaultsKey, true)
    }

    func hideWidget(_ kind: DesktopWidgetKind) {
        widgets[kind]?.orderOut(nil)
        widgets[kind] = nil
        visibleWidgets.remove(kind)
        Defaults.set(kind.defaultsKey, false)
    }

    /// Top-right of the main screen, stacked, out of the way of the menu bar.
    private func defaultOrigin(for kind: DesktopWidgetKind) -> CGPoint {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let x = visible.maxX - kind.size.width - 24
        switch kind {
        case .record:
            return CGPoint(x: x, y: visible.maxY - kind.size.height - 24)
        case .turntable:
            return CGPoint(x: x, y: visible.maxY - DesktopWidgetKind.record.size.height - kind.size.height - 40)
        }
    }

    /// A saved position from a since-disconnected display would leave the widget
    /// invisible; pull it back onto a screen that exists.
    private func keepOnScreen(_ panel: NSWindow) {
        let frame = panel.frame
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return }
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        panel.setFrameOrigin(CGPoint(x: visible.maxX - frame.width - 24,
                                     y: visible.maxY - frame.height - 24))
    }

    // MARK: - Backdrop

    func toggleBackdrop() { setBackdrop(visible: !isBackdropVisible) }

    func setBackdrop(visible: Bool) {
        Defaults.set(.desktopBackdropVisible, visible)
        isBackdropVisible = visible

        guard visible else {
            backdrop?.orderOut(nil)
            backdrop = nil
            return
        }
        guard backdrop == nil else { return }

        let frame = backdropScreen.frame
        let panel = DesktopPanel(contentRect: frame, layer: .wallpaper)
        let hosting = NSHostingView(rootView: environment(BackdropView(isInteractive: false)))
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        panel.contentView = hosting
        panel.orderFrontRegardless()
        backdrop = panel
    }

    private var backdropScreen: NSScreen {
        // The built-in display if there is one: that is where the notch, and the
        // user's eyes, usually are.
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func screensChanged() {
        backdrop?.setFrame(backdropScreen.frame, display: true)
        widgets.values.forEach(keepOnScreen)
    }

    // MARK: - Full screen

    func toggleFullScreen() {
        if let fullScreen {
            fullScreen.exit()
            return
        }

        let window = FullScreenWindow(screen: backdropScreen)
        window.contentView = NSHostingView(rootView: environment(BackdropView(isInteractive: true)))
        window.onClose = { [weak self] in
            self?.fullScreen = nil
            self?.isFullScreenVisible = false
        }
        fullScreen = window
        isFullScreenVisible = true

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }
}

/// A plain titled window that goes straight into its own full-screen space. Escape
/// (or ⌘W) leaves full screen and closes it.
final class FullScreenWindow: NSWindow, NSWindowDelegate {
    var onClose: (() -> Void)?
    private var isClosing = false

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        title = "Spindle"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isReleasedWhenClosed = false
        backgroundColor = .black
        collectionBehavior = [.fullScreenPrimary]
        delegate = self
    }

    override func cancelOperation(_ sender: Any?) { exit() }

    override func performClose(_ sender: Any?) { exit() }

    func exit() {
        guard !isClosing else { return }
        isClosing = true
        if styleMask.contains(.fullScreen) {
            // Close once the space animation has finished, or AppKit leaves an empty
            // black space behind.
            toggleFullScreen(nil)
        } else {
            close()
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
    }
}
