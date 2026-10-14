import Foundation

enum ProviderID: String, CaseIterable, Identifiable, Codable {
    case appleMusic
    case spotify

    var id: String { rawValue }

    var bundleIdentifier: String {
        switch self {
        case .appleMusic: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}

/// One immutable read of "what is playing right now".
struct PlaybackSnapshot: Equatable {
    var provider: ProviderID
    var trackID: String
    var title: String
    var artist: String
    var album: String
    /// Seconds.
    var duration: Double
    /// Seconds.
    var position: Double
    var isPlaying: Bool
    var artworkURL: URL?

    /// 0...1, clamped. Zero-length tracks report 0 rather than NaN.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// Identity of the *song*, used to decide when to re-fetch artwork.
    var artworkKey: String {
        trackID.isEmpty ? "\(provider.rawValue)|\(title)|\(artist)|\(album)" : "\(provider.rawValue)|\(trackID)"
    }

    static func idle(_ provider: ProviderID) -> PlaybackSnapshot {
        PlaybackSnapshot(provider: provider, trackID: "", title: "", artist: "", album: "",
                         duration: 0, position: 0, isPlaying: false, artworkURL: nil)
    }

    var hasTrack: Bool { !title.isEmpty }
}

enum PlayerError: Error, LocalizedError {
    /// The user has not granted (or has denied) Automation access for this app.
    case notAuthorized(ProviderID)
    case notRunning(ProviderID)
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let p):
            return "Spindle isn't allowed to control \(p.displayName) yet."
        case .notRunning(let p):
            return "\(p.displayName) isn't running."
        case .scriptFailed(let message):
            return message
        }
    }
}
