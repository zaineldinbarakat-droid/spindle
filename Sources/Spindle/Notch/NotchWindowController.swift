import AppKit
import SwiftUI
import Combine
import SpindleSync

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
    private let timer: PomodoroTimer

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalClickMonitor: Any?
    private var scrollMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    /// Delays closing slightly so a fast diagonal exit doesn't flap the panel.
    private var closeWorkItem: DispatchWorkItem?

    init(viewModel: NotchViewModel, player: PlayerManager, timer: PomodoroTimer) {
        self.viewModel = viewModel
        self.player = player
        self.timer = timer
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

        installSync()
    }

    // MARK: - Sleeve sync

    private var syncObservers: [NSObjectProtocol] = []

    private func installSync() {
        syncObservers.append(SyncChannel.observe(SyncChannel.requestSpindleState) { [weak self] _ in
            Task { @MainActor in self?.publishState() }
        })
        syncObservers.append(SyncChannel.observe(SyncChannel.zenMode) { [weak self] info in
            Task { @MainActor in self?.setZen(info["enabled"] as? Bool ?? false) }
        })
        syncObservers.append(SyncChannel.observe(SyncChannel.sleeveTerminated) { [weak self] _ in
            Task { @MainActor in self?.setZen(false) }
        })
        // One dropdown at a time: Sleeve's bar opening closes our panel.
        syncObservers.append(SyncChannel.observe(SyncChannel.sleeveBar) { [weak self] info in
            Task { @MainActor in
                guard let self, info["open"] as? Bool == true else { return }
                self.closeWorkItem?.cancel()
                self.closeWorkItem = nil
                self.viewModel.collapse()
            }
        })

        // Anything that changes what we occupy is worth telling Sleeve about.
        Publishers.CombineLatest3(viewModel.statePublisher.removeDuplicates(),
                                  viewModel.metricsPublisher.removeDuplicates(),
                                  viewModel.$isZenHidden.removeDuplicates())
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.publishState() }
            .store(in: &cancellables)
        // A new song's colour, for Sleeve's "Album" menu bar tint.
        player.$accent.removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.publishState() }
            .store(in: &cancellables)
        player.$snapshot.map(\.hasTrack).removeDuplicates()
            .merge(with: timer.runningPublisher.removeDuplicates())
            .sink { [weak self] _ in self?.publishState() }
            .store(in: &cancellables)
    }

    private static func components(of color: Color) -> [Double]? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map(Double.init)
    }

    private func setZen(_ enabled: Bool) {
        if enabled { viewModel.collapse() }
        viewModel.isZenHidden = enabled
    }

    private func publishState() {
        let metrics = viewModel.metrics
        let pillVisible = !viewModel.isZenHidden && (player.snapshot.hasTrack || timer.isActive || viewModel.isExpanded)
        let state = SpindleState(pillFrame: pillVisible ? metrics.hoverZone() : .zero,
                                 hoverZone: viewModel.openOnHover ? metrics.hoverZone() : .zero,
                                 panelFrame: viewModel.isExpanded ? metrics.liveZone() : .zero,
                                 isExpanded: viewModel.isExpanded,
                                 isZenHidden: viewModel.isZenHidden,
                                 accent: Self.components(of: player.accent))
        SyncChannel.post(SyncChannel.spindleState, state.userInfo)
    }

    private func rebuildPanel() {
        let metrics = NotchMetrics.current()
        viewModel.updateMetrics(metrics)

        if panel == nil {
            let created = NotchPanel(contentRect: metrics.windowFrame())
            let root = NotchRootView()
                .environmentObject(viewModel)
                .environmentObject(player)
                .environmentObject(timer)
            let hosting = NSHostingView(rootView: root)
            // Layer-backed so the morph animates on the GPU compositor.
            hosting.wantsLayer = true
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

        // Two-finger swipes over the open panel page between the player and the timer.
        // Scrolls go to the window under the cursor, so a local monitor sees them.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handleScroll(event) } ? nil : event
        }

        // While collapsed the panel is click-through, so clicks on the notch reach us
        // only through a global monitor.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.handleGlobalClick() }
        }
    }

    // MARK: - Swiping between tabs

    /// Whether the current gesture is a horizontal swipe we're handling: decided on its
    /// first real movement, so a vertical scroll is never mistaken for one.
    private var swipeIsHorizontal: Bool?
    private var swipeTravel: CGFloat = 0
    /// Recent movement, to measure how fast the fingers were going on release.
    private var swipeSamples: [(time: TimeInterval, dx: CGFloat)] = []

    /// Pages the way macOS does: the tabs follow the fingers one to one, resist past
    /// the ends with the system's rubber-band curve, and on release go to the next page
    /// if you'd dragged a third of the way — or flicked toward it, however short the
    /// flick. Returns true when the event was used.
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard viewModel.isExpanded, event.window === panel else { return false }
        // The glide after a swipe we handled: swallow it.
        if event.momentumPhase != [] { return swipeIsHorizontal == true }

        // A mouse wheel (no phases): one horizontal notch turns the page.
        if event.phase == [] {
            guard !event.hasPreciseScrollingDeltas,
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
            turnPage(toward: event.scrollingDeltaX < 0 ? .focus : .player)
            return true
        }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            swipeIsHorizontal = nil
            swipeTravel = 0
            swipeSamples.removeAll()
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            guard swipeIsHorizontal == true else { return false }
            settleSwipe()
            return true
        }

        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        if swipeIsHorizontal == nil {
            guard abs(dx) + abs(dy) >= 1 else { return false }
            swipeIsHorizontal = abs(dx) > abs(dy)
        }
        guard swipeIsHorizontal == true else { return false }
        swipeTravel += dx
        swipeSamples.append((event.timestamp, dx))
        swipeSamples.removeAll { event.timestamp - $0.time > 0.08 }
        viewModel.swipeOffset = rubberBanded(swipeTravel)
        return true
    }

    /// Following the fingers one to one, except past either end, where the page gives
    /// way less and less — the same curve macOS uses at a scroll view's edge.
    private func rubberBanded(_ travel: CGFloat) -> CGFloat {
        let width = viewModel.metrics.panelSize.width
        let pastEnd = (viewModel.tab == .player && travel > 0) || (viewModel.tab == .focus && travel < 0)
        guard pastEnd else { return max(min(travel, width), -width) }
        let x = abs(travel)
        return (travel < 0 ? -1 : 1) * (1 - 1 / (x * 0.55 / width + 1)) * width
    }

    /// Finger speed over the last few hundredths of a second, in points per second.
    private var swipeVelocity: CGFloat {
        guard let first = swipeSamples.first, let last = swipeSamples.last, last.time > first.time else { return 0 }
        return swipeSamples.reduce(0) { $0 + $1.dx } / CGFloat(last.time - first.time)
    }

    private func settleSwipe() {
        let width = viewModel.metrics.panelSize.width
        let offset = viewModel.swipeOffset
        let velocity = swipeVelocity
        var target = viewModel.tab
        if viewModel.tab == .player && (offset < -width / 3 || (velocity < -220 && offset < 0)) { target = .focus }
        if viewModel.tab == .focus && (offset > width / 3 || (velocity > 220 && offset > 0)) { target = .player }
        withAnimation(NotchViewModel.pageSpring) {
            viewModel.tab = target
            viewModel.swipeOffset = 0
        }
    }

    private var lastPageTurn = Date.distantPast

    private func turnPage(toward tab: NotchViewModel.Tab) {
        // A wheel sends several notches per flick: one page per flick.
        guard Date.now.timeIntervalSince(lastPageTurn) > 0.35, viewModel.tab != tab else { return }
        lastPageTurn = .now
        withAnimation(NotchViewModel.pageSpring) { viewModel.tab = tab }
    }

    /// Hover already opens the panel, so this matters when hover-to-open is off: a
    /// click on the little record opens the music app, anywhere else on the notch
    /// opens the panel, and a click elsewhere on screen closes it.
    private func handleGlobalClick() {
        let location = NSEvent.mouseLocation
        let metrics = viewModel.metrics

        if viewModel.isExpanded {
            if !viewModel.openOnHover && !metrics.liveZone().contains(location) {
                viewModel.collapse()
            }
            return
        }

        guard metrics.hoverZone().contains(location) else { return }
        if metrics.collapsedRecordZone().contains(location) {
            player.openSourceApp()
        } else if !viewModel.openOnHover {
            panel?.ignoresMouseEvents = false
            viewModel.expand()
        }
    }

    /// Drops the panel open for a few seconds on a given tab, then tucks it away
    /// again unless the cursor has moved onto it.
    func peek(tab: NotchViewModel.Tab, for seconds: TimeInterval = 4) {
        viewModel.tab = tab
        closeWorkItem?.cancel()
        closeWorkItem = nil
        panel?.ignoresMouseEvents = false
        viewModel.expand()

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.viewModel.isExpanded else { return }
            guard !self.viewModel.metrics.liveZone().contains(NSEvent.mouseLocation) else { return }
            self.viewModel.collapse()
        }
    }

    /// When the panel last opened and closed — the hysteresis that keeps a cursor
    /// sitting on the boundary from flickering it open and shut.
    private var openedAt = Date.distantPast
    private var closedAt = Date.distantPast

    private func handleMouseMoved() {
        guard viewModel.openOnHover, !viewModel.isZenHidden else { return }
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
            // Just closed: don't bounce straight back open while the cursor is
            // crossing the edge on its way out.
            guard Date.now.timeIntervalSince(closedAt) > 0.18 else { return }
            closeWorkItem?.cancel()
            closeWorkItem = nil
            panel?.ignoresMouseEvents = false
            openedAt = .now
            viewModel.expand()
        }
    }

    private func scheduleClose() {
        guard closeWorkItem == nil else { return }
        // Never close in the first moments after opening: the panel is still growing
        // under the cursor, and a quick graze shouldn't snap it shut mid-animation.
        let minimumOpen = max(0.25 - Date.now.timeIntervalSince(openedAt), 0)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeWorkItem = nil
            // Re-check: the cursor may have come back while we waited.
            guard !self.viewModel.metrics.liveZone().contains(NSEvent.mouseLocation) else { return }
            self.closedAt = .now
            self.viewModel.collapse()
        }
        closeWorkItem = item
        // A short grace (Settings → Panel → Closing), enough to forgive the cursor
        // slipping off the edge.
        DispatchQueue.main.asyncAfter(deadline: .now() + viewModel.closeDelay + minimumOpen, execute: item)
    }

    // MARK: - Teardown

    func tearDown() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        globalClickMonitor = nil
        globalMouseMonitor = nil
        localMouseMonitor = nil
        cancellables.removeAll()
        syncObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        syncObservers.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }
}
