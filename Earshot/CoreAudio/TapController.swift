import Foundation

/// Creates, updates and destroys Core Audio process taps.
///
/// Taps are what actually change an app's volume: a tapped app's original
/// output is muted and Earshot plays the captured audio to the output device
/// with the user's gain applied (DESIGN §1).
///
/// Callers describe the taps they want as a `TapPlan` (per-app taps keyed by
/// app id, plus the optional single global tap for the software master,
/// DESIGN §9), and the controller works out what to create, rebuild, update or
/// destroy (`TapReconciler`). It also follows the system default output device,
/// rebuilding every tap against the new device when it changes (DESIGN §3).
///
/// Tests use a fake conforming to this protocol.
@MainActor
protocol TapController: AnyObject {
    /// Makes the active taps match `plan`. Apps missing from the plan lose
    /// their tap and play directly to the hardware again; an empty plan
    /// destroys everything.
    ///
    /// Failures are per tap: a tap that cannot be created is left out and
    /// retried on the next call.
    func apply(_ plan: TapPlan)

    /// The current linear peak amplitude (`1` is full scale) of each app that
    /// has a tap, keyed by app id: volume taps report their post-gain output,
    /// meter-only taps (`TapPlan.meters`) the untouched audio (DESIGN §14).
    /// Cheap and safe to call at 20-30 Hz.
    func peaks() -> [String: Float]
}
