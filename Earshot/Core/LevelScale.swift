import Foundation

/// Maps audio peak amplitudes onto the `0...1` range of a level meter.
///
/// Pure logic, no Core Audio dependency.
enum LevelScale {
    /// The level, in dBFS, at and below which the meter reads empty.
    static let floorDecibels: Float = -60

    /// Converts a linear peak amplitude to a `0...1` meter position on a dB scale.
    ///
    /// `-60 dBFS` and below map to 0, `0 dBFS` (a peak of 1) maps to 1, and the
    /// range between is linear in dB.
    ///
    /// - Parameter peak: The linear peak amplitude, where `1` is full scale.
    ///   Values `<= 0` give 0 and values above `1` clamp to 1.
    static func normalized(peak: Float) -> Float {
        guard peak > 0 else { return 0 }
        let decibels = 20 * log10(peak)
        let position = (decibels - floorDecibels) / -floorDecibels
        return min(max(position, 0), 1)
    }
}
