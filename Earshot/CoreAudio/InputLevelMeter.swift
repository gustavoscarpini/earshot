import Foundation

/// Measures the live input level of the default microphone.
///
/// Capturing the microphone shows macOS's orange privacy indicator and switches
/// Bluetooth headsets to the low-quality hands-free profile, so the meter runs
/// only while the user opts in (DESIGN §2, "Known risks and limitations").
///
/// `AVAudioEngineLevelMeter` is the AVFoundation implementation; tests use a
/// fake conforming to this protocol.
@MainActor
protocol InputLevelMeter: AnyObject {
    /// Called on the main actor when the meter cannot keep running after
    /// `start(onLevel:)` returned, e.g. the user denied the microphone prompt.
    /// The meter is stopped by then.
    var onFailure: (@MainActor () -> Void)? { get set }

    /// Starts measuring the default input device.
    ///
    /// Idempotent: calling it again while running does nothing.
    ///
    /// - Parameter onLevel: Called on the main actor, at most about 20 times a
    ///   second, with the level already normalized to `0...1`.
    /// - Throws: When microphone access is denied or the audio engine cannot
    ///   start.
    func start(onLevel: @escaping @MainActor (Float) -> Void) throws

    /// Stops measuring and releases the microphone. Does nothing when stopped.
    func stop()
}
