import AppKit
import Combine
import SwiftUI

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
    /// Lower is more visible; an app with icons in several sections takes the lowest.
    var rank: Int {
        switch self {
        case .visible: return 0
        case .hidden: return 1
        case .alwaysHidden: return 2
        }
    }
}

/// Owns Sleeve's three control items and the hide/reveal state.
///
/// The menu bar, right to left, looks like:
///
///     clock … [visible items] ‹toggle› │ [hidden items] │ [always hidden]
///
/// The user decides what goes where by ⌘-dragging icons across the │ dividers, and
/// macOS remembers each divider's position through its autosave name. How the
/// hidden sections are actually hidden depends on the system — see `HidingMethod`.
@MainActor
final class SectionManager: ObservableObject {
    enum RevealState: Equatable {
        case collapsed
        /// Hidden section showing; Always Hidden still tucked away.
        case hidden
        /// Everything showing.
        case all
    }

    enum HidingMethod: Equatable {
        /// macOS 14–26: a divider stretched to 10 000 pt shoves its neighbours off
        /// the screen, the technique every menu bar manager has used since Hidden Bar.
        case pushOffscreen
        /// macOS 27: MenuBarAgent removes the hidden apps' icons and reflows the bar.
        case native
        /// macOS 27 fallback: hidden icons are painted over. See `CoverController`.
        case cover

        var title: String {
            switch self {
            case .pushOffscreen: return "Classic (icons pushed off screen)"
            case .native: return "Native (icons removed, bar reflows)"
            case .cover: return "Cover (icons painted over)"
            }
        }
    }

    @Published private(set) var state: RevealState = .collapsed
    @Published private(set) var items: [MenuBarItem] = [] {
        didSet {
            updateSectionCache()
            rememberOverflow()
            reapplyIfSomethingSlippedThrough()
            offerPlacementTipIfNeeded()
        }
    }
    /// Set by automation rules; holds the reveal open regardless of auto-rehide.
    @Published var pinnedByRule: RevealState?
    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()
    /// Native hiding failed this session (message for Settings); Sleeve has fallen back.
    @Published private(set) var nativeFailure: String?

    private let toggleItem: NSStatusItem
    private let dividerItem: NSStatusItem
    private let alwaysDividerItem: NSStatusItem

    private static let dividerLength: CGFloat = 12
    private static let pushLength: CGFloat = 10_000

    /// macOS 27 moved status item layout into MenuBarAgent: the 10 000 pt divider no
    /// longer pushes anything (measured: 20 pt) and synthesized ⌘-drags are ignored.
    static let isModernMenuBar: Bool = {
        if #available(macOS 27, *) { return true }
        return false
    }()

    var method: HidingMethod {
        guard Self.isModernMenuBar else { return .pushOffscreen }
        if settings.useNativeHiding, nativeFailure == nil, isAccessibilityTrusted, NativeVisibility.isAvailable {
            return .native
        }
        return .cover
    }

    private let settings = SleeveSettings.shared
    private let scanQueue = DispatchQueue(label: "com.spindle.sleeve.scan", qos: .userInitiated)
    private var rehideTimer: Timer?
    private var rescanTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Native hiding state.
    private let native = NativeVisibility()
    private var restriction: NativeVisibility.Restriction?
    /// Bumped whenever a pending native change must no longer win.
    private var nativeGeneration = 0
    /// Section of every icon, last read while that icon was actually in the bar.
    /// Needed because an icon macOS has removed reports a stale position.
    private var itemSections: [String: MenuBarSection] = [:]

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
            installIconView(in: button)
            // Enter/exit events still reach a status item's button on macOS 27, even
            // though MenuBarAgent draws it (checked with a test item).
            button.addTrackingArea(NSTrackingArea(rect: .zero,
                                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                  owner: iconHover, userInfo: nil))
        }
        for (item, label) in [(dividerItem, "Sleeve hidden divider"), (alwaysDividerItem, "Sleeve always-hidden divider")] {
            item.button?.setAccessibilityLabel(label)
            item.button?.imagePosition = .imageOnly
        }

        settings.$toggleIcon.combineLatest(settings.$customIconData).sink { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateIcons() }
        }.store(in: &cancellables)
        // Sleeve's icon is always in the bar.
        toggleItem.isVisible = true
        iconHover.onEnter = { [weak self] in self?.iconHoverBegan() }
        iconHover.onExit = { [weak self] in self?.iconHoverEnded() }
        // Changing how or what to hide re-applies the current state the new way.
        Publishers.Merge4(settings.$useNativeHiding.dropFirst().map { _ in () },
                          settings.$hideAllApps.dropFirst().map { _ in () },
                          settings.$alwaysShownBundles.dropFirst().map { _ in () },
                          settings.$hiddenSectionBundles.dropFirst().map { _ in () })
            .sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.releaseRestriction()
                self.apply(self.state, force: true)
            }
        }.store(in: &cancellables)

        // Positions move whenever apps launch, quit or resize their items.
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                self?.appLaunched(app?.bundleIdentifier)
            }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                self?.rescan()
            }
        }

        rescan()
        // Collapse once the first scan has told us where everything is.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            await rescanSoon()
            apply(.collapsed, force: true)
        }
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

    /// Whether `item` is really in the bar right now, so its position can be trusted.
    /// While a native restriction is active, removed apps' icons report stale frames.
    func isLive(_ item: MenuBarItem) -> Bool {
        guard let restriction else { return true }
        if item.isNativeSystemItem { return true }
        guard let bundle = item.bundleID else { return false }
        return restriction.allowed.contains(bundle)
    }

    private func geometricSection(of item: MenuBarItem) -> MenuBarSection {
        guard let divider = dividerFrame, let always = alwaysDividerFrame else { return .visible }
        let x = item.frame.midX
        if x > divider.maxX - 1 { return .visible }
        if x > always.maxX - 1 { return .hidden }
        return .alwaysHidden
    }

    func section(of item: MenuBarItem) -> MenuBarSection {
        if item.isOverflowed { return .visible }
        if !isLive(item) { return itemSections[item.id] ?? .hidden }
        return geometricSection(of: item)
    }

    func items(in section: MenuBarSection) -> [MenuBarItem] {
        items.filter { self.section(of: $0) == section }
    }

    private func updateSectionCache() {
        for item in items where isLive(item) && !item.isOverflowed {
            itemSections[item.id] = geometricSection(of: item)
        }
    }

    /// Per app, the most visible section any of its icons is in — native hiding can
    /// only show or hide an app's icons together.
    private func bundleSections() -> [String: MenuBarSection] {
        var result: [String: MenuBarSection] = [:]
        for item in items where !item.isNativeSystemItem && !item.isOverflowed {
            guard let bundle = item.bundleID else { continue }
            let section = self.section(of: item)
            if let existing = result[bundle], existing.rank <= section.rank { continue }
            result[bundle] = section
        }
        return result
    }

    // MARK: - Hidden section

    /// Apps opened from the hidden section, let into the bar until the next hide.
    private var temporarilyShown: Set<String> = []
    /// Icons macOS pushed into its own overflow because the bar was full, as last seen
    /// while apps were showing (while hidden, their positions are stale).
    private var overflowedIDs: Set<String> = []

    func isInHiddenSection(_ item: MenuBarItem) -> Bool {
        guard let bundle = item.bundleID else { return false }
        return settings.hiddenSectionBundles.contains(bundle)
    }

    private func isTemporarilyShown(_ item: MenuBarItem) -> Bool {
        item.bundleID.map(temporarilyShown.contains) ?? false
    }

    /// What the hidden section lists: apps kept out of the bar on purpose, plus any
    /// that didn't fit.
    var hiddenSectionItems: [MenuBarItem] {
        var seen = Set<String>()
        return items.filter { item in
            guard !isOwn(item), !item.isNativeSystemItem else { return false }
            guard isInHiddenSection(item) || overflowedIDs.contains(item.id) else { return false }
            return seen.insert(item.id).inserted
        }
    }

    private func rememberOverflow() {
        guard state != .collapsed else { return }
        overflowedIDs = Set(items.filter { $0.isOverflowed && !$0.isNativeSystemItem }.map(\.id))
    }

    /// Whether hide-all mode hides this icon while collapsed.
    func isHiddenByHideAll(_ item: MenuBarItem) -> Bool {
        guard !item.isOverflowed, !item.isNativeSystemItem else { return false }
        guard let bundle = item.bundleID else { return true }
        return !settings.alwaysShownBundles.contains(bundle)
    }

    private var lastReapply = Date.distantPast

    /// Under a native restriction, an icon that should be hidden but is in the bar
    /// (an app launched after the restriction, a bundleless icon, an icon dragged
    /// into a hidden section) means the allow-list is out of date: refresh it.
    private func reapplyIfSomethingSlippedThrough() {
        guard method == .native, Date.now.timeIntervalSince(lastReapply) > 2 else { return }
        let slipped: Bool
        if settings.hideAllApps {
            if state == .collapsed {
                slipped = items.contains { isLive($0) && isHiddenByHideAll($0) && !isOwn($0) }
            } else {
                slipped = items.contains { isLive($0) && isInHiddenSection($0) && !isTemporarilyShown($0) }
            }
        } else {
            guard state != .all else { return }
            let hiding: Set<MenuBarSection> = state == .collapsed ? [.hidden, .alwaysHidden] : [.alwaysHidden]
            slipped = items.contains {
                isLive($0) && !$0.isNativeSystemItem && !$0.isOverflowed && !isOwn($0)
                    && hiding.contains(geometricSection(of: $0))
            }
        }
        guard slipped else { return }
        lastReapply = .now
        applyNative(state)
    }

    private func isOwn(_ item: MenuBarItem) -> Bool {
        item.pid == ProcessInfo.processInfo.processIdentifier
    }

    /// Left edge of the leftmost icon that is actually on screen — where the empty
    /// stretch of menu bar ends.
    var leftmostVisibleX: CGFloat? {
        let screenMinX = NSScreen.screens.first?.frame.minX ?? 0
        var xs = items.filter { isLive($0) && !$0.isOverflowed }.map(\.frame.minX).filter { $0 >= screenMinX }
        if let toggle = toggleFrame { xs.append(toggle.minX) }
        return xs.min()
    }

    /// Icons that are in a hidden section for the current state but that the active
    /// method can't remove, so `CoverController` paints over them.
    func itemsNeedingCover() -> [MenuBarItem] {
        if settings.hideAllApps {
            // Hide-all only covers in the fallback; natively, apps are removed and
            // Apple's own items are meant to stay.
            guard method == .cover, state == .collapsed else { return [] }
            return items.filter { isHiddenByHideAll($0) }
        }
        let hiding: [MenuBarSection]
        switch state {
        case .collapsed: hiding = [.hidden, .alwaysHidden]
        case .hidden: hiding = [.alwaysHidden]
        case .all: hiding = []
        }
        let candidates = items.filter { !$0.isOverflowed && hiding.contains(section(of: $0)) }
        switch method {
        case .pushOffscreen: return []
        case .cover: return candidates
        // Native hiding keeps macOS's own items; only those still need covering.
        case .native: return candidates.filter { $0.isNativeSystemItem && isLive($0) }
        }
    }

    // MARK: - Scanning

    func rescan() {
        let trusted = AXIsProcessTrusted()
        if trusted && !isAccessibilityTrusted {
            // Just granted: hiding couldn't work until now, so apply it properly.
            isAccessibilityTrusted = true
            Task {
                await rescanSoon(after: 100)
                apply(state, force: true)
            }
        }
        isAccessibilityTrusted = trusted
        scanQueue.async { [weak self] in
            let found = MenuBarScanner.scan()
            Task { @MainActor in
                guard let self, found != self.items else { return }
                self.items = found
            }
        }
    }

    /// Waits for macOS to lay the bar out again after a change, then rescans.
    func rescanSoon(after delay: Int = 180) async {
        try? await Task.sleep(for: .milliseconds(delay))
        isAccessibilityTrusted = AXIsProcessTrusted()
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

    /// A new app's icon lands wherever macOS puts it; under a native restriction it
    /// would be hidden just for being new. Treat unknown apps as Visible and re-apply.
    private func appLaunched(_ bundleID: String?) {
        rescan()
        guard method == .native, let restriction, let bundleID, !restriction.allowed.contains(bundleID) else { return }
        let known = items.contains { $0.bundleID == bundleID && itemSections[$0.id] != nil && itemSections[$0.id] != .visible }
        guard !known else { return }
        for item in items where item.bundleID == bundleID { itemSections[item.id] = .visible }
        apply(state, force: true)
    }

    // MARK: - Reveal

    func reveal(_ target: RevealState = .hidden) {
        guard target != .collapsed else { return collapse() }
        apply(target)
        scheduleRehide()
    }

    func collapse() {
        if let pinned = pinnedByRule {
            // A rule is holding things open; drop back to that rather than closing.
            if state != pinned { apply(pinned) }
            return
        }
        apply(.collapsed)
    }

    func toggle() {
        // Hide-all has no Hidden-vs-Always-Hidden distinction: revealing shows everything.
        if settings.hideAllApps { return toggleAll() }
        state == .collapsed ? reveal(.hidden) : collapse()
    }

    func toggleAll() {
        state == .all ? collapse() : reveal(.all)
    }

    private func apply(_ new: RevealState, force: Bool = false) {
        let changed = state != new
        guard changed || force else { return }

        switch method {
        case .pushOffscreen:
            dividerItem.length = new == .collapsed ? Self.pushLength : Self.dividerLength
            alwaysDividerItem.length = new == .all ? Self.dividerLength : Self.pushLength
            releaseRestriction()
        case .cover:
            dividerItem.length = dividerLengthOnModernBar
            alwaysDividerItem.length = dividerLengthOnModernBar
            releaseRestriction()
        case .native:
            dividerItem.length = dividerLengthOnModernBar
            alwaysDividerItem.length = dividerLengthOnModernBar
            applyNative(new)
        }

        state = new
        updateIcons()
        if changed { onStateChange?(new) }
        Task { await rescanSoon() }
        if new == .collapsed {
            temporarilyShown.removeAll()
            rehideTimer?.invalidate()
            stopWatchingCursor()
            if MenuBarGeometry.isInMenuBar(NSEvent.mouseLocation, margin: 6) { isHoverArmed = false }
        } else if changed {
            revealedAt = .now
        }
    }

    /// Hide-all doesn't use sections, so the dividers shrink to nothing and leave
    /// just Sleeve's icon — they keep their slot, so sections still work if it's off.
    private var dividerLengthOnModernBar: CGFloat {
        settings.hideAllApps ? 0 : Self.dividerLength
    }

    // MARK: - Native hiding

    private func applyNative(_ target: RevealState) {
        nativeGeneration += 1
        let generation = nativeGeneration
        Task {
            // Hide-all's allow-list never depends on where icons are, so act at once:
            // any scan here would sit between the cursor and the bar changing.
            if settings.hideAllApps {
                var allowed = appleAgentBundles()
                if let own = Bundle.main.bundleIdentifier { allowed.insert(own) }
                if target == .collapsed {
                    // Only Apple's items, Sleeve and the "Always" apps stay.
                    allowed.formUnion(settings.alwaysShownBundles)
                    await restrictNatively(to: allowed, generation: generation,
                                           describing: "every app except \(allowed.sorted())")
                    return
                }
                // Revealed: everything except the hidden section (apps the user keeps
                // out of the bar), less any of those opened from the section just now.
                let hiddenSection = Set(settings.hiddenSectionBundles).subtracting(temporarilyShown)
                guard !hiddenSection.isEmpty else {
                    releaseRestriction()
                    return
                }
                allowed.formUnion(items.compactMap(\.bundleID))
                allowed.subtract(hiddenSection)
                await restrictNatively(to: allowed, generation: generation,
                                       describing: "the hidden section: \(hiddenSection.sorted())")
                return
            }

            // Showing everything needs no layout either.
            if target == .all {
                releaseRestriction()
                return
            }
            // Sections: use the layout from the last scan (refreshed every 3 s and
            // after every change); only scan first if there's nothing to go on.
            if items.isEmpty { await rescanSoon(after: 0) }
            guard generation == nativeGeneration else { return }

            let hiding: Set<MenuBarSection>
            switch target {
            case .collapsed: hiding = [.hidden, .alwaysHidden]
            case .hidden: hiding = [.alwaysHidden]
            case .all: hiding = []
            }
            let sections = bundleSections()
            let hiddenBundles = Set(sections.filter { hiding.contains($0.value) }.keys)
            let hidesBundlelessItem = items.contains {
                $0.bundleID == nil && !$0.isNativeSystemItem && hiding.contains(section(of: $0))
            }
            guard !hiddenBundles.isEmpty || hidesBundlelessItem else {
                if restriction != nil { NSLog("Sleeve: native hiding released — nothing to hide") }
                releaseRestriction()
                return
            }

            var allowed = Set(sections.keys).subtracting(hiddenBundles).union(appleAgentBundles())
            if let own = Bundle.main.bundleIdentifier { allowed.insert(own) }
            await restrictNatively(to: allowed, generation: generation,
                                   describing: "\(hiddenBundles.sorted())\(hidesBundlelessItem ? " + icons without a bundle ID" : "")")
        }
    }

    private func restrictNatively(to allowed: Set<String>, generation: Int, describing hidden: String) async {
        let result = await native.restrict(to: allowed)
        guard generation == nativeGeneration else {
            // A newer change won the race; drop this one.
            if case .success(let stale) = result { stale.release() }
            return
        }
        switch result {
        case .success(let new):
            NSLog("Sleeve: native hiding active — hiding \(hidden)")
            // New restriction first, then release the old, so nothing flashes.
            let old = restriction
            restriction = new
            old?.release()
            objectWillChange.send()
        case .failure(let error):
            // Fail open: never leave icons hidden after an error. Covering takes over.
            NSLog("Sleeve: native hiding failed, falling back to covering: \(error.localizedDescription)")
            releaseRestriction()
            nativeFailure = error.localizedDescription
            apply(state, force: true)
        }
    }

    private func releaseRestriction() {
        nativeGeneration += 1
        restriction?.release()
        if restriction != nil {
            restriction = nil
            objectWillChange.send()
        }
    }

    /// Lets Settings retry after a failure (e.g. once Accessibility is granted).
    func retryNativeHiding() {
        nativeFailure = nil
        apply(state, force: true)
    }

    func applyRulePin(_ pin: RevealState?) {
        pinnedByRule = pin
        if let pin {
            if state == .collapsed || (pin == .all && state != .all) { apply(pin) }
        } else if state != .collapsed {
            scheduleRehide()
        }
    }

    // MARK: - Auto-rehide

    func scheduleRehide() {
        rehideTimer?.invalidate()
        stopWatchingCursor()
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
            startWatchingCursor()
        }
    }

    // MARK: - Instant rehide

    private var cursorMonitors: [Any] = []
    private var lastMenuCheck = Date.distantPast
    private var menuWasOpen = false

    /// Hides the moment the cursor leaves the menu bar (or the Sleeve Bar) — driven by
    /// the cursor's own movement, so there's no polling delay. An open menu holds
    /// everything in place, or the icon would vanish from under its own menu.
    private func startWatchingCursor() {
        stopWatchingCursor()
        let handler: () -> Void = { [weak self] in
            guard let self, self.state != .collapsed else { return }
            if self.isCursorInMenuBarOrBar() { return }
            // The bar is still rearranging itself for a moment after a reveal.
            if Date.now.timeIntervalSince(self.revealedAt) < 0.15 { return }
            // Asking the window server whether a menu is open costs a little, so do
            // it at most every 80 ms while the cursor roams outside the bar.
            if Date.now.timeIntervalSince(self.lastMenuCheck) > 0.08 {
                self.lastMenuCheck = .now
                self.menuWasOpen = Self.isAnyMenuOpen()
            }
            if !self.menuWasOpen { self.collapse() }
        }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { _ in
            Task { @MainActor in handler() }
        }) { cursorMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { event in
            Task { @MainActor in handler() }
            return event
        }) { cursorMonitors.append(local) }
        // A menu closing doesn't move the cursor; check now and then while one is open.
        rehideTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.menuWasOpen else { return }
                self.lastMenuCheck = .distantPast
                handler()
            }
        }
    }

    private func stopWatchingCursor() {
        cursorMonitors.forEach { NSEvent.removeMonitor($0) }
        cursorMonitors.removeAll()
        menuWasOpen = false
    }

    /// Extra rect that counts as "still in the menu bar" — the Sleeve Bar, when open.
    var keepAliveRect: CGRect?

    private func isCursorInMenuBarOrBar() -> Bool {
        let mouse = NSEvent.mouseLocation
        if let keepAliveRect, keepAliveRect.insetBy(dx: -8, dy: -8).contains(mouse) { return true }
        // 6 pt of slack below the bar: resting on its bottom edge mustn't flap.
        return MenuBarGeometry.isInMenuBar(mouse, margin: 6)
    }

    /// Apple's own menu bar processes. They're always allow-listed: the restriction
    /// only keeps "system items" by number, and anything else Apple puts in the bar —
    /// Siri, owned by SystemUIServer — would otherwise vanish and reappear on every
    /// toggle, shuffling the whole bar.
    private func appleAgentBundles() -> Set<String> {
        var bundles: Set<String> = ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver",
                                    "com.apple.TextInputMenuAgent", "com.apple.Siri"]
        for item in items where item.isNativeSystemItem {
            if let bundle = item.bundleID { bundles.insert(bundle) }
        }
        return bundles
    }

    /// Hover may reveal only after the cursor has been away from the bar since the
    /// last hide — otherwise hiding with a click, or a hide while the cursor sits in
    /// the bar, would be undone by the very next twitch of the mouse.
    var isHoverArmed = true
    private var revealedAt = Date.distantPast

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

    /// Opens a status item's menu, even if it is currently hidden.
    func activate(_ item: MenuBarItem) async {
        if settings.hideAllApps && method == .native {
            return await activateFromHiddenSection(item)
        }
        let section = self.section(of: item)
        let needed: RevealState = section == .alwaysHidden ? .all : (section == .hidden ? .hidden : state)

        switch method {
        case .cover:
            // The icon never left its place; press it there and its menu drops down
            // over the cover.
            break
        case .pushOffscreen:
            if needed != state && needed != .collapsed {
                apply(needed)
                await rescanSoon()
            }
        case .native:
            if !isLive(item) {
                reveal(needed == .collapsed ? .hidden : needed)
                // Wait for macOS to put the icon back and reflow, then read where it is.
                for _ in 0..<20 where !isLive(item) {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                await rescanSoon(after: 250)
            }
        }

        let fresh = items.first { $0.id == item.id } ?? item
        if !fresh.element.press() {
            ItemMover.click(at: CGPoint(x: fresh.frame.midX, y: fresh.frame.midY))
        }
        if method != .cover { scheduleRehide() }
    }

    /// Hide-all: an app kept in the hidden section is let into the bar until the next
    /// hide, then pressed; one macOS overflowed is pressed where it is, or failing that
    /// through macOS's own "Show Hidden Menu Bar Items" button.
    private func activateFromHiddenSection(_ item: MenuBarItem) async {
        if let bundle = item.bundleID, isInHiddenSection(item) {
            temporarilyShown.insert(bundle)
        }
        apply(.all, force: true)
        scheduleRehide()
        for _ in 0..<20 where !isLive(item) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await rescanSoon(after: 250)
        let fresh = items.first { $0.id == item.id } ?? item
        if fresh.isOverflowed {
            if !fresh.element.press() { MenuBarScanner.overflowButton()?.press() }
            return
        }
        if !fresh.element.press() {
            ItemMover.click(at: CGPoint(x: fresh.frame.midX, y: fresh.frame.midY))
        }
    }

    // MARK: - Toggle button

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        // Two-finger click (secondary click) or ⌃-click: Sleeve's menu of options.
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
            return
        }
        if event?.modifierFlags.contains(.option) == true {
            toggleAll()
            return
        }
        // Nothing to show yet: explain how to hide something instead of doing nothing.
        if !settings.hideAllApps && state == .collapsed && isAccessibilityTrusted
            && items(in: .hidden).isEmpty && items(in: .alwaysHidden).isEmpty {
            showHowToHide()
            return
        }
        if settings.useSleeveBar && !settings.hideAllApps {
            onToggleClickedForBar?()
        } else {
            toggle()
        }
    }

    // MARK: - Hovering Sleeve's icon

    private let iconHover = IconHoverTracker()
    /// Called to reveal from a hover when the Sleeve Bar is the reveal style.
    var onHoverRevealForBar: (() -> Void)?

    func iconHoverBegan() {
        guard !isHoveringIcon else { return }
        isHoveringIcon = true
        updateIcons()
        guard settings.revealOnIconHover, state == .collapsed else { return }
        // No dwell: the moment the cursor touches the icon, the apps come out.
        revealForUser()
    }

    /// Reveal the way the user's settings ask for: everything in hide-all mode, the
    /// Sleeve Bar if that's the reveal style, otherwise the Hidden section in place.
    func revealForUser() {
        if settings.hideAllApps {
            // Hide-all shows apps in the bar itself; the drawer is the hidden section.
            reveal(.all)
        } else if settings.useSleeveBar {
            onHoverRevealForBar?()
        } else {
            reveal(.hidden)
        }
    }

    /// Two-finger click: show if hidden, hide if shown.
    private var lastUserToggle = Date.distantPast

    func toggleForUser() {
        // One physical click can reach Sleeve twice on macOS 27 (the menu bar reports
        // the button-down to the global monitor and the button-up to the button);
        // treat anything within 0.35 s as the same click.
        guard Date.now.timeIntervalSince(lastUserToggle) > 0.35 else { return }
        lastUserToggle = .now
        if isBarOpen { onCloseBar?(); return }
        state == .collapsed ? revealForUser() : collapse()
    }

    func iconHoverEnded() {
        guard isHoveringIcon else { return }
        isHoveringIcon = false
        updateIcons()
        // Hiding again is left to auto-rehide, which waits until the cursor has left
        // the whole menu bar — revealed icons can shift the bar under the cursor.
    }

    private var lastMenuShown = Date.distantPast

    /// Sleeve's options, dropped down from its icon. One click can arrive twice on
    /// macOS 27 (global monitor and button), so a second request within 0.4 s is the
    /// same click.
    func showMenu() {
        guard Date.now.timeIntervalSince(lastMenuShown) > 0.4, let menu = menuProvider?() else { return }
        lastMenuShown = .now
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil
    }

    private var hintPopover: NSPopover?

    // MARK: - Keeping the icon still

    /// When apps sit to the *right* of Sleeve's icon, revealing them pushes the icon
    /// left and hiding pulls it back — it jumps around under the cursor. macOS 27
    /// won't let an app choose its own position (preferred positions are ignored and
    /// synthesized ⌘-drags rejected), so the fix is one ⌘-drag by the user; this
    /// explains that, once, the first time the situation is seen.
    var hasAppsRightOfIcon: Bool {
        guard state != .collapsed, let icon = toggleFrame else { return false }
        return items.contains { item in
            isLive(item) && !item.isOverflowed && !item.isNativeSystemItem && !isOwn(item)
                && item.frame.minX > icon.maxX
        }
    }

    private func offerPlacementTipIfNeeded() {
        guard hasAppsRightOfIcon,
              !UserDefaults.standard.bool(forKey: "didShowPlacementTip"),
              hintPopover?.isShown != true else { return }
        UserDefaults.standard.set(true, forKey: "didShowPlacementTip")
        showPlacementTip()
    }

    func showPlacementTip() {
        guard let button = toggleItem.button else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PlacementTipView(close: { [weak self] in
            self?.hintPopover?.close()
        }))
        hintPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showHowToHide() {
        guard let button = toggleItem.button else { return }
        if hintPopover?.isShown == true { hintPopover?.close(); return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: HowToHideView(close: { [weak self] in
            self?.hintPopover?.close()
        }))
        hintPopover = popover
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// True while the cursor is over Sleeve's icon — the icon shows its "looking"
    /// face straight away, before anything has been revealed.
    private(set) var isHoveringIcon = false

    /// The icon is drawn by our own image view rather than the button's image, so the
    /// change between faces can animate: SF Symbols morph from one to the other, and
    /// the "showing" face gives a little bounce as the apps come out.
    private let iconView = MenuIconView()
    private var shownFace: (style: SleeveSettings.ToggleIcon, showing: Bool)?

    private func installIconView(in button: NSStatusBarButton) {
        button.image = nil
        button.title = ""
        button.imagePosition = .noImage
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        button.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])
        // With no image of its own the button would collapse to nothing.
        toggleItem.length = 26
    }

    /// The Sleeve Bar is showing: the icon wears its "open" face meanwhile.
    var isBarOpen = false {
        didSet { if isBarOpen != oldValue { updateIcons() } }
    }
    /// Closes the Sleeve Bar (set by the app, which owns it).
    var onCloseBar: (() -> Void)?

    private func updateIcons() {
        let showing = state != .collapsed || isHoveringIcon || isBarOpen
        let style = settings.toggleIcon
        let previous = shownFace
        shownFace = (style, showing)
        // Only a change of face animates; a change of style just swaps.
        let animate = previous != nil && previous?.style == style && previous?.showing != showing

        switch style {
        case .custom:
            let image = settings.customIconData.flatMap(NSImage.init(data:))
                ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
            image?.size = NSSize(width: 18, height: 18)
            iconView.image = image
            // One picture, two moods: dimmed while apps are tucked away.
            if animate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    iconView.animator().alphaValue = showing ? 1 : 0.5
                }
            } else {
                iconView.alphaValue = showing ? 1 : 0.5
            }
        default:
            iconView.alphaValue = 1
            let face = showing ? style.faces.shown : style.faces.hidden
            let config = NSImage.SymbolConfiguration(pointSize: style == .dot ? 10 : 14,
                                                     weight: showing ? .semibold : .regular)
            guard let image = NSImage(systemSymbolName: face, accessibilityDescription: "Sleeve")?
                .withSymbolConfiguration(config) else { break }
            image.isTemplate = true
            if animate {
                iconView.setSymbolImage(image, contentTransition: .replace.downUp.byLayer)
                if showing { iconView.addSymbolEffect(.bounce.up.byLayer, options: .nonRepeating) }
            } else {
                iconView.image = image
            }
        }

        // Dividers show a faint tick so the user can see where to drop icons. With the
        // classic method a collapsed divider is a long invisible spacer instead.
        let tick = NSImage(systemSymbolName: "poweron", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .light))
        tick?.isTemplate = true
        let alwaysShowTicks = Self.isModernMenuBar
        let showTicks = !(Self.isModernMenuBar && settings.hideAllApps)
        dividerItem.button?.image = showTicks && (alwaysShowTicks || state != .collapsed) ? tick : nil
        alwaysDividerItem.button?.image = showTicks && (alwaysShowTicks || state == .all) ? tick : nil
        dividerItem.button?.alphaValue = 0.35
        alwaysDividerItem.button?.alphaValue = 0.35
    }

    func tearDown() {
        // Leave the bar as we found it: no restriction, no stretched divider.
        releaseRestriction()
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

    /// Whether `point` is on a menu bar, `margin` points of slack below it included.
    /// Inclusive of the very top: pushed against the top edge the cursor reports
    /// y == screen.frame.maxY exactly, which `CGRect.contains` calls outside.
    static func isInMenuBar(_ point: CGPoint, margin: CGFloat = 0) -> Bool {
        NSScreen.screens.contains { screen in
            let frame = screen.frame
            guard point.x >= frame.minX, point.x <= frame.maxX else { return false }
            return point.y >= frame.maxY - height(of: screen) - margin && point.y <= frame.maxY + 2
        }
    }
}

/// Receives enter/exit for the tracking area on Sleeve's icon.
final class IconHoverTracker: NSResponder {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func mouseEntered(with event: NSEvent) {
        DispatchQueue.main.async { self.onEnter?() }
    }

    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.async { self.onExit?() }
    }
}

/// Sleeve's icon. Never takes the click itself, so the status button underneath still
/// gets it.
final class MenuIconView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
