import AppKit
import ApplicationServices

/// One icon in the menu bar's status area, as seen through Accessibility.
///
/// macOS 27 draws every status item inside a single system process (MenuBarAgent), so
/// the old approach of reading each item's own window from the window server no longer
/// works. Accessibility still exposes them: each app's `AXExtrasMenuBar` lists its
/// items with a position, a size, and a press action.
struct MenuBarItem: Identifiable, Equatable {
    var id: String
    var pid: pid_t
    var ownerName: String
    var bundleID: String?
    /// Title or accessibility description, whichever the app provides.
    var label: String
    /// Global frame, AppKit coordinates (origin bottom-left of the primary screen).
    var frame: CGRect
    var element: AXUIElement
    /// macOS 27 moved this icon into its own "Show Hidden Menu Bar Items" overflow
    /// because the bar ran out of room. It isn't really in the bar, so Sleeve
    /// neither sorts it into a section nor covers anything on its behalf.
    var isOverflowed = false

    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame && lhs.label == rhs.label && lhs.isOverflowed == rhs.isOverflowed
    }

    /// Name shown in Sleeve's UI. System items from MenuBarAgent/Control Center have
    /// useful descriptions ("Wi-Fi", "Battery"); third-party items often have none, in
    /// which case the app name is the best label there is.
    var displayName: String {
        if !label.isEmpty, label != ownerName, !isSystemItem { return "\(ownerName) — \(label)" }
        if !label.isEmpty { return label }
        return ownerName
    }

    /// Owned by macOS itself (clock, Wi-Fi, Control Center…). Native hiding always
    /// keeps these, so Sleeve covers them instead when they're in a hidden section.
    var isNativeSystemItem: Bool {
        guard let bundleID else { return false }
        return ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver",
                "com.apple.TextInputMenuAgent", "com.apple.Siri"].contains(bundleID)
    }

    var isSystemItem: Bool {
        ["MenuBarAgent", "ControlCenter", "Control Centre", "SystemUIServer", "TextInputMenuAgent"]
            .contains(ownerName)
            || bundleID?.hasPrefix("com.apple.") == true
    }

    /// App icon, or a symbol for system items (which belong to an agent with no icon).
    var icon: NSImage {
        if isSystemItem, let symbol = Self.systemSymbol(for: label),
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) {
            return image
        }
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            return icon
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }

    private static func systemSymbol(for label: String) -> String? {
        let l = label.lowercased()
        let table: [(String, String)] = [
            ("wi-fi", "wifi"), ("wifi", "wifi"), ("battery", "battery.75percent"),
            ("bluetooth", "dot.radiowaves.left.and.right"), ("sound", "speaker.wave.2.fill"),
            ("volume", "speaker.wave.2.fill"), ("clock", "clock"), ("control centre", "switch.2"),
            ("control center", "switch.2"), ("focus", "moon.fill"), ("spotlight", "magnifyingglass"),
            ("siri", "waveform"), ("display", "display"), ("now playing", "play.circle"),
            ("airdrop", "airplayaudio"), ("input", "keyboard"), ("keyboard", "keyboard"),
            ("user", "person.crop.circle"), ("time machine", "clock.arrow.circlepath"),
            ("screen mirroring", "rectangle.on.rectangle"), ("vpn", "network.badge.shield.half.filled")
        ]
        return table.first { l.contains($0.0) }?.1
    }
}

/// Reads the current set of status items. Runs off the main thread; AX calls into
/// other processes can stall for as long as that process is busy.
enum MenuBarScanner {
    /// Our own process: Sleeve's control items are found by frame instead.
    private static let ownPID = ProcessInfo.processInfo.processIdentifier

    /// An app that may own menu bar items, with what the scan needs to know about it.
    private struct Owner {
        let pid: pid_t
        let bundleID: String?
        let name: String
    }

    // Only touched from the (serial) scan queue; the lock is belt and braces.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var knownOwners: [Owner] = []
    nonisolated(unsafe) private static var lastFullScan = Date.distantPast

    /// Reads every app's menu bar items.
    ///
    /// Asking every running app costs: over a hundred processes, two seconds of
    /// Accessibility round-trips, most of them to background processes that can't have
    /// an icon at all. So a full scan (apps that can show UI) runs at most once a minute,
    /// or when asked (`full`, on an app launching or quitting); in between, only the
    /// handful of apps that had icons last time are re-read.
    static func scan(full: Bool = false) -> [MenuBarItem] {
        guard AXIsProcessTrusted() else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var items: [MenuBarItem] = []
        var overflowButton: CGRect?

        lock.lock()
        let known = knownOwners
        let doFull = full || known.isEmpty || Date().timeIntervalSince(lastFullScan) > 60
        lock.unlock()

        let owners: [Owner] = doFull
            ? NSWorkspace.shared.runningApplications.compactMap { app in
                // Background-only processes can't put anything in the menu bar.
                guard app.processIdentifier != ownPID, app.activationPolicy != .prohibited else { return nil }
                return Owner(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                             name: app.localizedName ?? app.bundleIdentifier ?? "Unknown")
            }
            : known
        var owning: [Owner] = []

        for app in owners {
            let appElement = AXUIElementCreateApplication(app.pid)
            // An app hung in its main thread would otherwise block the scan for 6 s.
            AXUIElementSetMessagingTimeout(appElement, 0.2)

            guard let extras: AXUIElement = appElement.attribute("AXExtrasMenuBar"),
                  let children: [AXUIElement] = extras.attribute(kAXChildrenAttribute) else { continue }
            owning.append(app)

            for (index, child) in children.enumerated() {
                guard let position: CGPoint = child.pointAttribute(kAXPositionAttribute),
                      let size: CGSize = child.sizeAttribute(kAXSizeAttribute),
                      size.width > 0 else { continue }

                let role: String = child.attribute(kAXRoleAttribute) ?? ""
                // macOS 27's own "Show Hidden Menu Bar Items" chevron: the only button
                // MenuBarAgent puts in the bar. It must never be hidden or covered,
                // or icons macOS overflowed would become unreachable.
                if app.bundleID == "com.apple.MenuBarAgent" && role == kAXButtonRole {
                    overflowButton = CGRect(x: position.x, y: primaryHeight - position.y - size.height,
                                            width: size.width, height: size.height)
                    continue
                }

                // System items on macOS 27 are a group wrapping the real menu bar item,
                // which carries the name, a stable identifier, and the press action.
                var target = child
                if role == "AXGroup",
                   let inner: [AXUIElement] = child.attribute(kAXChildrenAttribute),
                   inner.count == 1 {
                    target = inner[0]
                }

                let title: String = target.attribute(kAXTitleAttribute) ?? ""
                let description: String = target.attribute(kAXDescriptionAttribute) ?? ""
                let identifier: String = target.attribute(kAXIdentifierAttribute) ?? ""
                // "Wi‑Fi, connected, 3 bars" → "Wi-Fi": the first clause is the name,
                // the rest is live status that would make the label flicker.
                let rawLabel = !title.isEmpty ? title : description
                let label = (rawLabel.components(separatedBy: ", ").first ?? rawLabel)
                    .replacingOccurrences(of: "\u{2011}", with: "-")

                // AX is top-left origin; flip into AppKit space once, here.
                let frame = CGRect(x: position.x,
                                   y: primaryHeight - position.y - size.height,
                                   width: size.width,
                                   height: size.height)
                let owner = app.name
                let key = identifier.isEmpty ? "\(index)|\(label)" : identifier
                items.append(MenuBarItem(id: "\(app.bundleID ?? owner)|\(key)",
                                         pid: app.pid,
                                         ownerName: owner,
                                         bundleID: app.bundleID,
                                         label: label,
                                         frame: frame,
                                         element: target))
            }
        }
        if doFull {
            lock.lock()
            knownOwners = owning
            lastFullScan = Date()
            lock.unlock()
        }
        // Overflowed icons report a position on top of macOS's overflow button.
        if let overflowButton {
            let zone = overflowButton.insetBy(dx: -30, dy: 0)
            for index in items.indices where zone.contains(CGPoint(x: items[index].frame.midX,
                                                                    y: items[index].frame.midY)) {
                items[index].isOverflowed = true
            }
        }
        // Right to left, the way the menu bar reads from the clock outwards.
        return items.sorted { $0.frame.minX > $1.frame.minX }
    }

    /// macOS 27's own "Show Hidden Menu Bar Items" button, if it's in the bar.
    static func overflowButton() -> AXUIElement? {
        guard AXIsProcessTrusted(),
              let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first else {
            return nil
        }
        let element = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        guard let extras: AXUIElement = element.attribute("AXExtrasMenuBar"),
              let children: [AXUIElement] = extras.attribute(kAXChildrenAttribute) else { return nil }
        return children.first { (($0.attribute(kAXRoleAttribute) as String?) ?? "") == kAXButtonRole }
    }

    /// Frontmost app's menus (Apple, File, Edit…): where the empty bar begins.
    static func appMenusMaxX() -> CGFloat? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        guard let bar: AXUIElement = element.attribute(kAXMenuBarAttribute),
              let menus: [AXUIElement] = bar.attribute(kAXChildrenAttribute) else { return nil }
        return menus.compactMap { menu -> CGFloat? in
            guard let p = menu.pointAttribute(kAXPositionAttribute),
                  let s = menu.sizeAttribute(kAXSizeAttribute) else { return nil }
            return p.x + s.width
        }.max()
    }
}

// MARK: - AX helpers

extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    func pointAttribute(_ name: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    func sizeAttribute(_ name: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    @discardableResult
    func press() -> Bool {
        AXUIElementPerformAction(self, kAXPressAction as CFString) == .success
    }
}
