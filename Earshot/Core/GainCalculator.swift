import Foundation

/// Computes the gain applied to a tapped app.
///
/// Pure logic, no Core Audio dependency, so it is fully unit-testable.
enum GainCalculator {
    /// The gain applied to a single app.
    ///
    /// The resulting gain is `app * master`, clamped to `0...1`. A muted app
    /// always resolves to `0`, regardless of the two gains.
    ///
    /// - Parameters:
    ///   - app: The per-app volume, `0...1`.
    ///   - master: The master volume, `0...1`.
    ///   - muted: Whether the app is muted.
    /// - Returns: The effective linear gain, `0...1`.
    static func effectiveGain(app: Float, master: Float, muted: Bool) -> Float {
        guard !muted else { return 0 }
        return min(max(app * master, 0), 1)
    }
}
