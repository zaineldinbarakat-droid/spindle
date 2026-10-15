import SwiftUI
import Combine

@MainActor
final class NotchViewModel: ObservableObject {
    enum State: Equatable {
        case collapsed
        case expanded
    }

    /// How the notch is painted.
    enum Style: String, CaseIterable, Identifiable {
        /// Pure black, so it reads as part of the hardware notch.
        case black
        /// A deep wash of the current cover's colour.
        case songColor
        /// macOS 26 Liquid Glass, tinted with the cover's colour.
        case liquidGlass

        var id: String { rawValue }

        var title: String {
            switch self {
            case .black: return "Black"
            case .songColor: return "Song Color"
            case .liquidGlass: return "Liquid Glass"
            }
        }

        static var isGlassAvailable: Bool {
            if #available(macOS 26, *) { return true }
            return false
        }
    }

    /// What the expanded panel shows.
    enum Tab: Equatable {
        case player
        case focus
    }

    @Published private(set) var state: State = .collapsed

    /// `$state` is unreachable from other types once the setter is private, so the
    /// window controller gets the stream through here instead.
    var statePublisher: AnyPublisher<State, Never> { $state.eraseToAnyPublisher() }
    @Published private(set) var metrics: NotchMetrics = .current()
    var metricsPublisher: AnyPublisher<NotchMetrics, Never> { $metrics.eraseToAnyPublisher() }
    /// Set while the tonearm is held, so the panel cannot close mid-drag.
    @Published var isInteracting = false
    @Published var tab: Tab = .player
    /// Set while Sleeve's Zen mode is on: the whole notch UI steps out of the way.
    @Published var isZenHidden = false
    @Published var style: Style = Style(rawValue: Defaults.string(.notchStyle) ?? "") ?? .black {
        didSet { Defaults.set(.notchStyle, style.rawValue) }
    }

    // Backed by UserDefaults by hand rather than with @AppStorage: inside an
    // ObservableObject that wrapper writes the value but never fires objectWillChange,
    // so flipping a switch in Settings would not reach the panel until the next launch.
    @Published var openOnHover: Bool = Defaults.bool(.openOnHover, default: true) {
        didSet { Defaults.set(.openOnHover, openOnHover) }
    }
    @Published var showVisualizer: Bool = Defaults.bool(.showVisualizer, default: true) {
        didSet { Defaults.set(.showVisualizer, showVisualizer) }
    }

    var isExpanded: Bool { state == .expanded }

    func expand() {
        guard state != .expanded, !isZenHidden else { return }
        withAnimation(.notch) { state = .expanded }
    }

    func collapse() {
        guard state != .collapsed, !isInteracting else { return }
        withAnimation(.notchClose) { state = .collapsed }
    }

    func toggle() {
        if state == .expanded { withAnimation(.notchClose) { state = .collapsed } }
        else if !isZenHidden { withAnimation(.notch) { state = .expanded } }
    }

    func updateMetrics(_ new: NotchMetrics) {
        guard new != metrics else { return }
        metrics = new
    }
}
