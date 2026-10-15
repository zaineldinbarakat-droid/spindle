import AppKit
import SwiftUI

/// Zen mode: one quiet bar over the entire menu bar, on every display, so nothing in it
/// shows while presenting, screen sharing or focusing. Spindle's notch pill steps away
/// too. Leave with the hotkey or a double-click on the bar.
@MainActor
final class ZenController: ObservableObject {
    @Published private(set) var isOn = false

    private var panels: [NSPanel] = []
    private unowned let spindle: SpindleBridge
    private unowned let sections: SectionManager

    init(spindle: SpindleBridge, sections: SectionManager) {
        self.spindle = spindle
        self.sections = sections
    }

    func toggle() { isOn ? disable() : enable() }

    func enable() {
        guard !isOn else { return }
        isOn = true
        sections.collapse()
        for screen in NSScreen.screens {
            let strip = MenuBarGeometry.strip(of: screen)
            let panel = NSPanel(contentRect: strip, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            // Above the status items, below Spindle's notch panel (which hides itself).
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: ZenBar(onExit: { [weak self] in self?.disable() }))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.3; panel.animator().alphaValue = 1 }
            panels.append(panel)
        }
        spindle.zenChanged(true)
    }

    func disable() {
        guard isOn else { return }
        isOn = false
        let closing = panels
        panels.removeAll()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            Task { @MainActor in closing.forEach { $0.orderOut(nil) } }
        })
        spindle.zenChanged(false)
    }
}

private struct ZenBar: View {
    var onExit: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle().fill(.black)
            Text("Zen · double-click to return")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(hovering ? 0.45 : 0))
                .animation(.easeInOut(duration: 0.3), value: hovering)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onExit)
    }
}
