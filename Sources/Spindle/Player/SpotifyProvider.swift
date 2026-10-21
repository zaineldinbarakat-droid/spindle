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

    /// Between songs only the state and position change: just those and the track's ID,
    /// three Apple Events instead of nine (each one wakes Spotify too).
    private let quickScript = """
    set sep to character id 31
    tell application id "com.spotify.client"
        set stateText to (player state as text)
        set positionText to "0"
        try
            set positionText to (player position as text)
        end try
        set idText to ""
        try
            set idText to ((id of current track) as text)
        end try
        return stateText & sep & positionText & sep & idText
    end tell
    """

    /// The last full snapshot's fields, reused while the same track plays. Guarded by `lock`.
    nonisolated(unsafe) private var lastFull: [String]?
    private let lock = NSLock()

    func snapshot() throws -> PlaybackSnapshot {
        guard isRunning else { throw PlayerError.notRunning(.spotify) }
        lock.lock()
        defer { lock.unlock() }

        let quick = try fields(quickScript, key: "spotify.quick")
        if quick.count >= 3, !quick[2].isEmpty, var f = lastFull, f[7] == quick[2] {
            f[0] = quick[0]
            f[1] = quick[1]
            return snapshot(from: f)
        }

        let f = try fields(snapshotScript, key: "spotify.snapshot")
        guard f.count >= 8 else { throw PlayerError.scriptFailed("Unexpected Spotify response.") }
        lastFull = f[7].isEmpty ? nil : f
        return snapshot(from: f)
    }

    private func fields(_ script: String, key: String) throws -> [String] {
        do {
            return try bridge.run(script, cacheKey: key).fields(separatedBy: scriptFieldSeparator)
        } catch {
            throw AppleScriptBridge.classify(error, provider: .spotify)
        }
    }

    private func snapshot(from f: [String]) -> PlaybackSnapshot {
        PlaybackSnapshot(
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
