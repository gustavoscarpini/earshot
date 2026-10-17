import Darwin
import Foundation

/// Observes which apps are currently producing audio output.
///
/// Backed by the Core Audio process objects and their
/// `kAudioProcessPropertyIsRunningOutput` property (DESIGN §1). The list of
/// "apps currently playing" is derived from these process objects, never from
/// the taps themselves.
///
/// This is a declaration-only protocol for now; the Core Audio implementation
/// arrives in a later step. Tests use a fake conforming to this protocol.
protocol AudioProcessMonitor: AnyObject {
    /// Starts observing changes to the set of processes that are running output.
    ///
    /// - Parameter onChange: Called on the main queue whenever the set changes.
    func startObserving(_ onChange: @escaping () -> Void)

    /// Stops observing changes and releases any listener blocks.
    func stopObserving()

    /// The processes that are currently producing audio output.
    ///
    /// Each entry is `(pid, bundle identifier, display name)`. The bundle
    /// identifier is `nil` for processes that have none.
    func runningOutputProcesses() -> [(pid: pid_t, bundleID: String?, name: String)]

    /// The bundle identifier of the process that owns `pid`, if any.
    ///
    /// Used to group helper processes (e.g. "Google Chrome Helper (Renderer)")
    /// under their parent app (DESIGN §5).
    func parentBundleIdentifier(ofPID pid: pid_t) -> String?
}
