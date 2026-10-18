import Foundation

/// Creates, updates and destroys Core Audio process taps.
///
/// Taps are what actually change an app's volume: a tapped app's original
/// output is muted and Earshot plays the captured audio to the output device
/// with the user's gain applied (DESIGN §1).
///
/// Callers describe the taps they want, keyed by app id, and the controller
/// works out what to create, rebuild, update or destroy (`TapReconciler`). It
/// also follows the system default output device, rebuilding every tap against
/// the new device when it changes (DESIGN §3).
///
/// The single global tap for the software master (DESIGN §9) arrives in a later
/// step. Tests use a fake conforming to this protocol.
@MainActor
protocol TapController: AnyObject {
    /// Makes the active taps match `desired`. Apps missing from `desired` lose
    /// their tap and play directly to the hardware again.
    ///
    /// Failures are per app: an app whose tap cannot be created is left
    /// untapped and retried on the next call.
    func apply(_ desired: [String: TapSpec])
}
