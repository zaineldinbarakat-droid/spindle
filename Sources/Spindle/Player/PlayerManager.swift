import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Owns provider selection, polling and the scrub interaction.
///
/// Polling runs at 1 Hz. Everything smoother than that (the progress bar, the spinning
/// record) is interpolated from `positionAnchor`, so we get 120 fps motion out of one
/// Apple Event per second.
@MainActor
final class PlayerManager: ObservableObject {

    @Published private(set) var snapshot: PlaybackSnapshot = .idle(.appleMusic)
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = Theme.defaultAccent
    @Published private(set) var availableProviders: [ProviderID] = []
    @Published private(set) var deniedProviders: Set<ProviderID> = []
    @Published private(set) var lastErrorMessage: String?

    /// Non-nil while the user is dragging the tonearm.
    @Published var scrubFraction: Double?

    /// `nonisolated` because polling reads this from a background queue. Safe: the
    /// dictionary is a `let`, and the providers hold no mutable state of their own.
    nonisolated private let providers: [ProviderID: MusicProvider] = [
        .appleMusic: AppleMusicProvider(),
        .spotify: SpotifyProvider()
    ]
    private let artworkLoader = ArtworkLoader()
    private let work = DispatchQueue(label: "com.spindle.player", qos: .userInitiated)

    /// Which provider the UI is following. Nil means "whichever one is playing".
    /// Published by hand so the picker's checkmark updates; see NotchViewModel.
    @Published private var pinnedProviderRaw: String = Defaults.string(.pinnedProvider) ?? ""

    private var activeProviderID: ProviderID = .appleMusic
    private var pollTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    /// Wall-clock reference for interpolating the playhead between polls.
    private var positionAnchor: (position: Double, at: CFTimeInterval) = (0, 0)
    /// Set when we seek, so an in-flight poll cannot yank the playhead backwards.
    private var seekGuardUntil: CFTimeInterval = 0

    var pinnedProvider: ProviderID? {
        get { ProviderID(rawValue: pinnedProviderRaw) }
        set {
            pinnedProviderRaw = newValue?.rawValue ?? ""
            Defaults.set(.pinnedProvider, pinnedProviderRaw)
            refresh()
        }
    }

    // MARK: - Lifecycle

    func start() {
        refreshAvailability()
        observeProviders()
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        pollTimer?.tolerance = 0.2
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
    }

    private func observeProviders() {
        for provider in providers.values {
            guard let name = provider.changeNotification else { continue }
            let token = DistributedNotificationCenter.default().addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            observers.append(token)
        }

        // Apps launching or quitting changes which providers we can offer.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshAvailability()
                    self?.refresh()
                }
            }
        }
    }

    private func refreshAvailability() {
        availableProviders = ProviderID.allCases.filter { providers[$0]?.isRunning == true }
    }

    // MARK: - Authorization

    /// Prompts once per provider that is installed. Safe to call repeatedly: macOS only
    /// shows the dialog the first time.
    func requestAuthorizationIfNeeded() {
        work.async { [weak self] in
            guard let self else { return }
            var denied: Set<ProviderID> = []
            for id in ProviderID.allCases where AppleScriptBridge.shared.isRunning(id) {
                if !AppleScriptBridge.shared.requestAuthorization(for: id) {
                    denied.insert(id)
                }
            }
            Task { @MainActor in self.deniedProviders = denied }
        }
    }

    func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Polling

    func refresh() {
        let candidates = providerPriority()
        work.async { [weak self] in
            guard let self else { return }

            var chosen: PlaybackSnapshot?
            var denied: Set<ProviderID> = []
            var firstIdle: PlaybackSnapshot?

            for id in candidates {
                guard let provider = self.providers[id], provider.isRunning else { continue }
                do {
                    let snap = try provider.snapshot()
                    if snap.isPlaying {
                        chosen = snap
                        break
                    }
                    if firstIdle == nil, snap.hasTrack { firstIdle = snap }
                } catch PlayerError.notAuthorized(let p) {
                    denied.insert(p)
                } catch {
                    continue
                }
            }

            let result = chosen ?? firstIdle
            Task { @MainActor in
                self.deniedProviders = denied
                if let result {
                    self.apply(result)
                } else if self.snapshot.hasTrack && !candidates.contains(where: { self.providers[$0]?.isRunning == true }) {
                    self.apply(.idle(self.activeProviderID))
                }
            }
        }
    }

    /// Pinned provider first; otherwise the one we were already following, so a paused
    /// app doesn't lose the display to a different idle app on every tick.
    private func providerPriority() -> [ProviderID] {
        if let pinned = pinnedProvider { return [pinned] }
        var order = [activeProviderID]
        order.append(contentsOf: ProviderID.allCases.filter { $0 != activeProviderID })
        return order
    }

    private func apply(_ new: PlaybackSnapshot) {
        let now = CACurrentMediaTime()
        let trackChanged = new.artworkKey != snapshot.artworkKey
        activeProviderID = new.provider

        // A seek we just issued may not be reflected yet; keep our optimistic value.
        if now < seekGuardUntil, !trackChanged {
            var adjusted = new
            adjusted.position = interpolatedPosition
            snapshot = adjusted
        } else {
            snapshot = new
            positionAnchor = (new.position, now)
        }

        if trackChanged {
            artwork = nil
            accent = Theme.defaultAccent
            loadArtwork(for: new)
        }
    }

    private func loadArtwork(for snap: PlaybackSnapshot) {
        guard snap.hasTrack else { return }
        let key = snap.artworkKey
        let url = snap.artworkURL
        let provider = providers[snap.provider]

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let result = await self.artworkLoader.load(key: key, url: url) {
                (try? provider?.localArtwork()) ?? nil
            }
            guard let result else { return }
            await MainActor.run {
                // Ignore art that arrived after the user moved on.
                guard self.snapshot.artworkKey == key else { return }
                self.artwork = result.image
                self.accent = Color(nsColor: result.accent)
            }
        }
    }

    // MARK: - Derived playhead

    /// The playhead including time elapsed since the last poll.
    var interpolatedPosition: Double {
        guard snapshot.isPlaying, snapshot.duration > 0 else { return snapshot.position }
        let elapsed = CACurrentMediaTime() - positionAnchor.at
        return min(positionAnchor.position + elapsed, snapshot.duration)
    }

    /// What the UI should draw: the scrub preview when dragging, otherwise the playhead.
    var displayFraction: Double {
        if let scrubFraction { return scrubFraction }
        guard snapshot.duration > 0 else { return 0 }
        return min(max(interpolatedPosition / snapshot.duration, 0), 1)
    }

    var displayPosition: Double {
        if let scrubFraction { return scrubFraction * snapshot.duration }
        return interpolatedPosition
    }

    // MARK: - Transport

    private var active: MusicProvider? { providers[activeProviderID] }

    func togglePlayPause() {
        guard snapshot.hasTrack || active?.isRunning == true else { return }
        // Update optimistically so the record reacts on the same frame as the click.
        positionAnchor = (interpolatedPosition, CACurrentMediaTime())
        snapshot.isPlaying.toggle()
        active?.playPause()
        scheduleConfirmation()
    }

    func next() {
        active?.nextTrack()
        scheduleConfirmation(after: 0.35)
    }

    func previous() {
        active?.previousTrack()
        scheduleConfirmation(after: 0.35)
    }

    func beginScrub(fraction: Double) {
        scrubFraction = min(max(fraction, 0), 1)
    }

    func updateScrub(fraction: Double) {
        scrubFraction = min(max(fraction, 0), 1)
    }

    func endScrub() {
        guard let fraction = scrubFraction else { return }
        scrubFraction = nil
        guard snapshot.duration > 0 else { return }

        let target = fraction * snapshot.duration
        snapshot.position = target
        positionAnchor = (target, CACurrentMediaTime())
        seekGuardUntil = CACurrentMediaTime() + 1.2
        active?.seek(to: target)
    }

    func skip(by seconds: Double) {
        guard snapshot.duration > 0 else { return }
        let target = min(max(interpolatedPosition + seconds, 0), snapshot.duration)
        snapshot.position = target
        positionAnchor = (target, CACurrentMediaTime())
        seekGuardUntil = CACurrentMediaTime() + 1.2
        active?.seek(to: target)
    }

    private func scheduleConfirmation(after delay: TimeInterval = 0.2) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refresh()
        }
    }
}
