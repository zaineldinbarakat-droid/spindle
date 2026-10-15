import AppKit
import Combine
import SwiftUI

/// The fallback for hiding icons on macOS 27, used when native hiding is off or
/// unavailable — and for Apple's own icons, which native hiding always keeps.
///
/// It lays a clean capsule over each stretch of hidden icons: frosted glass, a quiet
/// "•••" to say something is tucked away there, and a click reveals it. The icons
/// keep their space in the bar, which is why native hiding is preferred.
///
/// An earlier version painted the desktop wallpaper into the cover so it would vanish
/// into the bar. Reading the wallpaper file froze Sleeve when it lived in a protected
/// folder (here, ~/Downloads): macOS put up a folder-access prompt and the main thread
/// waited on it. The cover now touches no files at all.
@MainActor
final class CoverController {
    private var panels: [NSPanel] = []
    private let models: [CoverModel] = (0..<8).map { _ in CoverModel() }
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
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
    }

    /// Contiguous stretches of icons to cover, left to right, in global AppKit x.
    /// Icons that stay visible split the stretches, so they're never covered.
    private func coveredRuns() -> [ClosedRange<CGFloat>] {
        let covered = sections.itemsNeedingCover()
        guard !covered.isEmpty else { return [] }
        let coveredIDs = Set(covered.map(\.id))
        let visible = sections.items.filter { !coveredIDs.contains($0.id) && !$0.isOverflowed && sections.isLive($0) }

        var runs: [ClosedRange<CGFloat>] = []
        for item in covered.sorted(by: { $0.frame.minX < $1.frame.minX }) {
            let range = (item.frame.minX - 2)...(item.frame.maxX + 2)
            if let last = runs.last,
               !visible.contains(where: { $0.frame.midX > last.upperBound && $0.frame.midX < range.lowerBound }) {
                runs[runs.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                runs.append(range)
            }
        }
        return Array(runs.prefix(models.count))
    }

    func update() {
        guard let screen = NSScreen.screens.first else { return hideAll() }
        let runs = coveredRuns()
        let strip = MenuBarGeometry.strip(of: screen)

        for (index, run) in runs.enumerated() {
            let frame = CGRect(x: run.lowerBound, y: strip.minY, width: run.upperBound - run.lowerBound,
                               height: strip.height)
            let panel = index < panels.count ? panels[index] : makePanel(model: models[index])
            if index >= panels.count { panels.append(panel) }
            models[index].size = frame.size
            panel.setFrame(frame, display: true)
            if !panel.isVisible {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }
        }
        for panel in panels.dropFirst(runs.count) where panel.isVisible {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in panel.orderOut(nil) }
            })
        }
    }

    private func hideAll() {
        panels.forEach { $0.orderOut(nil) }
    }

    private func makePanel(model: CoverModel) -> NSPanel {
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
        hideAll()
    }
}

private final class CoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CoverModel: ObservableObject {
    @Published var size: CGSize = .zero
}

/// A frosted capsule the height of an icon, with three dots in the middle.
private struct CoverView: View {
    @ObservedObject var model: CoverModel
    var onClick: () -> Void
    @State private var hovering = false

    var body: some View {
        let height = min(max(model.size.height - 10, 16), 24)
        let capsule = Capsule(style: .continuous)

        ZStack {
            Group {
                if #available(macOS 26, *) {
                    // Opaque enough that nothing underneath shows through.
                    Color.clear.glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.85)), in: capsule)
                } else {
                    capsule.fill(.regularMaterial)
                        .overlay(capsule.fill(Color(nsColor: .windowBackgroundColor).opacity(0.75)))
                }
            }
            .overlay(capsule.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().frame(width: 3.5, height: 3.5)
                }
            }
            .foregroundStyle(Color.primary.opacity(hovering ? 0.75 : 0.45))
        }
        .frame(width: max(model.size.width - 4, height), height: height)
        .frame(width: model.size.width, height: model.size.height)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onTapGesture(perform: onClick)
        .help("Hidden by Sleeve — click to show")
    }
}
