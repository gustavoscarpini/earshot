import Foundation

/// Controls the audio devices of one direction (input or output): the device
/// list, the system default device and its hardware volume and mute.
///
/// Covers the output side from DESIGN §3 (follow the system default output,
/// device picker, hybrid hardware/software master volume) and the microphone
/// side from DESIGN §2 (input picker, input gain, mute). When an output has no
/// settable hardware volume (e.g. many HDMI displays) the caller falls back to
/// a software master implemented with the global tap (DESIGN §9).
///
/// `CoreAudioDeviceController` is the Core Audio implementation; tests use a
/// fake conforming to this protocol.
@MainActor
protocol AudioDeviceController: AnyObject {
    /// The available devices (at least one stream in this direction), sorted by
    /// name. Hidden devices and Earshot's own private aggregates are excluded.
    func devices() -> [AudioDevice]

    /// The UID of the current system default device, if any.
    func defaultDeviceUID() -> String?

    /// Changes the system default device.
    func setDefaultDevice(uid: String) throws

    /// Whether the device has a settable hardware volume.
    func hasHardwareVolume(uid: String) -> Bool

    /// The hardware volume (`0...1`) of the device, or `nil` when it has none.
    func hardwareVolume(uid: String) -> Float?

    /// Sets the hardware volume (`0...1`) of the device.
    func setHardwareVolume(_ volume: Float, uid: String) throws

    /// Whether the device is muted, or `nil` when it has no settable mute.
    func hardwareMute(uid: String) -> Bool?

    /// Mutes or unmutes the device.
    func setHardwareMute(_ muted: Bool, uid: String) throws

    /// Starts observing the device list, the default device, and the default
    /// device's volume and mute.
    ///
    /// - Parameter onChange: Called on the main actor whenever the device list,
    ///   the default device, or the default device's volume or mute changes.
    func start(onChange: @escaping @MainActor () -> Void)

    /// Stops observing and removes every property listener.
    func stop()
}
