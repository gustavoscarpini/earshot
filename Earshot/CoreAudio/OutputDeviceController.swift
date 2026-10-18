import Foundation

/// Controls output devices: the device list, the system default output and its
/// hardware volume and mute.
///
/// Covers the output side from DESIGN §3 (follow the system default output,
/// device picker, hybrid hardware/software master volume). When a device has no
/// settable hardware volume (e.g. many HDMI displays) the caller falls back to
/// a software master implemented with the global tap (DESIGN §9).
///
/// `CoreAudioOutputDeviceController` is the Core Audio implementation; tests use
/// a fake conforming to this protocol.
@MainActor
protocol OutputDeviceController: AnyObject {
    /// The available output devices (at least one output stream), sorted by
    /// name. Hidden devices and Earshot's own private aggregates are excluded.
    func devices() -> [OutputDevice]

    /// The UID of the current system default output device, if any.
    func defaultDeviceUID() -> String?

    /// Changes the system default output device.
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

    /// Starts observing the device list, the default output, and the default
    /// output's volume and mute.
    ///
    /// - Parameter onChange: Called on the main actor whenever the device list,
    ///   the default output, or the default output's volume or mute changes.
    func start(onChange: @escaping @MainActor () -> Void)

    /// Stops observing and removes every property listener.
    func stop()
}
