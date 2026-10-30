import Foundation

/// The result of feeding one line to a `NowPlayingStreamParser`.
enum NowPlayingStreamUpdate: Equatable, Sendable {
    /// The line was not a valid `data` message; the state is unchanged.
    case ignored

    /// The line updated the state. `nil` means nothing is playing.
    case state(NowPlayingInfo?)
}

/// Turns the adapter's `stream` output into `NowPlayingInfo`.
///
/// Each line is a JSON object `{"type":"data","diff":<bool>,"payload":{...}}`.
/// A full payload (`diff` false) replaces the stored state; a diff payload is
/// merged into it, with a `null` value removing a key. The item counts as
/// playing only while `bundleIdentifier`, `title` and `playing` are all present.
struct NowPlayingStreamParser {
    private var state: [String: Any] = [:]

    /// The last artwork string and its decoded bytes, so an unchanged artwork is
    /// not decoded again on every diff.
    private var artworkCache: (base64: String, data: Data?)?

    /// Parses one line (without newline) and applies it to the state.
    mutating func consume(line: Data) -> NowPlayingStreamUpdate {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            object["type"] as? String == "data",
            let payload = object["payload"] as? [String: Any]
        else {
            return .ignored
        }

        if object["diff"] as? Bool == true {
            for (key, value) in payload {
                if value is NSNull {
                    state[key] = nil
                } else {
                    state[key] = value
                }
            }
        } else {
            state = payload.filter { !($0.value is NSNull) }
        }
        return .state(makeInfo())
    }

    /// Builds the info from the stored state, or `nil` when a mandatory key is
    /// missing.
    private mutating func makeInfo() -> NowPlayingInfo? {
        guard
            let bundleID = state["bundleIdentifier"] as? String,
            let title = state["title"] as? String,
            let isPlaying = state["playing"] as? Bool
        else {
            return nil
        }
        return NowPlayingInfo(
            bundleID: bundleID,
            parentBundleID: state["parentApplicationBundleIdentifier"] as? String,
            title: title,
            artist: state["artist"] as? String,
            album: state["album"] as? String,
            isPlaying: isPlaying,
            artworkData: artworkData(),
            duration: state["duration"] as? Double,
            elapsedTime: state["elapsedTime"] as? Double,
            timestamp: (state["timestamp"] as? String).flatMap(Self.date(fromISO8601:)),
            playbackRate: state["playbackRate"] as? Double
        )
    }

    /// Parses an ISO-8601 timestamp such as `2026-10-30T00:14:23Z`, with or
    /// without fractional seconds.
    private static func date(fromISO8601 string: String) -> Date? {
        if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(string, strategy: Date.ISO8601FormatStyle())
    }

    /// The decoded artwork, decoding only when the base64 string changed.
    private mutating func artworkData() -> Data? {
        guard let base64 = state["artworkData"] as? String else {
            artworkCache = nil
            return nil
        }
        if let artworkCache, artworkCache.base64 == base64 {
            return artworkCache.data
        }
        let data = Data(base64Encoded: base64)
        artworkCache = (base64, data)
        return data
    }
}
