import AppKit
import Combine

enum MenuBarSection: String, CaseIterable, Identifiable {
    case visible, hidden, alwaysHidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .visible: return "Visible"
        case .hidden: return "Hidden"
        case .alwaysHidden: return "Always Hidden"
        }
    }
}

/// Owns Sleeve's three control items and the hide/reveal state.
///
/// The menu bar, right to left, looks like:
///
///     clock … [visible items] ‹toggle› ‹divider› [hidden items] ‹always divider› [always hidden]
///
/// Up to macOS 26, hiding is done the way every menu bar manager since Hidden Bar does
/// it: a divider's length is set to 10 000 pt, which shoves everything to its left off
/// the screen. macOS 27 caps item width, so there the dividers stay small and
/// `CoverController` paints over the hidden stretch instead.
///
/// Either way the user decides what goes where by ⌘-dragging icons across the
/// dividers, and macOS remembers each divider's position through its autosave name.
@MainActor
final class SectionManager: ObservableObject {
    enum RevealState: Equatable {
        case collapsed
        /// Hidden section showing; Always Hidden still tucked away.
        case hidden
        /// Everything showing.
        case all
    }

    @Published private(set) var state: RevealState = .collapsed
    @Published private(set) var items: [MenuBarItem] = []
    /// Set by automation rules; holds the reveal open regardless of auto-rehide.
    @Published var pinnedByRule: RevealState?
    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()

    private let toggleItem: NSStatusItem
    private let dividerItem: NSStatusItem
    private let alwaysDividerItem: NSStatusItem

    private static let dividerLength: CGFloat = 12
    /// The long-divider trick, where macOS still honours it.
    private static var hideLength: CGFloat { usesCoverHiding ? dividerLength : 10_000 }

    /// macOS 27+: hidden icons are covered, not pushed away. See `CoverController`.
    static let usesCoverHiding: Bool = {
        if #available(macOS 27, *) { return true }
        return false
    }()

    private let settings = SleeveSettings.shared
    private let scanQueue = DispatchQueue(label: "com.spindle.sleeve.scan", qos: .userInitiated)
    private var rehideTimer: Timer?
    private var rescanTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Fired after every reveal-state change, with the new state.
    var onStateChange: ((RevealState) -> Void)?
    /// Left click on the toggle when the Sleeve Bar is on.
    var onToggleClickedForBar: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    init() {
        Self.seedInitialPositionsIfNeeded()

        // Created right-to-left: macOS places each new item to the left of the last.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggleItem.autosaveName = "Sleeve.Toggle"
        dividerItem = NSStatusBar.system.statusItem(withLength: Self.dividerLength)
        dividerItem.autosaveName = "Sleeve.Divider"
        alwaysDividerItem = NSStatusBar.system.statusItem(withLength: Self.dividerLength)
        alwaysDividerItem.autosaveName = "Sleeve.AlwaysDivider"

        // The toggle must never be ⌘-dragged out of existence, or there'd be no way back.
        toggleItem.behavior = []
        dividerItem.behavior = []
        alwaysDividerItem.behavior = []

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Sleeve")
        }
        for (item, label) in [(dividerItem, "Sleeve hidden divider"), (alwaysDividerItem, "Sleeve always-hidden divider")] {
            item.button?.setAccessibilityLabel(label)
            item.button?.imagePosition = .imageOnly
        }

        settings.$toggleIcon.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcons() }
        }.store(in: &cancellables)

        apply(.collapsed, animated: false)

        // Positions move whenever apps launch, quit or resize their items.
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    self?.rescan()
                }
            }
        }
        rescan()
    }

    /// First launch only: put the control items at the left end of the status area,
    /// so every existing icon starts out Visible and nothing vanishes unexpectedly.
    private static func seedInitialPositionsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "NSStatusItem Preferred Position Sleeve.Toggle") == nil else { return }
        // Preferred positions are measured from the right edge of the screen.
        defaults.set(2000, forKey: "NSStatusItem Preferred Position Sleeve.Toggle")
        defaults.set(2010, forKey: "NSStatusItem Preferred Position Sleeve.Divider")
        defaults.set(2020, forKey: "NSStatusItem Preferred Position Sleeve.AlwaysDivider")
    }

    // MARK: - Geometry

    /// Global AppKit frames of our own items, or nil while they're not laid out.
    var toggleFrame: CGRect? { toggleItem.button?.window?.frame }
    var dividerFrame: CGRect? { dividerItem.button?.window?.frame }
    var alwaysDividerFrame: CGRect? { alwaysDividerItem.button?.window?.frame }

    func section(of item: MenuBarItem) -> MenuBarSection {
        guard let divider = dividerFrame, let always = alwaysDividerFrame else { return .visible }
        let x = item.frame.midX
        if x > divider.maxX - 1 { return .visible }
        if x > always.maxX - 1 { return .hidden }
        return .alwaysHidden
    }

    func items(in section: MenuBarSection) -> [MenuBarItem] {
        items.filter { self.section(of: $0) == section }
    }

    /// Left edge of the leftmost icon that is actually on screen — where the empty
    /// stretch of menu bar ends.
    var leftmostVisibleX: CGFloat? {
        let screenMinX = NSScreen.screens.first?.frame.minX ?? 0
        var xs = items.map(\.frame.minX).filter { $0 >= screenMinX }
        if let toggle = toggleFrame { xs.append(toggle.minX) }
        return xs.min()
    }

    // MARK: - Scanning

    func rescan() {
        isAccessibilityTrusted = AXIsProcessTrusted()
        scanQueue.async { [weak self] in
            let found = MenuBarScanner.scan()
            Task { @MainActor in
                guard let self, found != self.items else { return }
                self.items = found
            }
        }
    }

    /// Waits for macOS to lay the bar out again after a length change, then rescans.
    func rescanSoon() async {
        try? await Task.sleep(for: .milliseconds(180))
        await withCheckedContinuation { continuation in
            scanQueue.async { [weak self] in
                let found = MenuBarScanner.scan()
                Task { @MainActor in
                    self?.items = found
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Reveal

    func reveal(_ target: RevealState = .hidden) {
        guard target != .collapsed else { return collapse() }
        apply(target, animated: true)
        scheduleRehide()
    }

    func collapse() {
        if let pinned = pinnedByRule {
            // A rule is holding things open; drop back to that rather than closing.
            if state != pinned { apply(pinned, animated: true) }
            return
        }
        apply(.collapsed, animated: true)
    }

    func toggle() {
        state == .collapsed ? reveal(.hidden) : collapse()
    }

    func toggleAll() {
        state == .all ? collapse() : reveal(.all)
    }

    private func apply(_ new: RevealState, animated: Bool) {
        switch new {
        case .collapsed:
            dividerItem.length = Self.hideLength
            alwaysDividerItem.length = Self.hideLength
        case .hidden:
            dividerItem.length = Self.dividerLength
            alwaysDividerItem.length = Self.hideLength
        case .all:
            dividerItem.length = Self.dividerLength
            alwaysDividerItem.length = Self.dividerLength
        }
        let changed = state != new
        state = new
        updateIcons()
        if changed {
            onStateChange?(new)
            Task { await rescanSoon() }
        }
        if new == .collapsed { rehideTimer?.invalidate() }
    }

    func applyRulePin(_ pin: RevealState?) {
        pinnedByRule = pin
        if let pin {
            if state == .collapsed || (pin == .all && state != .all) { apply(pin, animated: true) }
        } else if state != .collapsed {
            scheduleRehide()
        }
    }

    // MARK: - Auto-rehide

    func scheduleRehide() {
        rehideTimer?.invalidate()
        guard pinnedByRule == nil else { return }
        switch settings.rehideMode {
        case .never:
            return
        case .timed:
            rehideTimer = Timer.scheduledTimer(withTimeInterval: settings.rehideDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if Self.isAnyMenuOpen() { self.scheduleRehide() } else { self.collapse() }
                }
            }
        case .smart:
            // Poll gently; a mouse monitor would fire hundreds of times a second for a
            // decision that only needs to be right within half a second.
            var awaySince: Date?
            rehideTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
                Task { @MainActor in
                    guard let self else { timer.invalidate(); return }
                    if self.isCursorInMenuBarOrBar() || Self.isAnyMenuOpen() {
                        awaySince = nil
                        return
                    }
                    if awaySince == nil { awaySince = .now }
                    if let since = awaySince, Date.now.timeIntervalSince(since) > 0.6 {
                        timer.invalidate()
                        self.collapse()
                    }
                }
            }
        }
    }

    /// Extra rect that counts as "still in the menu bar" — the Sleeve Bar, when open.
    var keepAliveRect: CGRect?

    private func isCursorInMenuBarOrBar() -> Bool {
        let mouse = NSEvent.mouseLocation
        if let keepAliveRect, keepAliveRect.insetBy(dx: -8, dy: -8).contains(mouse) { return true }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return false }
        return mouse.y >= screen.frame.maxY - MenuBarGeometry.height(of: screen) - 4
    }

    /// A status item's menu is open (pop-up menus live at their own window level).
    /// Collapsing then would yank the item out from under its own menu.
    static func isAnyMenuOpen() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.contains { ($0[kCGWindowLayer as String] as? Int) == menuLevel }
    }

    // MARK: - Activating an item

    /// Opens a status item's menu, even if it is currently hidden: the section is
    /// revealed first so the menu appears in the right place, then the item is pressed.
    /// With cover hiding the icon never left its place, so it's pressed where it is
    /// and its menu drops down over the cover.
    func activate(_ item: MenuBarItem) async {
        if Self.usesCoverHiding {
            let fresh = items.first { $0.id == item.id } ?? item
            if !fresh.element.press() {
                ItemMover.click(at: CGPoint(x: fresh.frame.midX, y: fresh.frame.midY))
            }
            return
        }
        let section = self.section(of: item)
        let needed: RevealState = section == .alwaysHidden ? .all : (section == .hidden ? .hidden : state)
        if needed != state && needed != .collapsed {
            apply(needed, animated: true)
            await rescanSoon()
        }
        let fresh = items.first { $0.id == item.id } ?? item
        if !fresh.element.press() {
            ItemMover.click(at: CGPoint(x: fresh.frame.midX, y: fresh.frame.midY))
        }
        scheduleRehide()
    }

    // MARK: - Toggle button

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            if let menu = menuProvider?() {
                toggleItem.menu = menu
                toggleItem.button?.performClick(nil)
                toggleItem.menu = nil
            }
            return
        }
        if event?.modifierFlags.contains(.option) == true {
            toggleAll()
            return
        }
        if settings.useSleeveBar {
            onToggleClickedForBar?()
        } else {
            toggle()
        }
    }

    private func updateIcons() {
        let revealed = state != .collapsed
        let symbol: String
        switch settings.toggleIcon {
        case .dot: symbol = revealed ? "circle" : "circle.fill"
        case .chevron: symbol = revealed ? "chevron.compact.right" : "chevron.compact.left"
        case .sleeve: symbol = revealed ? "opticaldisc" : "smallcircle.filled.circle"
        }
        let config = NSImage.SymbolConfiguration(pointSize: settings.toggleIcon == .dot ? 7 : 13, weight: .semibold)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Sleeve")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        toggleItem.button?.image = image

        // Dividers only show a faint tick while their section is open, so the user can
        // see where to drop icons; collapsed, they're just a long invisible spacer.
        let tick = NSImage(systemSymbolName: "poweron", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .light))
        tick?.isTemplate = true
        dividerItem.button?.image = state == .collapsed ? nil : tick
        alwaysDividerItem.button?.image = state == .all ? tick : nil
        dividerItem.button?.alphaValue = 0.35
        alwaysDividerItem.button?.alphaValue = 0.35
    }

    func tearDown() {
        // Leave the bar as we found it: an expanded divider must not outlive the app.
        dividerItem.length = Self.dividerLength
        alwaysDividerItem.length = Self.dividerLength
        rehideTimer?.invalidate()
        rescanTimer?.invalidate()
    }
}

enum MenuBarGeometry {
    /// Height of the menu bar on `screen` — taller on notched displays.
    static func height(of screen: NSScreen) -> CGFloat {
        let fromVisible = screen.frame.maxY - screen.visibleFrame.maxY
        if fromVisible > 0 { return fromVisible }
        return max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
    }

    static func strip(of screen: NSScreen) -> CGRect {
        let h = height(of: screen)
        return CGRect(x: screen.frame.minX, y: screen.frame.maxY - h, width: screen.frame.width, height: h)
    }
}
