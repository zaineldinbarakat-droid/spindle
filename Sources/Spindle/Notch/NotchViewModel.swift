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
    @Published private(set) var metrics: NotchMetrics = {
        var metrics = NotchMetrics.current()
        metrics.panelScale = CGFloat(Defaults.double(.panelScale, default: PanelPreset.standard.scale))
        metrics.panelWidthFactor = CGFloat(Defaults.double(.panelWidth, default: PanelPreset.standard.width))
        metrics.panelHeightFactor = CGFloat(Defaults.double(.panelHeight, default: PanelPreset.standard.height))
        return metrics
    }()
    var metricsPublisher: AnyPublisher<NotchMetrics, Never> { $metrics.eraseToAnyPublisher() }
    /// Set while the tonearm is held, so the panel cannot close mid-drag.
    @Published var isInteracting = false
    @Published var tab: Tab = .player

    // MARK: Panel size and feel (Settings → Panel)

    /// Overall size, relative to the original design: everything scales together.
    @Published var panelScale: Double = Defaults.double(.panelScale, default: PanelPreset.standard.scale) {
        didSet { Defaults.set(.panelScale, panelScale); syncPanelMetrics() }
    }
    /// Extra width: more room between the cover and the controls, a longer progress bar.
    @Published var panelWidth: Double = Defaults.double(.panelWidth, default: PanelPreset.standard.width) {
        didSet { Defaults.set(.panelWidth, panelWidth); syncPanelMetrics() }
    }
    /// Extra height: more room above and below the content.
    @Published var panelHeight: Double = Defaults.double(.panelHeight, default: PanelPreset.standard.height) {
        didSet { Defaults.set(.panelHeight, panelHeight); syncPanelMetrics() }
    }
    /// The panel's lower corners, in points at 100 % size.
    @Published var panelCornerRadius: Double = Defaults.double(.panelCornerRadius, default: PanelPreset.standard.cornerRadius) {
        didSet { Defaults.set(.panelCornerRadius, panelCornerRadius) }
    }
    /// The album cover or record, relative to its usual size.
    @Published var coverScale: Double = Defaults.double(.coverScale, default: PanelPreset.standard.cover) {
        didSet { Defaults.set(.coverScale, coverScale) }
    }
    /// How the panel springs open and tucks away.
    @Published var motion: NotchMotion = NotchMotion.current {
        didSet { Defaults.set(.notchMotion, motion.rawValue) }
    }
    /// How long the panel waits after the cursor leaves before closing.
    @Published var closeDelay: Double = Defaults.double(.closeDelay, default: 0.08) {
        didSet { Defaults.set(.closeDelay, closeDelay) }
    }

    static let panelScaleRange: ClosedRange<Double> = 0.75...Double(NotchMetrics.maxPanelScale)
    static let panelWidthRange: ClosedRange<Double> = 0.85...Double(NotchMetrics.maxPanelWidthFactor)
    static let panelHeightRange: ClosedRange<Double> = 0.9...Double(NotchMetrics.maxPanelHeightFactor)
    static let cornerRadiusRange: ClosedRange<Double> = 8...40
    static let coverScaleRange: ClosedRange<Double> = 0.8...1.1
    static let closeDelayRange: ClosedRange<Double> = 0...0.8

    /// The preset matching the current settings, if any.
    var currentPreset: PanelPreset? {
        PanelPreset.all.first { $0.matches(self) }
    }

    func apply(_ preset: PanelPreset) {
        panelScale = preset.scale
        panelWidth = preset.width
        panelHeight = preset.height
        panelCornerRadius = preset.cornerRadius
        coverScale = preset.cover
    }

    private func syncPanelMetrics() {
        var new = metrics
        new.panelScale = CGFloat(panelScale)
        new.panelWidthFactor = CGFloat(panelWidth)
        new.panelHeightFactor = CGFloat(panelHeight)
        if new != metrics { metrics = new }
    }

    /// Kept open while a panel setting is being adjusted, as a live preview.
    @Published var isPreviewingSize = false

    /// How far a two-finger swipe has dragged the tabs, in points (0 at rest).
    @Published var swipeOffset: CGFloat = 0
    /// The spring tabs settle with, after a swipe or a tap on the switcher: quick and
    /// without overshoot, the way macOS settles a page swipe.
    static let pageSpring = Animation.spring(duration: 0.32, bounce: 0)
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
    @Published var indicatorColorMode: IndicatorColor = IndicatorColor(rawValue: Defaults.string(.indicatorColorMode) ?? "") ?? .white {
        didSet { Defaults.set(.indicatorColorMode, indicatorColorMode.rawValue) }
    }
    @Published var indicatorCustomColor: Color = NotchViewModel.loadColor(Defaults.string(.indicatorCustomColor)) {
        didSet { Defaults.set(.indicatorCustomColor, NotchViewModel.saveColor(indicatorCustomColor)) }
    }
    /// 0.3 (soft) … 1 (bright).
    @Published var indicatorBrightness: Double = Defaults.double(.indicatorBrightness, default: 0.65) {
        didSet { Defaults.set(.indicatorBrightness, indicatorBrightness) }
    }
    /// 0 (no glow) … 1 (strong halo).
    @Published var indicatorGlow: Double = Defaults.double(.indicatorGlow, default: 0) {
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
    @Published var collapsedShowsCover: Bool = Defaults.bool(.collapsedShowsCover, default: false) {
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
    /// The waves, larger, beside the controls in the open panel.
    @Published var panelWaves: Bool = Defaults.bool(.panelWaves, default: true) {
        didSet { Defaults.set(.panelWaves, panelWaves) }
    }
    /// How dramatic live waves are: 0 calm … 1 wild.
    @Published var waveIntensity: Double = Defaults.double(.waveIntensity, default: 0.53) {
        didSet {
            Defaults.set(.waveIntensity, waveIntensity)
            AudioLevels.shared.intensity = Float(waveIntensity)
        }
    }
    /// Waves that move with the song's actual sound (system audio, with permission).
    @Published var liveWaves: Bool = Defaults.bool(.liveWaves, default: true) {
        didSet {
            Defaults.set(.liveWaves, liveWaves)
            if liveWaves { AudioLevels.shared.retry() }
        }
    }

    var isExpanded: Bool { state == .expanded }

    func expand() {
        guard state != .expanded, !isZenHidden else { return }
        withAnimation(.notch) { state = .expanded }
        // The playhead is only re-synced every few seconds; opening is when it shows.
        AppEnvironment.shared.player.refresh()
    }

    func collapse() {
        guard state != .collapsed, !isInteracting, !isPreviewingSize else { return }
        withAnimation(.notchClose) { state = .collapsed }
    }

    func toggle() {
        if state == .expanded { withAnimation(.notchClose) { state = .collapsed } }
        else if !isZenHidden { withAnimation(.notch) { state = .expanded } }
    }

    func updateMetrics(_ new: NotchMetrics) {
        var new = new
        new.panelScale = CGFloat(panelScale)
        new.panelWidthFactor = CGFloat(panelWidth)
        new.panelHeightFactor = CGFloat(panelHeight)
        guard new != metrics else { return }
        metrics = new
    }
}

/// A ready-made shape for the open panel (Settings → Panel).
struct PanelPreset: Identifiable, Equatable {
    var name: String
    var scale: Double
    var width: Double
    var height: Double
    var cornerRadius: Double
    var cover: Double
    var id: String { name }

    static let compact = PanelPreset(name: "Compact", scale: 0.82, width: 0.92, height: 0.95, cornerRadius: 18, cover: 0.95)
    static let standard = PanelPreset(name: "Standard", scale: 0.9, width: 1.0, height: 1.0, cornerRadius: 22, cover: 1.0)
    static let wide = PanelPreset(name: "Wide", scale: 0.9, width: 1.25, height: 1.0, cornerRadius: 24, cover: 1.0)
    static let cinema = PanelPreset(name: "Cinema", scale: 0.95, width: 1.4, height: 0.92, cornerRadius: 30, cover: 1.0)
    static let tall = PanelPreset(name: "Tall", scale: 0.9, width: 1.0, height: 1.22, cornerRadius: 28, cover: 1.08)
    static let all = [compact, standard, wide, cinema, tall]

    /// The panel's proportions, for the little silhouettes in Settings.
    var aspect: CGFloat { CGFloat(width * 500) / CGFloat(height * 168) }

    @MainActor func matches(_ model: NotchViewModel) -> Bool {
        abs(model.panelScale - scale) < 0.005 && abs(model.panelWidth - width) < 0.005
            && abs(model.panelHeight - height) < 0.005 && abs(model.panelCornerRadius - cornerRadius) < 0.5
            && abs(model.coverScale - cover) < 0.005
    }
}
