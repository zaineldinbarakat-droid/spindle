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

    func snapshot() throws -> PlaybackSnapshot {
        guard isRunning else { throw PlayerError.notRunning(.appleMusic) }
        let descriptor: NSAppleEventDescriptor
        do {
            descriptor = try bridge.run(snapshotScript, cacheKey: "music.snapshot")
        } catch {
            throw AppleScriptBridge.classify(error, provider: .appleMusic)
        }

        let f = descriptor.fields(separatedBy: scriptFieldSeparator)
        guard f.count >= 7 else { throw PlayerError.scriptFailed("Unexpected Music response.") }

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
