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

    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame && lhs.label == rhs.label
    }

    /// Name shown in Sleeve's UI. System items from MenuBarAgent/Control Center have
    /// useful descriptions ("Wi-Fi", "Battery"); third-party items often have none, in
    /// which case the app name is the best label there is.
    var displayName: String {
        if !label.isEmpty, label != ownerName, !isSystemItem { return "\(ownerName) — \(label)" }
        if !label.isEmpty { return label }
        return ownerName
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

    static func scan() -> [MenuBarItem] {
        guard AXIsProcessTrusted() else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var items: [MenuBarItem] = []

        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != ownPID {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            // An app hung in its main thread would otherwise block the scan for 6 s.
            AXUIElementSetMessagingTimeout(appElement, 0.2)

            guard let extras: AXUIElement = appElement.attribute("AXExtrasMenuBar"),
                  let children: [AXUIElement] = extras.attribute(kAXChildrenAttribute) else { continue }

            for (index, child) in children.enumerated() {
                guard let position: CGPoint = child.pointAttribute(kAXPositionAttribute),
                      let size: CGSize = child.sizeAttribute(kAXSizeAttribute),
                      size.width > 0 else { continue }

                let role: String = child.attribute(kAXRoleAttribute) ?? ""
                // macOS 27's own "Show Hidden Menu Bar Items" chevron: the only button
                // MenuBarAgent puts in the bar. It must never be hidden or covered,
                // or icons macOS overflowed would become unreachable.
                if app.bundleIdentifier == "com.apple.MenuBarAgent" && role == kAXButtonRole { continue }

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
                let owner = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
                let key = identifier.isEmpty ? "\(index)|\(label)" : identifier
                items.append(MenuBarItem(id: "\(app.bundleIdentifier ?? owner)|\(key)",
                                         pid: app.processIdentifier,
                                         ownerName: owner,
                                         bundleID: app.bundleIdentifier,
                                         label: label,
                                         frame: frame,
                                         element: target))
            }
        }
        // Right to left, the way the menu bar reads from the clock outwards.
        return items.sorted { $0.frame.minX > $1.frame.minX }
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
