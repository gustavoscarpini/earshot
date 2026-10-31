import Foundation

/// Turns raw per-app peaks into meter positions with an instant attack and a
/// linear fall-off, like the input meter (DESIGN §14).
///
/// Pure logic, no Core Audio dependency.
struct LevelSmoother: Equatable, Sendable {
    /// How much the meter may fall per second, in meter units (`0...1`).
    static let fallPerSecond: Float = 1.8

    private var levels: [String: Float] = [:]

    /// Folds a new set of peaks in and returns the smoothed levels.
    ///
    /// - Parameters:
    ///   - peaks: Linear peak amplitudes by app id, `1` is full scale.
    ///   - elapsed: Seconds since the previous call.
    /// - Returns: Levels `0...1` by app id. Ids missing from `peaks` fall to 0
    ///   and are dropped once they reach it.
    mutating func update(peaks: [String: Float], elapsed: TimeInterval) -> [String: Float] {
        let drop = Self.fallPerSecond * Float(max(elapsed, 0))
        var next: [String: Float] = [:]
        for id in Set(levels.keys).union(peaks.keys) {
            let target = LevelScale.normalized(peak: peaks[id] ?? 0)
            let level = max(target, (levels[id] ?? 0) - drop)
            if level > 0 || peaks[id] != nil { next[id] = level }
        }
        levels = next
        return next
    }

    /// Forgets every level.
    mutating func reset() {
        levels = [:]
    }
}
