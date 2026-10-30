import Foundation

/// What the system reports as currently playing, as shown by the now playing
/// card (DESIGN §13).
struct NowPlayingInfo: Equatable, Sendable {
    /// Bundle ID of the app that owns the now playing item (e.g. a browser tab's
    /// helper process).
    let bundleID: String

    /// Bundle ID of the parent application, when the item is played by a helper
    /// process. Preferred over `bundleID` when looking up an icon.
    let parentBundleID: String?

    /// The track title.
    let title: String

    /// The artist, or `nil` when unknown or empty.
    let artist: String?

    /// The album, or `nil` when unknown or empty.
    let album: String?

    /// Whether playback is running (as opposed to paused).
    let isPlaying: Bool

    /// The encoded artwork image (PNG, JPEG, ...), if the player reports one.
    let artworkData: Data?

    /// The track length in seconds, or `nil` when unknown (e.g. a live stream).
    let duration: TimeInterval?

    /// The playback position in seconds at `timestamp`, or `nil` when unknown.
    let elapsedTime: TimeInterval?

    /// When `elapsedTime` was measured, or `nil` when unknown.
    let timestamp: Date?

    /// The playback speed (`1` is normal), or `nil` when not reported.
    let playbackRate: Double?

    /// Creates the info. An empty `artist` or `album` becomes `nil`.
    init(
        bundleID: String,
        parentBundleID: String? = nil,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        isPlaying: Bool,
        artworkData: Data? = nil,
        duration: TimeInterval? = nil,
        elapsedTime: TimeInterval? = nil,
        timestamp: Date? = nil,
        playbackRate: Double? = nil
    ) {
        self.bundleID = bundleID
        self.parentBundleID = parentBundleID
        self.title = title
        self.artist = artist.flatMap { $0.isEmpty ? nil : $0 }
        self.album = album.flatMap { $0.isEmpty ? nil : $0 }
        self.isPlaying = isPlaying
        self.artworkData = artworkData
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.timestamp = timestamp
        self.playbackRate = playbackRate
    }

    /// The estimated playback position at `now`, in seconds.
    ///
    /// While playing, the reported `elapsedTime` advances by the time passed
    /// since `timestamp`, scaled by `playbackRate` (1 when not reported); while
    /// paused it stays at `elapsedTime`. The result is clamped to
    /// `0...duration` (just `0...` when the duration is unknown).
    ///
    /// - Returns: The position, or `nil` when the player reported no
    ///   `elapsedTime`.
    func elapsed(at now: Date) -> TimeInterval? {
        guard let elapsedTime else { return nil }
        var position = elapsedTime
        if isPlaying, let timestamp {
            position += max(0, now.timeIntervalSince(timestamp)) * (playbackRate ?? 1)
        }
        position = max(0, position)
        if let duration {
            position = min(position, max(0, duration))
        }
        return position
    }

    /// The info after an optimistic play/pause flip made at `now`.
    ///
    /// Pausing freezes the position at the current estimate; resuming restarts
    /// the estimate from that position at `now`. The next update from the
    /// source replaces this guess.
    func togglingPlayback(at now: Date) -> NowPlayingInfo {
        let position = elapsed(at: now)
        let resumedRate = playbackRate.flatMap { $0 > 0 ? $0 : nil } ?? 1
        return NowPlayingInfo(
            bundleID: bundleID,
            parentBundleID: parentBundleID,
            title: title,
            artist: artist,
            album: album,
            isPlaying: !isPlaying,
            artworkData: artworkData,
            duration: duration,
            elapsedTime: position,
            timestamp: position == nil ? timestamp : now,
            playbackRate: isPlaying ? playbackRate : resumedRate
        )
    }

    /// Formats a position or length as `m:ss` (e.g. `3:07`); negative values
    /// count as zero.
    static func clockString(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

/// A transport command for the now playing app. The raw value is the ID the
/// adapter's `send` command expects (MediaRemote's `MRCommand`).
enum NowPlayingCommand: Int, Sendable {
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}
