import AppKit
import Combine
import SwiftUI

/// A floating drawer just under the menu bar that shows the hidden apps — Ice's
/// "Ice Bar".
///
/// Revealing apps in the menu bar itself makes macOS rearrange the bar, which slides
/// Sleeve's icon (and everything else) about under the cursor. The drawer shows them
/// without touching the bar at all; clicking one opens its real menu.
@MainActor
final class SleeveBarController {
    private var panel: NSPanel?
    private unowned let sections: SectionManager
    private unowned let spindle: SpindleBridge
    private let model = SleeveBarModel()
    private var outsideClickMonitor: Any?
    private var cursorMonitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()

    var isOpen: Bool { panel?.isVisible == true }

    init(sections: SectionManager, spindle: SpindleBridge) {
        self.sections = sections
        self.spindle = spindle
        sections.$items.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshItems() }
        }.store(in: &cancellables)
    }

    func toggle(includeAlwaysHidden: Bool = false) {
        isOpen ? close() : open(includeAlwaysHidden: includeAlwaysHidden)
    }

    func open(includeAlwaysHidden: Bool = false) {
        // Hover reveal fires on every cursor move; an open bar must not re-fade.
        guard !isOpen else { return }
        model.includeAlwaysHidden = includeAlwaysHidden || NSEvent.modifierFlags.contains(.option)
        refreshItems()
        sections.rescan()

        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }

        sections.keepAliveRect = panel.frame
        sections.isBarOpen = true
        spindle.sleeveBarChanged(open: true)
        installOutsideClickMonitor()
        installCursorWatch()
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
        sections.keepAliveRect = nil
        sections.isBarOpen = false
        // Closed with the cursor still on the bar (a click): hover waits until it leaves.
        if MenuBarGeometry.isInMenuBar(NSEvent.mouseLocation, margin: 6) { sections.isHoverArmed = false }
        spindle.sleeveBarChanged(open: false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        cursorMonitors.forEach { NSEvent.removeMonitor($0) }
        cursorMonitors.removeAll()
    }

    /// Closes the moment the cursor is off both the menu bar and the drawer — unless a
    /// menu it opened is still showing.
    private func installCursorWatch() {
        let check: () -> Void = { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            let point = NSEvent.mouseLocation
            if MenuBarGeometry.isInMenuBar(point, margin: 6) { return }
            if panel.frame.insetBy(dx: -10, dy: -10).contains(point) { return }
            if SectionManager.isAnyMenuOpen() { return }
            self.close()
        }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { _ in
            Task { @MainActor in check() }
        }) { cursorMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { event in
            Task { @MainActor in check() }
            return event
        }) { cursorMonitors.append(local) }
    }

    private func refreshItems() {
        var list: [MenuBarItem]
        if SleeveSettings.shared.hideAllApps {
            // Every app hide-all keeps out of the bar, one button per icon.
            list = sections.items.filter { sections.isHiddenByHideAll($0) }
        } else {
            list = sections.items(in: .hidden)
            if model.includeAlwaysHidden { list += sections.items(in: .alwaysHidden) }
        }
        model.items = list.sorted { $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName) == .orderedAscending }
        if let panel, panel.isVisible { position(panel) }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        let root = SleeveBarView(model: model) { [weak self] item in
            guard let self else { return }
            self.close()
            Task { await self.sections.activate(item) }
        }
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        panel.contentView = hosting
        return panel
    }

    /// Starts under Sleeve's icon and runs right, toward where the apps normally sit;
    /// never under the notch or Spindle's pill.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.screens.first, let hosting = panel.contentView else { return }
        let size = hosting.fittingSize
        let barBottom = screen.frame.maxY - MenuBarGeometry.height(of: screen)
        var x = (sections.toggleFrame?.minX ?? (screen.frame.maxX - size.width - 200)) - 6
        if let pill = spindle.state?.pillFrame, !pill.isEmpty, x < pill.maxX, x + size.width > pill.minX {
            x = pill.maxX + 8
        }
        x = min(max(x, screen.frame.minX + 6), screen.frame.maxX - size.width - 6)
        panel.setFrame(CGRect(x: x, y: barBottom - size.height - 6, width: size.width, height: size.height),
                       display: true)
        sections.keepAliveRect = panel.isVisible ? panel.frame : nil
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel else { return }
                let point = NSEvent.mouseLocation
                if !panel.frame.contains(point), !(self.sections.toggleFrame?.contains(point) ?? false) {
                    self.close()
                }
            }
        }
    }
}

@MainActor
final class SleeveBarModel: ObservableObject {
    @Published var items: [MenuBarItem] = []
    @Published var includeAlwaysHidden = false
}

struct SleeveBarView: View {
    @ObservedObject var model: SleeveBarModel
    var activate: (MenuBarItem) -> Void

    var body: some View {
        HStack(spacing: 2) {
            if model.items.isEmpty {
                Text(AXIsProcessTrusted()
                     ? "No hidden icons — ⌘-drag icons left of the Sleeve divider to hide them."
                     : "Allow Sleeve in Privacy & Security → Accessibility.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else {
                ForEach(model.items) { item in
                    SleeveBarButton(item: item) { activate(item) }
                }
            }
        }
        .padding(5)
        .frame(height: 36)
        .background(barBackground)
        .fixedSize()
    }

    @ViewBuilder
    private var barBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}

private struct SleeveBarButton: View {
    var item: MenuBarItem
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(nsImage: item.icon)
                .resizable()
                .renderingMode(item.isSystemItem ? .template : .original)
                .aspectRatio(contentMode: .fit)
                .frame(width: 17, height: 17)
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovering ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.displayName)
    }
}
