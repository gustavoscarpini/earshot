import Foundation

/// Observes which apps are currently producing audio output.
///
/// Backed by Core Audio process objects and their
/// `kAudioProcessPropertyIsRunningOutput` property (DESIGN §1). The list of
/// "apps currently playing" is derived from these process objects, never from
/// the taps themselves.
///
/// `CoreAudioProcessMonitor` is the Core Audio implementation; tests use a
/// fake conforming to this protocol (DESIGN §11).
@MainActor
protocol AudioProcessMonitor: AnyObject {
    /// Starts observing changes to the process list and to each process's
    /// running-output state.
    ///
    /// - Parameter onChange: Called on the main actor whenever the process list
    ///   or any process's running-output state changes.
    func start(onChange: @escaping @MainActor () -> Void)

    /// Stops observing changes and removes every property listener.
    func stop()

    /// The current Core Audio process objects, excluding Earshot's own process.
    func processes() -> [AudioProcess]
}
