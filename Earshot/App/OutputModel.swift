import Foundation
import Observation

/// Owns the "Output" section: the output device picker and the master volume.
///
/// The master is hybrid (DESIGN §3). When the selected output has a settable
/// hardware volume, volume and mute go straight to the device. When it does not
/// (e.g. HDMI displays), the slider drives a software master, remembered per
/// device UID, which the tap layer applies through the global tap (DESIGN §9);
/// `onSoftwareMasterChange` reports the gain it must use.
@MainActor
@Observable
final class OutputModel {
    /// UserDefaults key for the per-device software master volumes
    /// (`[String: Double]`, keyed by device UID).
    private static let softwareVolumesKey = "softwareMasterVolumes"

    /// The available output devices, sorted by name.
    private(set) var devices: [OutputDevice] = []

    /// The UID of the current default output device, if any.
    private(set) var selectedUID: String?

    /// Whether the selected device has no hardware volume, so the slider drives
    /// the software master.
    private(set) var usesSoftwareMaster = false

    /// The master volume, `0...1`: the hardware volume, or the software master.
    private(set) var volume: Float = 1

    /// Whether the master is muted: the hardware mute when the device has one,
    /// otherwise a session-only software mute.
    private(set) var isMuted = false

    /// Called on the main actor whenever `softwareMasterGain` changes, including
    /// device switches and at start.
    @ObservationIgnored var onSoftwareMasterChange: (@MainActor (Float) -> Void)?

    private let controller: any OutputDeviceController
    private let defaults: UserDefaults
    private var isRunning = false

    /// Whether the selected hardware-volume device has a settable hardware mute.
    @ObservationIgnored private var hasHardwareMute = false

    /// Session-only software mute, used when the device has no hardware mute.
    @ObservationIgnored private var softwareMuted = false

    /// The last gain reported through `onSoftwareMasterChange`.
    @ObservationIgnored private var lastReportedGain: Float?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - controller: Reads and controls the output devices.
    ///   - defaults: Where software master volumes are remembered.
    init(controller: any OutputDeviceController, defaults: UserDefaults = .standard) {
        self.controller = controller
        self.defaults = defaults
    }

    /// What the taps must use as software master: `1` when the device has
    /// hardware volume and hardware mute; `isMuted ? 0 : volume` for software
    /// devices; `isMuted ? 0 : 1` for a hardware-volume device lacking hardware
    /// mute.
    var softwareMasterGain: Float {
        if usesSoftwareMaster { return isMuted ? 0 : volume }
        return hasHardwareMute ? 1 : (isMuted ? 0 : 1)
    }

    /// Starts observing the controller and reads the current state.
    ///
    /// Idempotent: calling it again while running does nothing.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        controller.start { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    /// Stops observing the controller.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        controller.stop()
    }

    /// Makes the device with `uid` the system default output.
    func select(uid: String) {
        guard uid != selectedUID else { return }
        try? controller.setDefaultDevice(uid: uid)
        refresh()
    }

    /// Sets the master volume, snapping near-full values to 100%.
    func setVolume(_ volume: Float) {
        guard let uid = selectedUID else { return }
        let volume = TapPolicy.normalizedVolume(volume)
        if usesSoftwareMaster {
            storeSoftwareVolume(volume, uid: uid)
        } else {
            try? controller.setHardwareVolume(volume, uid: uid)
        }
        refresh()
    }

    /// Toggles mute. With a hardware mute it goes to the device; otherwise mute
    /// is a software master of 0, kept for the session only.
    func toggleMute() {
        guard let uid = selectedUID else { return }
        if !usesSoftwareMaster, hasHardwareMute {
            try? controller.setHardwareMute(!isMuted, uid: uid)
        } else {
            softwareMuted.toggle()
        }
        refresh()
    }

    // MARK: Private

    /// Re-reads the controller, updates the observable state and reports the
    /// software master gain when it changed.
    private func refresh() {
        devices = controller.devices()
        let uid = controller.defaultDeviceUID()
        if uid != selectedUID {
            softwareMuted = false
        }
        selectedUID = uid

        if let uid, let hardware = controller.hardwareVolume(uid: uid) {
            usesSoftwareMaster = false
            volume = hardware
            if let muted = controller.hardwareMute(uid: uid) {
                hasHardwareMute = true
                isMuted = muted
            } else {
                hasHardwareMute = false
                isMuted = softwareMuted
            }
        } else {
            usesSoftwareMaster = true
            hasHardwareMute = false
            volume = uid.map(storedSoftwareVolume(uid:)) ?? 1
            isMuted = softwareMuted
        }

        let gain = softwareMasterGain
        if gain != lastReportedGain {
            lastReportedGain = gain
            onSoftwareMasterChange?(gain)
        }
    }

    private func storedSoftwareVolume(uid: String) -> Float {
        (defaults.dictionary(forKey: Self.softwareVolumesKey)?[uid] as? Double).map(Float.init) ?? 1
    }

    /// Stores the software master for `uid`. `1.0` forgets the entry.
    private func storeSoftwareVolume(_ volume: Float, uid: String) {
        var volumes = defaults.dictionary(forKey: Self.softwareVolumesKey) ?? [:]
        volumes[uid] = volume == 1 ? nil : Double(volume)
        defaults.set(volumes, forKey: Self.softwareVolumesKey)
    }
}
