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
    @Published var style: Style = Style(rawValue: Defaults.string(.notchStyle) ?? "") ?? .songColor {
        didSet { Defaults.set(.notchStyle, style.rawValue) }
    }
    /// Song Color only: let the colour reach the collapsed pill and the strip beside
    /// the camera. Off keeps everything around the notch hardware-black.
    @Published var tintNotch: Bool = Defaults.bool(.tintNotch, default: false) {
        didSet { Defaults.set(.tintNotch, tintNotch) }
    }
    /// A soft glow of the album's colour behind the cover in the open notch. Off by
    /// default: around the cover is simply the notch's own look (black, song colour or
    /// glass), with nothing rising from behind it.
    @Published var coverGlow: Bool = Defaults.bool(.coverGlow, default: false) {
        didSet { Defaults.set(.coverGlow, coverGlow) }
    }
    // MARK: Liquid Glass

    /// 0 = frosted (Apple's regular glass, blurred and dimmed for legibility) … 1 =
    /// clear (Apple's clear glass: see-through, just refracting at the edges).
    @Published var glassClarity: Double = Defaults.double(.glassClarity, default: 0.6) {
        didSet { Defaults.set(.glassClarity, glassClarity) }
    }
    /// Tint the glass with the album's colour.
    @Published var glassTinted: Bool = Defaults.bool(.glassTinted, default: true) {
        didSet { Defaults.set(.glassTinted, glassTinted) }
    }

    // MARK: Playing indicator (the glow on the right of the collapsed notch)

    enum IndicatorStyle: String, CaseIterable, Identifiable {
        case bars, wave, pulse
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum IndicatorColor: String, CaseIterable, Identifiable {
        /// The cover's own colour, changing with every song.
        case album
        /// Monotone white.
        case white
        /// One colour of the user's choosing.
        case custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .album: return "Album"
            case .white: return "White"
            case .custom: return "Custom"
            }
        }
    }

    @Published var indicatorStyle: IndicatorStyle = IndicatorStyle(rawValue: Defaults.string(.indicatorStyle) ?? "") ?? .bars {
        didSet { Defaults.set(.indicatorStyle, indicatorStyle.rawValue) }
    }
    @Published var indicatorColorMode: IndicatorColor = IndicatorColor(rawValue: Defaults.string(.indicatorColorMode) ?? "") ?? .album {
        didSet { Defaults.set(.indicatorColorMode, indicatorColorMode.rawValue) }
    }
    @Published var indicatorCustomColor: Color = NotchViewModel.loadColor(Defaults.string(.indicatorCustomColor)) {
        didSet { Defaults.set(.indicatorCustomColor, NotchViewModel.saveColor(indicatorCustomColor)) }
    }
    /// 0.3 (soft) … 1 (bright).
    @Published var indicatorBrightness: Double = Defaults.double(.indicatorBrightness, default: 0.85) {
        didSet { Defaults.set(.indicatorBrightness, indicatorBrightness) }
    }
    /// 0 (no glow) … 1 (strong halo).
    @Published var indicatorGlow: Double = Defaults.double(.indicatorGlow, default: 0.6) {
        didSet { Defaults.set(.indicatorGlow, indicatorGlow) }
    }

    func indicatorColor(accent: Color) -> Color {
        switch indicatorColorMode {
        case .album: return accent
        case .white: return .white
        case .custom: return indicatorCustomColor
        }
    }

    private static func loadColor(_ string: String?) -> Color {
        let parts = (string ?? "").split(separator: ",").compactMap { Double($0) }
        guard parts.count == 3 else { return Color(red: 0.55, green: 0.85, blue: 1.0) }
        return Color(.sRGB, red: parts[0], green: parts[1], blue: parts[2])
    }

    private static func saveColor(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return "\(ns.redComponent),\(ns.greenComponent),\(ns.blueComponent)"
    }

    /// The collapsed notch's left wing: the album cover (default) or the spinning record.
    @Published var collapsedShowsCover: Bool = Defaults.bool(.collapsedShowsCover, default: true) {
        didSet { Defaults.set(.collapsedShowsCover, collapsedShowsCover) }
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
