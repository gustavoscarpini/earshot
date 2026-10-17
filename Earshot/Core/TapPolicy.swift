import Foundation

/// Decides whether an app needs a Core Audio process tap.
///
/// Pure logic, no Core Audio dependency, so it is fully unit-testable.
///
/// A tap is created **only** when it changes what the user hears: the app is
/// muted, or its volume is not exactly 100%. At 100% and unmuted the app plays
/// directly to the hardware device — zero added latency and zero dependency on
/// Earshot.
enum TapPolicy {
    /// Whether the app identified by these values needs a tap.
    ///
    /// - Parameters:
    ///   - volume: The per-app volume, `0...1`.
    ///   - muted: Whether the app is muted.
    /// - Returns: `true` when the app is muted or its volume is not `1.0`.
    static func needsTap(volume: Float, muted: Bool) -> Bool {
        muted || volume != 1.0
    }
}
