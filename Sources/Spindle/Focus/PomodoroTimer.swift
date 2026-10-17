import AppKit
import Combine
import SwiftUI
import UserNotifications

/// A Pomodoro cycle: focus, short break, repeat, with a long break every N sessions.
///
/// Time is kept as a wall-clock deadline rather than a decrementing counter, so sleep,
/// a stalled main thread or timer coalescing can never make the countdown drift. The
/// 1 Hz tick only exists to publish the new value and runs only while counting.
@MainActor
final class PomodoroTimer: ObservableObject {

    enum Phase: String, CaseIterable {
        case focus
        case shortBreak
        case longBreak

        var title: String {
            switch self {
            case .focus: return "Lock In"
            case .shortBreak: return "Short Break"
            case .longBreak: return "Long Break"
            }
        }

        var symbol: String {
            switch self {
            case .focus: return "brain.head.profile"
            case .shortBreak: return "cup.and.saucer.fill"
            case .longBreak: return "sofa.fill"
            }
        }

        var color: Color {
            switch self {
            case .focus: return Theme.focusColor
            case .shortBreak: return Theme.breakColor
            case .longBreak: return Theme.longBreakColor
            }
        }

        var isBreak: Bool { self != .focus }
    }

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var isRunning = false
    var runningPublisher: AnyPublisher<Bool, Never> { $isRunning.eraseToAnyPublisher() }
    /// Seconds left in the current phase.
    @Published private(set) var remaining: TimeInterval
    /// Focus sessions finished since the last reset; drives the long-break cadence.
    @Published private(set) var completedSessions = 0

    // Settings, persisted by hand for the reason given in NotchViewModel.
    @Published var focusMinutes: Int = Defaults.int(.focusMinutes, default: 25) {
        didSet { Defaults.set(.focusMinutes, focusMinutes); settingsChanged(.focus) }
    }
    @Published var shortBreakMinutes: Int = Defaults.int(.shortBreakMinutes, default: 5) {
        didSet { Defaults.set(.shortBreakMinutes, shortBreakMinutes); settingsChanged(.shortBreak) }
    }
    @Published var longBreakMinutes: Int = Defaults.int(.longBreakMinutes, default: 15) {
        didSet { Defaults.set(.longBreakMinutes, longBreakMinutes); settingsChanged(.longBreak) }
    }
    @Published var sessionsBeforeLongBreak: Int = Defaults.int(.sessionsBeforeLongBreak, default: 4) {
        didSet { Defaults.set(.sessionsBeforeLongBreak, sessionsBeforeLongBreak) }
    }
    @Published var autoStartNextPhase: Bool = Defaults.bool(.autoStartNextPhase, default: true) {
        didSet { Defaults.set(.autoStartNextPhase, autoStartNextPhase) }
    }
    @Published var pauseMusicOnBreak: Bool = Defaults.bool(.pauseMusicOnBreak, default: false) {
        didSet { Defaults.set(.pauseMusicOnBreak, pauseMusicOnBreak) }
    }
    @Published var resumeMusicOnFocus: Bool = Defaults.bool(.resumeMusicOnFocus, default: false) {
        didSet { Defaults.set(.resumeMusicOnFocus, resumeMusicOnFocus) }
    }
    @Published var peekNotchOnPhaseEnd: Bool = Defaults.bool(.peekNotchOnPhaseEnd, default: true) {
        didSet { Defaults.set(.peekNotchOnPhaseEnd, peekNotchOnPhaseEnd) }
    }

    // MARK: - Presets

    struct Preset: Identifiable, Equatable {
        var id: String { name }
        var name: String
        var focus: Int
        var shortBreak: Int
        var longBreak: Int

        /// Francesco Cirillo's original timings.
        static let classic = Preset(name: "Classic · 25 / 5", focus: 25, shortBreak: 5, longBreak: 15)
        /// Longer blocks for deep work: fewer interruptions, a proper break each time.
        static let deepWork = Preset(name: "Deep Work · 50 / 10", focus: 50, shortBreak: 10, longBreak: 30)

        static let all = [classic, deepWork]
    }

    /// The preset the current durations match, or nil if they've been customised.
    var currentPreset: Preset? {
        Preset.all.first {
            $0.focus == focusMinutes && $0.shortBreak == shortBreakMinutes && $0.longBreak == longBreakMinutes
        }
    }

    /// Switches timings. A phase already counting keeps its clock; the new lengths
    /// apply from the next phase (or immediately, if nothing has started yet).
    func apply(_ preset: Preset) {
        focusMinutes = preset.focus
        shortBreakMinutes = preset.shortBreak
        longBreakMinutes = preset.longBreak
    }

    /// Called after a phase ends, with the phase that is now current.
    var onPhaseChange: ((Phase) -> Void)?

    private weak var player: PlayerManager?
    private var deadline: Date?
    /// Whether the current phase has ever been started; distinguishes paused from fresh.
    @Published private var phaseStarted = false
    private var ticker: Timer?
    /// True when we paused the music for a break, so focus only resumes what we stopped.
    private var pausedMusicForBreak = false

    init(player: PlayerManager) {
        self.player = player
        remaining = TimeInterval(Defaults.int(.focusMinutes, default: 25) * 60)
    }

    // MARK: - Derived

    func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: return TimeInterval(focusMinutes * 60)
        case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(longBreakMinutes * 60)
        }
    }

    /// 0 at the start of the phase, 1 when it ends.
    var progress: Double {
        let total = duration(of: phase)
        guard total > 0 else { return 0 }
        return min(max(1 - remaining / total, 0), 1)
    }

    /// Paused part-way through, as opposed to sitting at a fresh phase.
    var isPaused: Bool { !isRunning && phaseStarted }

    /// Worth showing in the collapsed notch: counting, or paused mid-phase.
    var isActive: Bool { isRunning || isPaused }

    /// Position within the current set of sessions, for the progress dots.
    var sessionInSet: Int {
        let set = max(sessionsBeforeLongBreak, 1)
        return completedSessions % set
    }

    var remainingString: String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        requestNotificationPermissionOnce()
        if remaining <= 0 { remaining = duration(of: phase) }
        deadline = Date().addingTimeInterval(remaining)
        isRunning = true
        phaseStarted = true
        startTicker()
        if phase == .focus { resumeMusicIfNeeded() }
    }

    func pause() {
        guard isRunning else { return }
        tick()
        isRunning = false
        deadline = nil
        stopTicker()
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    /// Back to a fresh focus session and an empty set.
    func reset() {
        stopTicker()
        isRunning = false
        deadline = nil
        phase = .focus
        phaseStarted = false
        completedSessions = 0
        remaining = duration(of: .focus)
    }

    /// Ends the current phase now, as if its time had run out — but quietly.
    func skip() {
        advance(announce: false)
    }

    // MARK: - Ticking

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let deadline else { return }
        remaining = max(deadline.timeIntervalSinceNow, 0)
        if remaining <= 0 { advance(announce: true) }
    }

    private func advance(announce: Bool) {
        let wasRunning = isRunning
        let finished = phase
        stopTicker()
        isRunning = false
        deadline = nil
        phaseStarted = false

        if finished == .focus {
            completedSessions += 1
            let set = max(sessionsBeforeLongBreak, 1)
            phase = completedSessions % set == 0 ? .longBreak : .shortBreak
        } else {
            phase = .focus
        }
        remaining = duration(of: phase)

        if phase.isBreak { pauseMusicIfNeeded() }

        if announce {
            NSSound(named: phase.isBreak ? "Glass" : "Hero")?.play()
            postNotification(finished: finished)
        }

        if autoStartNextPhase && (wasRunning || announce) {
            start()
        }
        onPhaseChange?(phase)
    }

    /// Changing a duration in Settings applies straight away to a phase that hasn't
    /// started, but never yanks the clock out from under one that is counting.
    private func settingsChanged(_ changed: Phase) {
        guard changed == phase, !phaseStarted else { return }
        remaining = duration(of: phase)
    }

    // MARK: - Music

    private func pauseMusicIfNeeded() {
        guard pauseMusicOnBreak, let player, player.snapshot.isPlaying else { return }
        player.pause()
        pausedMusicForBreak = true
    }

    private func resumeMusicIfNeeded() {
        guard let player else { return }
        // Resume what a break paused; optionally also start music for any focus session.
        if pausedMusicForBreak || resumeMusicOnFocus {
            player.play()
        }
        pausedMusicForBreak = false
    }

    // MARK: - Notifications

    private var askedForNotifications = false

    private func requestNotificationPermissionOnce() {
        guard !askedForNotifications else { return }
        askedForNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(finished: Phase) {
        let content = UNMutableNotificationContent()
        if finished == .focus {
            content.title = "Lock-in session done"
            content.body = phase == .longBreak
                ? "Nice work — take a \(longBreakMinutes)-minute long break."
                : "Take a \(shortBreakMinutes)-minute breather."
        } else {
            content.title = "Break's over"
            content.body = "Back to it: time to lock in for \(focusMinutes) minutes."
        }
        let request = UNNotificationRequest(identifier: "spindle.pomodoro",
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
