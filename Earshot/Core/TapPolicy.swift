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

    /// Volumes at or above this are treated as exactly 100%.
    static let fullVolumeSnap: Float = 0.99

    /// Clamps a slider value to `0...1` and snaps values near the top to `1.0`.
    ///
    /// Without the snap, dragging a slider "all the way up" can land on 0.998
    /// and leave a tap in place that changes nothing audible.
    static func normalizedVolume(_ volume: Float) -> Float {
        let clamped = min(max(volume, 0), 1)
        return clamped >= fullVolumeSnap ? 1 : clamped
    }
}
