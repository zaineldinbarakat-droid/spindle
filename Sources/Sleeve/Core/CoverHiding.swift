import AppKit
import Combine
import SwiftUI

/// How hidden icons are hidden on macOS 27 and later.
///
/// Every menu bar manager before macOS 27 hid icons by stretching a divider item to
/// 10 000 pt so it shoved its neighbours off the screen. macOS 27 moved status item
/// layout into MenuBarAgent, which caps item width, so the divider no longer pushes
/// anything anywhere (measured: an icon "behind" a 10 000 pt divider moved 20 pt).
/// The real layout now lives in a protected container no third-party app can write.
///
/// So on 27+, Sleeve covers the hidden stretch of the bar instead: a panel just above
/// the status icons that paints exactly what the empty menu bar would look like there —
/// the wallpaper, cropped and scaled the way the desktop shows it, plus any Sleeve
/// style — and swallows clicks (a click on it reveals). Icons keep their space in the
/// bar, but they're out of sight and out of the way.
@MainActor
final class CoverController {
    private var panel: NSPanel?
    private let model = CoverModel()
    private unowned let sections: SectionManager
    private let settings = SleeveSettings.shared
    private var cancellables = Set<AnyCancellable>()

    /// Clicking the cover is the obvious "show me what's under here" gesture.
    var onClick: (() -> Void)?

    init(sections: SectionManager) {
        self.sections = sections
        sections.$items
            .combineLatest(sections.$state)
            .sink { [weak self] _, _ in DispatchQueue.main.async { self?.update() } }
            .store(in: &cancellables)
        settings.$appearance
            .sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }
            .store(in: &cancellables)
        // The wallpaper differs per Space; re-read it whenever the Space changes.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.model.wallpaperKey = nil; self?.update() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.model.wallpaperKey = nil; self?.update() }
            .store(in: &cancellables)
    }

    /// The stretch of bar to cover for the current reveal state, in global AppKit
    /// coordinates, or nil when nothing needs covering.
    private func coveredRange() -> ClosedRange<CGFloat>? {
        let hiddenItems: [MenuBarItem]
        switch sections.state {
        case .collapsed:
            hiddenItems = sections.items(in: .hidden) + sections.items(in: .alwaysHidden)
        case .hidden:
            hiddenItems = sections.items(in: .alwaysHidden)
        case .all:
            hiddenItems = []
        }
        guard !hiddenItems.isEmpty, let screen = NSScreen.screens.first else { return nil }

        var minX = hiddenItems.map(\.frame.minX).min() ?? 0
        var maxX = hiddenItems.map(\.frame.maxX).max() ?? 0
        // Include our own dividers, which sit at the right end of each hidden stretch.
        if sections.state == .collapsed, let divider = sections.dividerFrame { maxX = max(maxX, divider.maxX) }
        if let always = sections.alwaysDividerFrame { maxX = max(maxX, always.maxX) }
        minX = max(minX - 2, screen.frame.minX)
        maxX = min(maxX + 1, sections.toggleFrame?.minX ?? maxX)
        guard maxX > minX else { return nil }
        return minX...maxX
    }

    func update() {
        guard let range = coveredRange(), let screen = NSScreen.screens.first else {
            hide()
            return
        }
        let strip = MenuBarGeometry.strip(of: screen)
        let frame = CGRect(x: range.lowerBound, y: strip.minY, width: range.upperBound - range.lowerBound,
                           height: strip.height)

        refreshWallpaper(for: screen)
        model.screenFrame = screen.frame
        model.coverFrame = frame
        model.barHeight = strip.height
        model.style = settings.appearance.style(for: screen, isDark: SystemAppearance.isDark)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                // Re-check: a re-hide may have arrived during the fade.
                if self.coveredRange() == nil { panel.orderOut(nil) }
            }
        })
    }

    private func refreshWallpaper(for screen: NSScreen) {
        let url = NSWorkspace.shared.desktopImageURL(for: screen)
        let key = url?.path ?? "none"
        guard model.wallpaperKey != key else { return }
        model.wallpaperKey = key
        model.wallpaper = url.flatMap { NSImage(contentsOf: $0) }
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        model.fillColor = (options[.fillColor] as? NSColor).map(Color.init) ?? .black
        let scaling = (options[.imageScaling] as? NSNumber).map { NSImageScaling(rawValue: $0.uintValue) }
        model.fitsInsteadOfFills = scaling == .scaleProportionallyUpOrDown
            && (options[.allowClipping] as? Bool) == false
    }

    private func makePanel() -> NSPanel {
        let panel = CoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Just above the status icons; below Zen (+1) and Spindle's notch panel (+3).
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        let hosting = NSHostingView(rootView: CoverView(model: model, onClick: { [weak self] in self?.onClick?() }))
        hosting.wantsLayer = true
        panel.contentView = hosting
        return panel
    }

    func tearDown() {
        panel?.orderOut(nil)
    }
}

private final class CoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CoverModel: ObservableObject {
    @Published var wallpaper: NSImage?
    var wallpaperKey: String?
    @Published var fillColor: Color = .black
    @Published var fitsInsteadOfFills = false
    @Published var screenFrame: CGRect = .zero
    @Published var coverFrame: CGRect = .zero
    @Published var barHeight: CGFloat = 24
    @Published var style = MenuBarStyle()
}

/// The wallpaper, laid out at full screen size exactly as the desktop shows it, then
/// shifted so only the covered slice shows; the Sleeve style goes on top so a styled
/// bar stays seamless across the cover.
private struct CoverView: View {
    @ObservedObject var model: CoverModel
    var onClick: () -> Void

    var body: some View {
        let offsetX = model.screenFrame.minX - model.coverFrame.minX
        ZStack(alignment: .topLeading) {
            model.fillColor

            if let wallpaper = model.wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: model.fitsInsteadOfFills ? .fit : .fill)
                    .frame(width: model.screenFrame.width, height: model.screenFrame.height)
                    .clipped()
                    .offset(x: offsetX)
            } else {
                // No readable wallpaper (some dynamic/aerial ones): blur what's behind.
                VisualEffectBlur()
            }

            if !model.style.isEmpty {
                MenuBarStyleView(style: model.style, layout: BarLayout(
                    size: CGSize(width: model.screenFrame.width, height: model.barHeight),
                    barHeight: model.barHeight,
                    appMenusEnd: 0, statusStart: model.coverFrame.minX - model.screenFrame.minX,
                    notch: nil))
                    .offset(x: offsetX)
            }
        }
        .frame(width: model.coverFrame.width, height: model.coverFrame.height, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onClick)
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
