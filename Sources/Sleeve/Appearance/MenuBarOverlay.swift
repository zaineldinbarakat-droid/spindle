import AppKit
import Combine
import SwiftUI

/// What the overlay needs to know about one screen's bar, in the overlay window's
/// own coordinates (origin top-left, x from the screen's left edge).
struct BarLayout: Equatable {
    var size: CGSize
    var barHeight: CGFloat
    /// Right end of the app menus (Apple, File, Edit…).
    var appMenusEnd: CGFloat
    /// Left end of the status icons.
    var statusStart: CGFloat
    /// The camera housing, if this screen has one.
    var notch: ClosedRange<CGFloat>?
}

/// Draws the chosen style across the menu bar: a light tint laid over the whole strip,
/// edge to edge and flush with the top of the screen — notch and all — as Ice does.
/// It never takes a click.
@MainActor
final class MenuBarOverlayController {
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private let model = OverlayModel()
    private let settings = SleeveSettings.shared
    private unowned let sections: SectionManager
    private unowned let spindle: SpindleBridge
    private var cancellables = Set<AnyCancellable>()
    private var appMenusEnd: CGFloat = 0

    init(sections: SectionManager, spindle: SpindleBridge) {
        self.sections = sections
        self.spindle = spindle

        settings.$appearance.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }.store(in: &cancellables)
        sections.$items.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }.store(in: &cancellables)
        spindle.$state.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }.store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        // App menus change width with every app switch.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in self?.updateAppMenusEnd() }
            .store(in: &cancellables)
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.refresh() }
            }
            .store(in: &cancellables)

        updateAppMenusEnd()
    }

    private func updateAppMenusEnd() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let end = MenuBarScanner.appMenusMaxX() ?? 0
            Task { @MainActor in
                self?.appMenusEnd = end
                self?.refresh()
            }
        }
    }

    func refresh() {
        let isDark = SystemAppearance.isDark
        var seen = Set<CGDirectDisplayID>()

        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let album = spindle.state?.accent.map { RGBA(r: $0[0], g: $0[1], b: $0[2]) }
            let style = settings.appearance.style(for: screen, isDark: isDark).resolved(album: album)
            guard !style.isEmpty else { continue }
            seen.insert(id)

            let barHeight = MenuBarGeometry.height(of: screen)
            // The bar, flush with the top of the screen, plus room for the shadow fade.
            let depth = MenuBarStyleView.shadowDepth
            let frame = CGRect(x: screen.frame.minX, y: screen.frame.maxY - barHeight - depth,
                               width: screen.frame.width, height: barHeight + depth)
            let panel = panels[id] ?? makePanel()
            panels[id] = panel
            panel.setFrame(frame, display: false)

            model.layouts[id] = layout(for: screen, barHeight: barHeight, size: frame.size)
            model.styles[id] = style
            if panel.contentView == nil || !(panel.contentView is NSHostingView<OverlayRoot>) {
                panel.contentView = NSHostingView(rootView: OverlayRoot(model: model, displayID: id))
            }
            panel.orderFrontRegardless()
        }

        for (id, panel) in panels where !seen.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
    }

    private func layout(for screen: NSScreen, barHeight: CGFloat, size: CGSize) -> BarLayout {
        let left = screen.frame.minX
        var notch: ClosedRange<CGFloat>?
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            notch = (l.maxX - left)...(r.minX - left)
        }

        let isMain = screen == NSScreen.screens.first
        var statusStart = (isMain ? sections.leftmostVisibleX : nil).map { $0 - left } ?? size.width * 0.7
        var menusEnd = isMain ? max(appMenusEnd - left, 0) : 0
        if menusEnd <= 0 { menusEnd = size.width * 0.3 }

        // Keep the capsules from running under the notch, or under Spindle's pill when
        // it's showing — the pill already frames the notch on its own.
        if settings.avoidSpindle, isMain, let pill = spindle.state?.pillFrame, !pill.isEmpty {
            let pillRange = (pill.minX - left)...(pill.maxX - left)
            menusEnd = min(menusEnd, pillRange.lowerBound - 6)
            statusStart = max(statusStart, pillRange.upperBound + 6)
        } else if let notch {
            menusEnd = min(menusEnd, notch.lowerBound - 6)
            statusStart = max(statusStart, notch.upperBound + 6)
        }

        return BarLayout(size: size, barHeight: barHeight,
                         appMenusEnd: menusEnd, statusStart: statusStart, notch: notch)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // On top of the menu bar, the way Ice does it. Underneath would be cleaner in
        // theory, but on macOS 27 the menu bar draws its own background and icons in a
        // single window, so a tint below it may never be seen. Above, at Ice's
        // strength, everything shows through tinted. Clicks pass straight through, and
        // Spindle's notch panel (a few levels higher) stays on top.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.animationBehavior = .none
        return panel
    }

    func tearDown() {
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var layouts: [CGDirectDisplayID: BarLayout] = [:]
    @Published var styles: [CGDirectDisplayID: MenuBarStyle] = [:]
}

struct OverlayRoot: View {
    @ObservedObject var model: OverlayModel
    var displayID: CGDirectDisplayID

    var body: some View {
        if let layout = model.layouts[displayID], let style = model.styles[displayID] {
            MenuBarStyleView(style: style, layout: layout)
                .animation(.smooth(duration: 0.35), value: layout)
                .animation(.smooth(duration: 0.35), value: style)
        }
    }
}

/// The style itself, drawn into a bar-shaped area. Also used for the live preview in
/// Settings.
struct MenuBarStyleView: View {
    var style: MenuBarStyle
    var layout: BarLayout

    /// Ice's shadow: a short fade below the bar's bottom edge.
    static let shadowDepth: CGFloat = 5

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                let shape = RoundedRectangle(cornerRadius: radius(for: rect), style: .continuous)
                ZStack(alignment: .topLeading) {
                    // The tint sits over the whole bar, icons included, so it's kept
                    // light; intensity is how much of the colour comes through.
                    shape.fill(style.fillStyle).opacity(style.intensity)
                    if style.border && style.shape != .full {
                        shape.strokeBorder(style.borderColor.color, lineWidth: style.borderWidth)
                    }
                }
                .shadow(color: .black.opacity(style.shadow && style.shape != .full ? style.shadowOpacity : 0),
                        radius: 4, y: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            }

            if style.shape == .full {
                if style.border {
                    // A hairline along the bottom edge.
                    Rectangle()
                        .fill(style.borderColor.color)
                        .frame(width: layout.size.width, height: style.borderWidth)
                        .offset(y: layout.barHeight - style.borderWidth)
                }
                if style.shadow {
                    LinearGradient(colors: [.black.opacity(style.shadowOpacity * 0.6), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(width: layout.size.width, height: Self.shadowDepth)
                        .offset(y: layout.barHeight)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    private func radius(for rect: CGRect) -> CGFloat {
        style.shape == .full ? 0 : min(CGFloat(style.cornerRadius), rect.height / 2)
    }

    private var rects: [CGRect] {
        let inset = CGFloat(style.inset)
        let h = layout.barHeight
        switch style.shape {
        case .full:
            return [CGRect(x: 0, y: 0, width: layout.size.width, height: h)]
        case .rounded:
            return [CGRect(x: inset, y: inset, width: layout.size.width - inset * 2, height: h - inset * 2)]
        case .split:
            let pad: CGFloat = 8
            let leftWidth = max(layout.appMenusEnd + pad - inset, 40)
            let rightStart = max(layout.statusStart - pad, inset)
            return [
                CGRect(x: inset, y: inset, width: leftWidth, height: h - inset * 2),
                CGRect(x: rightStart, y: inset, width: layout.size.width - rightStart - inset, height: h - inset * 2)
            ]
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
