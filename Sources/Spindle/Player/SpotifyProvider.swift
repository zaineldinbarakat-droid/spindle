import Foundation

final class SpotifyProvider: MusicProvider {
    let id: ProviderID = .spotify

    private let bridge = AppleScriptBridge.shared

    var isRunning: Bool { bridge.isRunning(.spotify) }

    var changeNotification: Notification.Name? {
        Notification.Name("com.spotify.client.PlaybackStateChanged")
    }

    // Returns: state, position, title, artist, album, durationMillis, artworkURL, trackID
    // Returns: state, position, title, artist, album, durationMillis, artworkURL, trackID
    //
    // Variable names are spelled out: `st` is reserved in AppleScript (it is the ordinal
    // suffix, as in "1st"), and so are `nd`, `rd` and `th`.
    private let snapshotScript = """
    set sep to character id 31
    set trackPart to ""
    tell application id "com.spotify.client"
        set stateText to (player state as text)
        set positionText to "0"
        try
            set positionText to (player position as text)
        end try
        try
            set theTrack to current track
            set artURL to ""
            try
                set artURL to (artwork url of theTrack) as text
            end try
            set trackPart to (name of theTrack) & sep & (artist of theTrack) & sep & (album of theTrack) & sep & ((duration of theTrack) as text) & sep & artURL & sep & ((id of theTrack) as text)
        on error
            set trackPart to "" & sep & "" & sep & "" & sep & "0" & sep & "" & sep & ""
        end try
        return stateText & sep & positionText & sep & trackPart
    end tell
    """

    func snapshot() throws -> PlaybackSnapshot {
        guard isRunning else { throw PlayerError.notRunning(.spotify) }
        let descriptor: NSAppleEventDescriptor
        do {
            descriptor = try bridge.run(snapshotScript, cacheKey: "spotify.snapshot")
        } catch {
            throw AppleScriptBridge.classify(error, provider: .spotify)
        }

        let f = descriptor.fields(separatedBy: scriptFieldSeparator)
        guard f.count >= 8 else { throw PlayerError.scriptFailed("Unexpected Spotify response.") }

        return PlaybackSnapshot(
            provider: .spotify,
            trackID: f[7],
            title: f[2],
            artist: f[3],
            album: f[4],
            duration: (f[5].appleScriptDouble ?? 0) / 1000,   // Spotify reports milliseconds
            position: f[1].appleScriptDouble ?? 0,
            isPlaying: f[0].caseInsensitiveCompare("playing") == .orderedSame,
            artworkURL: URL(string: f[6])
        )
    }

    // MARK: - Transport

    private func tell(_ body: String, key: String) {
        bridge.perform("tell application id \"com.spotify.client\" to \(body)", cacheKey: key)
    }

    func play() { tell("play", key: "spotify.play") }
    func pause() { tell("pause", key: "spotify.pause") }
    func playPause() { tell("playpause", key: "spotify.playpause") }
    func nextTrack() { tell("next track", key: "spotify.next") }
    func previousTrack() { tell("previous track", key: "spotify.prev") }

    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        // Not cached: the literal changes on every call.
        bridge.perform("tell application id \"com.spotify.client\" to set player position to \(clamped)")
    }
}
