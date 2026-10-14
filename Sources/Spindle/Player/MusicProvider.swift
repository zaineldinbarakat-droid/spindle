import Foundation

/// A source of now-playing information that we can also control.
///
/// Every concrete provider talks to a locally running app over Apple Events, which is
/// what buys us two things the private MediaRemote framework cannot give: a settable
/// playhead (so the tonearm can actually scrub) and a supported API surface.
protocol MusicProvider: AnyObject, Sendable {
    var id: ProviderID { get }

    /// True when the backing app is launched. We never launch it ourselves — sending an
    /// Apple Event to a dead app would boot it, which is not what a passive widget does.
    var isRunning: Bool { get }

    /// Name of the distributed notification the app posts when playback changes, if any.
    /// Providers that have one get instant updates and only need a light position poll.
    var changeNotification: Notification.Name? { get }

    /// Reads the current state. Called off the main thread.
    func snapshot() throws -> PlaybackSnapshot

    /// Fetches cover art bytes for the current track, if the provider serves them locally.
    /// Providers that expose a URL instead return nil here and populate `artworkURL`.
    func localArtwork() throws -> Data?

    func play()
    func pause()
    func playPause()
    func nextTrack()
    func previousTrack()
    func seek(to seconds: Double)
}

extension MusicProvider {
    func localArtwork() throws -> Data? { nil }
}

/// Field separator used by the scripts. U+001F is the ASCII unit separator: it cannot
/// appear in a track title, so joining and splitting on it is lossless.
let scriptFieldSeparator = "\u{1F}"
