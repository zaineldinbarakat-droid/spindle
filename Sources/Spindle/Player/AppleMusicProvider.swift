import Foundation

final class AppleMusicProvider: MusicProvider {
    let id: ProviderID = .appleMusic

    private let bridge = AppleScriptBridge.shared

    var isRunning: Bool { bridge.isRunning(.appleMusic) }

    var changeNotification: Notification.Name? {
        Notification.Name("com.apple.Music.playerInfo")
    }

    // Returns: state, position, title, artist, album, durationSeconds, persistentID
    // Returns: state, position, title, artist, album, durationSeconds, persistentID
    // See SpotifyProvider for why the variable names are spelled out.
    private let snapshotScript = """
    set sep to character id 31
    set trackPart to ""
    tell application id "com.apple.Music"
        set stateText to (player state as text)
        set positionText to "0"
        try
            set positionText to (player position as text)
        end try
        try
            set theTrack to current track
            set trackPart to (name of theTrack) & sep & (artist of theTrack) & sep & (album of theTrack) & sep & ((duration of theTrack) as text) & sep & ((persistent ID of theTrack) as text)
        on error
            set trackPart to "" & sep & "" & sep & "" & sep & "0" & sep & ""
        end try
        return stateText & sep & positionText & sep & trackPart
    end tell
    """

    private let artworkScript = """
    tell application id "com.apple.Music"
        set arts to artworks of current track
        if (count of arts) is 0 then error "no artwork"
        return raw data of item 1 of arts
    end tell
    """

    /// Between songs only the state and position change: just those and the track's ID,
    /// three Apple Events instead of eight (each one wakes Music too).
    private let quickScript = """
    set sep to character id 31
    tell application id "com.apple.Music"
        set stateText to (player state as text)
        set positionText to "0"
        try
            set positionText to (player position as text)
        end try
        set idText to ""
        try
            set idText to ((persistent ID of current track) as text)
        end try
        return stateText & sep & positionText & sep & idText
    end tell
    """

    /// The last full snapshot's fields, reused while the same track plays. Guarded by `lock`.
    nonisolated(unsafe) private var lastFull: [String]?
    private let lock = NSLock()

    func snapshot() throws -> PlaybackSnapshot {
        guard isRunning else { throw PlayerError.notRunning(.appleMusic) }
        lock.lock()
        defer { lock.unlock() }

        let quick = try fields(quickScript, key: "music.quick")
        if quick.count >= 3, !quick[2].isEmpty, var f = lastFull, f[6] == quick[2] {
            f[0] = quick[0]
            f[1] = quick[1]
            return snapshot(from: f)
        }

        let f = try fields(snapshotScript, key: "music.snapshot")
        guard f.count >= 7 else { throw PlayerError.scriptFailed("Unexpected Music response.") }
        lastFull = f[6].isEmpty ? nil : f
        return snapshot(from: f)
    }

    private func fields(_ script: String, key: String) throws -> [String] {
        do {
            return try bridge.run(script, cacheKey: key).fields(separatedBy: scriptFieldSeparator)
        } catch {
            throw AppleScriptBridge.classify(error, provider: .appleMusic)
        }
    }

    private func snapshot(from f: [String]) -> PlaybackSnapshot {
        // When stopped, `player position` coerces to "missing value", which parses to nil.
        let position = f[1].appleScriptDouble ?? 0

        return PlaybackSnapshot(
            provider: .appleMusic,
            trackID: f[6],
            title: f[2],
            artist: f[3],
            album: f[4],
            duration: f[5].appleScriptDouble ?? 0,  // Music reports seconds
            position: position,
            isPlaying: f[0].caseInsensitiveCompare("playing") == .orderedSame,
            artworkURL: nil
        )
    }

    /// Music hands back the cover as raw bytes rather than a URL, so we pull it directly
    /// out of the Apple Event descriptor instead of going to the network.
    func localArtwork() throws -> Data? {
        guard isRunning else { return nil }
        let descriptor = try bridge.run(artworkScript, cacheKey: "music.artwork")
        if let data = descriptor.data as Data?, !data.isEmpty {
            return data
        }
        return nil
    }

    // MARK: - Transport

    private func tell(_ body: String, key: String) {
        bridge.perform("tell application id \"com.apple.Music\" to \(body)", cacheKey: key)
    }

    func play() { tell("play", key: "music.play") }
    func pause() { tell("pause", key: "music.pause") }
    func playPause() { tell("playpause", key: "music.playpause") }
    func nextTrack() { tell("next track", key: "music.next") }
    func previousTrack() { tell("back track", key: "music.prev") }

    func seek(to seconds: Double) {
        let clamped = max(0, seconds)
        bridge.perform("tell application id \"com.apple.Music\" to set player position to \(clamped)")
    }
}
