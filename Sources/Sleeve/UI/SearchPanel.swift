import AppKit
import SwiftUI

/// Spotlight-style finder for menu bar icons: type, arrow, return — the icon's menu
/// opens, even if it's hidden.
@MainActor
final class SearchController {
    private var panel: SearchPanel?
    private unowned let sections: SectionManager
    private let model = SearchModel()

    init(sections: SectionManager) {
        self.sections = sections
    }

    func toggle() {
        if panel?.isVisible == true { close() } else { open() }
    }

    func open() {
        sections.rescan()
        model.query = ""
        model.selection = 0
        model.source = { [weak self] in
            guard let self else { return [] }
            return self.sections.items.map { ($0, self.sections.section(of: $0)) }
        }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let size = CGSize(width: 520, height: 360)
            panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2,
                                  y: screen.frame.maxY - size.height - screen.frame.height * 0.18,
                                  width: size.width, height: size.height), display: true)
        }
        // Typing needs key focus, which an accessory app only gets by activating.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.focusToken = UUID()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> SearchPanel {
        let panel = SearchPanel(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onResignKey = { [weak self] in self?.close() }
        panel.contentView = NSHostingView(rootView: SearchView(model: model,
            onPick: { [weak self] item in
                guard let self else { return }
                self.close()
                Task { await self.sections.activate(item) }
            },
            onCancel: { [weak self] in self?.close() }))
        return panel
    }
}

final class SearchPanel: NSPanel {
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
    @Published var focusToken = UUID()
    var source: () -> [(MenuBarItem, MenuBarSection)] = { [] }

    var results: [(MenuBarItem, MenuBarSection)] {
        let all = source()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all
            .map { ($0, Self.score($0.0.displayName.lowercased(), q)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Prefix beats word-start beats substring beats in-order letters.
    private static func score(_ text: String, _ query: String) -> Int {
        if text.hasPrefix(query) { return 4 }
        if text.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 3 }
        if text.contains(query) { return 2 }
        var index = text.startIndex
        for ch in query {
            guard let found = text[index...].firstIndex(of: ch) else { return 0 }
            index = text.index(after: found)
        }
        return 1
    }
}

struct SearchView: View {
    @ObservedObject var model: SearchModel
    var onPick: (MenuBarItem) -> Void
    var onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search menu bar items", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($focused)
                    .onSubmit {
                        if results.indices.contains(model.selection) { onPick(results[model.selection].0) }
                    }
                    .onKeyPress(.downArrow) {
                        model.selection = min(model.selection + 1, max(results.count - 1, 0)); return .handled
                    }
                    .onKeyPress(.upArrow) {
                        model.selection = max(model.selection - 1, 0); return .handled
                    }
                    .onKeyPress(.escape) { onCancel(); return .handled }
            }
            .padding(14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.0.id) { index, pair in
                            row(pair.0, pair.1, selected: index == model.selection)
                                .id(index)
                                .onTapGesture { onPick(pair.0) }
                        }
                        if results.isEmpty {
                            Text(AXIsProcessTrusted() ? "No matches" : "Sleeve needs Accessibility access to see menu bar items.")
                                .foregroundStyle(.secondary)
                                .padding(30)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selection) { _, new in proxy.scrollTo(new) }
            }
        }
        .background(background)
        .onChange(of: model.query) { _, _ in model.selection = 0 }
        .onChange(of: model.focusToken) { _, _ in focused = true }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }

    private func row(_ item: MenuBarItem, _ section: MenuBarSection, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: item.icon)
                .resizable()
                .renderingMode(item.isSystemItem ? .template : .original)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            Text(item.displayName).lineLimit(1)
            Spacer()
            Text(section.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
        .contentShape(Rectangle())
    }
}
