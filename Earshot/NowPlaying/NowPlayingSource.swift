import Foundation

/// Reports what is playing and sends transport commands to the playing app.
///
/// `MediaRemoteAdapterSource` is the real implementation (DESIGN §13); tests use
/// a fake conforming to this protocol.
@MainActor
protocol NowPlayingSource: AnyObject {
    /// Starts reporting the now playing item.
    ///
    /// - Parameter onChange: Called on the main actor whenever the item changes,
    ///   with `nil` when nothing is playing or the source is unavailable. Never
    ///   called twice in a row with the same value.
    func start(onChange: @escaping @MainActor (NowPlayingInfo?) -> Void)

    /// Stops reporting and releases every resource. Does nothing when stopped.
    func stop()

    /// Sends a transport command to the app that owns the now playing item.
    func send(_ command: NowPlayingCommand)
}
