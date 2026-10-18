import Foundation

/// Controls input devices.
///
/// Covers the microphone side from DESIGN §2 (input gain, mute, input picker,
/// level meter). The output side lives in `OutputDeviceController`.
///
/// This is a declaration-only protocol for now; the Core Audio implementation
/// arrives in a later step. Tests use a fake conforming to this protocol.
@MainActor
protocol InputDeviceController: AnyObject {
    /// The available input devices, as `(uid, name)` pairs.
    func inputDevices() -> [(uid: String, name: String)]

    /// The UID of the current system default input device, if any.
    func defaultInputDeviceUID() -> String?

    /// Changes the system default input device.
    func setDefaultInputDevice(uid: String) throws

    /// Whether the input device exposes a hardware input volume control.
    ///
    /// Many USB microphones do not; the UI then disables the slider and shows a
    /// "not supported by this device" hint. Mute still works.
    func inputHasHardwareVolume(uid: String) -> Bool

    /// The hardware input volume (`0...1`) of the input device, or `nil` when
    /// the device has no hardware input volume.
    func inputVolume(uid: String) -> Float?

    /// Sets the hardware input volume (`0...1`) of the input device.
    func setInputVolume(_ volume: Float, uid: String) throws

    /// Whether the input device is muted.
    func inputMuted(uid: String) -> Bool

    /// Mutes or unmutes the input device.
    func setInputMuted(_ muted: Bool, uid: String) throws

    /// The current input level (`0...1`) for the real-time level meter.
    func inputLevel(uid: String) -> Float

    /// Starts observing input device changes (device added/removed, default
    /// input switched, volume or mute changed).
    ///
    /// - Parameter onChange: Called on the main queue whenever the input
    ///   configuration changes.
    func startObservingInputChanges(_ onChange: @escaping () -> Void)

    /// Stops observing input device changes.
    func stopObservingInputChanges()
}
