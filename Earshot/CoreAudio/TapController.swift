import Darwin
import Foundation

/// Creates, updates and destroys Core Audio process taps.
///
/// Taps are what actually change an app's volume: a tapped app's original
/// output is muted and Earshot plays the captured audio to the output device
/// with the user's gain applied (DESIGN §1).
///
/// Two kinds of tap exist (DESIGN §9):
/// - per-app taps, created only when an app's volume is not 100% or it is muted;
/// - a single global tap, used for the software master on outputs without
///   hardware volume. It captures every process except Earshot itself and the
///   individually tapped apps, so gain is never applied twice.
///
/// This is a declaration-only protocol for now; the Core Audio implementation
/// arrives in a later step. Tests use a fake conforming to this protocol.
protocol TapController: AnyObject {
    /// Creates a tap for the process with `pid` and applies `gain`.
    ///
    /// While the tap is active, the tapped process's own output is muted
    /// (`muteBehavior = .mutedWhenTapped`).
    ///
    /// - Throws: If the tap cannot be created for this process.
    func createTap(forPID pid: pid_t, gain: Float) throws

    /// Updates the gain applied by the tap for `pid`.
    func setGain(_ gain: Float, forPID pid: pid_t)

    /// Destroys the tap for `pid`, restoring the app's direct output to hardware.
    func destroyTap(forPID pid: pid_t)

    /// Creates the single global tap that applies `gain` to every process except
    /// Earshot itself and the processes in `excludingPIDs`.
    ///
    /// - Throws: If the tap cannot be created.
    func createGlobalTap(gain: Float, excludingPIDs: [pid_t]) throws

    /// Updates the gain applied by the global tap.
    func setGlobalGain(_ gain: Float)

    /// Destroys the global tap, if any.
    func destroyGlobalTap()

    /// Destroys every tap, per-app and global.
    ///
    /// Called when the output device changes (taps are rebuilt against the new
    /// device) and on shutdown.
    func destroyAllTaps()

    /// The current peak level (`0...1`) for a tapped process, for the per-app
    /// level meter. Returns `0` for processes without a tap.
    func peakLevel(forPID pid: pid_t) -> Float
}
