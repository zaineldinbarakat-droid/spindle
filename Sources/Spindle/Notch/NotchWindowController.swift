import AppKit
import SwiftUI
import Combine

/// Keeps one `NotchPanel` alive on the notch screen and decides when it opens.
///
/// The panel is always at its full expanded size; we never resize it. Instead it is made
/// click-through while collapsed, so it doesn't swallow menu-bar clicks, and the SwiftUI
/// content animates the visible shape. Resizing a window every time the cursor grazed the
/// notch produced visible tearing, which is why hit-testing carries the state instead.
@MainActor
final class NotchWindowController {

    private var panel: NotchPanel?
    private let viewModel: NotchViewModel
    private let player: PlayerManager

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    /// Delays closing slightly so a fast diagonal exit doesn't flap the panel.
    private var closeWorkItem: DispatchWorkItem?

    init(viewModel: NotchViewModel, player: PlayerManager) {
        self.viewModel = viewModel
        self.player = player
    }

    // MARK: - Setup

    func show() {
        rebuildPanel()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildPanel() }
            .store(in: &cancellables)

        // Re-place the panel when the active space changes; `canJoinAllSpaces` keeps it
        // visible but the notch screen can differ between spaces on multi-display setups.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.repositionPanel() }
            .store(in: &cancellables)

        installMouseMonitors()

        viewModel.statePublisher
            .removeDuplicates()
            .sink { [weak self] state in
                self?.panel?.ignoresMouseEvents = (state == .collapsed)
            }
            .store(in: &cancellables)
    }

    private func rebuildPanel() {
        let metrics = NotchMetrics.current()
        viewModel.updateMetrics(metrics)

        if panel == nil {
            let created = NotchPanel(contentRect: metrics.windowFrame())
            let root = NotchRootView()
                .environmentObject(viewModel)
                .environmentObject(player)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = CGRect(origin: .zero, size: metrics.windowFrame().size)
            created.contentView = hosting
            created.ignoresMouseEvents = true
            created.orderFrontRegardless()
            panel = created
        } else {
            repositionPanel()
        }
    }

    private func repositionPanel() {
        guard let panel else { return }
        let metrics = NotchMetrics.current()
        viewModel.updateMetrics(metrics)
        panel.setFrame(metrics.windowFrame(), display: true)
        panel.orderFrontRegardless()
    }

    // MARK: - Hover tracking

    /// Global monitors see the cursor while another app is frontmost, which is the normal
    /// case for a widget; the local monitor covers the moments we are frontmost ourselves.
    private func installMouseMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            Task { @MainActor in self?.handleMouseMoved() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            Task { @MainActor in self?.handleMouseMoved() }
            return event
        }
    }

    private func handleMouseMoved() {
        guard viewModel.openOnHover else { return }
        let location = NSEvent.mouseLocation
        let metrics = viewModel.metrics

        if viewModel.isExpanded {
            if !metrics.liveZone().contains(location) {
                scheduleClose()
            } else {
                closeWorkItem?.cancel()
                closeWorkItem = nil
            }
        } else if metrics.hoverZone().contains(location) {
            closeWorkItem?.cancel()
            closeWorkItem = nil
            panel?.ignoresMouseEvents = false
            viewModel.expand()
        }
    }

    private func scheduleClose() {
        guard closeWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeWorkItem = nil
            // Re-check: the cursor may have come back while we waited.
            guard !self.viewModel.metrics.liveZone().contains(NSEvent.mouseLocation) else { return }
            self.viewModel.collapse()
        }
        closeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: item)
    }

    // MARK: - Teardown

    func tearDown() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        cancellables.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }
}
