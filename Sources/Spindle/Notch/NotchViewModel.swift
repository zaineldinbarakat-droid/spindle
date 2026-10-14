import SwiftUI
import Combine

@MainActor
final class NotchViewModel: ObservableObject {
    enum State: Equatable {
        case collapsed
        case expanded
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
    /// Set while the tonearm is held, so the panel cannot close mid-drag.
    @Published var isInteracting = false
    @Published var tab: Tab = .player

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
        guard state != .expanded else { return }
        withAnimation(.notch) { state = .expanded }
    }

    func collapse() {
        guard state != .collapsed, !isInteracting else { return }
        withAnimation(.notch) { state = .collapsed }
    }

    func toggle() {
        if state == .expanded { withAnimation(.notch) { state = .collapsed } }
        else { withAnimation(.notch) { state = .expanded } }
    }

    func updateMetrics(_ new: NotchMetrics) {
        guard new != metrics else { return }
        metrics = new
    }
}
