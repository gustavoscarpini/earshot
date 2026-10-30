import Foundation
import Observation

/// Owns the "Microphone" section: the input device cards, the input volume,
/// mute and the level meter.
///
/// Volume and mute go straight to the selected input's hardware controls
/// (DESIGN §2). Mute rules:
/// - A device with a hardware mute uses it.
/// - Otherwise, a device with hardware volume is "muted" by setting the volume
///   to 0; the previous volume is remembered for unmuting (session only). Moving
///   the slider while muted unmutes.
/// - Otherwise the device cannot be muted (`canMute == false`).
///
/// Level metering captures the microphone, so it runs only while the panel is
/// visible, and then only when it costs nothing extra or the user asks
/// (DESIGN §2): automatically while another app already uses the microphone
/// (the privacy indicator is on and Bluetooth headsets are already in hands-free
/// mode), otherwise only after `toggleManualMonitoring()`. Nothing is
/// persisted.
@MainActor
@Observable
final class InputModel {
    /// The available input devices, sorted by name.
    private(set) var devices: [AudioDevice] = []

    /// The UID of the current default input device, if any.
    private(set) var selectedUID: String?

    /// Whether the selected device has a settable hardware input volume. When
    /// it does not, the slider is disabled.
    private(set) var hasHardwareVolume = false

    /// The hardware input volume, `0...1`.
    private(set) var volume: Float = 1

    /// Whether the microphone is muted (see the mute rules above).
    private(set) var isMuted = false

    /// Whether the selected device can be muted at all.
    private(set) var canMute = false

    /// The current input level, `0...1`; 0 unless monitoring.
    private(set) var level: Float = 0

    /// Whether the level meter is running.
    private(set) var isMonitoring = false

    /// Whether the last attempt to start the meter failed (e.g. microphone
    /// access denied). Cleared when monitoring is turned on again or off.
    private(set) var meterError = false

    /// Whether another app (not Earshot) is currently capturing the microphone.
    /// While it is, the meter runs by itself and the manual button is hidden.
    private(set) var otherAppsUsingMic = false

    private let controller: any AudioDeviceController
    private let meter: any InputLevelMeter
    private var isRunning = false

    /// Whether the selected device has a settable hardware mute.
    @ObservationIgnored private var hasHardwareMute = false

    /// Whether the panel is on screen. The meter never runs without it.
    @ObservationIgnored private var isPanelVisible = false

    /// Whether the user started the meter by hand. Reset when the panel hides.
    @ObservationIgnored private var isManuallyMonitoring = false

    /// The volume to restore when unmuting a device muted through volume 0.
    @ObservationIgnored private var volumeBeforeMute: Float?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - controller: Reads and controls the input devices.
    ///   - meter: Measures the input level while monitoring.
    init(controller: any AudioDeviceController, meter: any InputLevelMeter) {
        self.controller = controller
        self.meter = meter
        meter.onFailure = { [weak self] in
            self?.meterFailed()
        }
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

    /// Stops observing the controller and the meter.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        controller.stop()
        setMonitoring(false)
    }

    /// Makes the device with `uid` the system default input and, while
    /// monitoring, restarts the meter on it.
    func select(uid: String) {
        guard uid != selectedUID else { return }
        try? controller.setDefaultDevice(uid: uid)
        refresh()
    }

    /// Sets the input volume, snapping near-full values to 100%. Does nothing
    /// when the device has no hardware volume. Moving the slider while muted
    /// through volume 0 unmutes.
    func setVolume(_ volume: Float) {
        guard let uid = selectedUID, hasHardwareVolume else { return }
        if !hasHardwareMute {
            volumeBeforeMute = nil
        }
        try? controller.setHardwareVolume(TapPolicy.normalizedVolume(volume), uid: uid)
        refresh()
    }

    /// Mutes or unmutes the microphone following the mute rules.
    func toggleMute() {
        guard let uid = selectedUID, canMute else { return }
        if hasHardwareMute {
            try? controller.setHardwareMute(!isMuted, uid: uid)
        } else if let previous = volumeBeforeMute {
            volumeBeforeMute = nil
            try? controller.setHardwareVolume(previous, uid: uid)
        } else {
            volumeBeforeMute = volume
            try? controller.setHardwareVolume(0, uid: uid)
        }
        refresh()
    }

    // MARK: Meter policy

    /// The panel became visible: the meter may start (see the type docs).
    func panelDidAppear() {
        isPanelVisible = true
        reconcileMeter()
    }

    /// The panel was hidden: the meter stops and the manual choice is forgotten.
    func panelDidDisappear() {
        isPanelVisible = false
        isManuallyMonitoring = false
        reconcileMeter()
    }

    /// Reports whether another app is capturing the microphone. Starts the
    /// meter while the panel is visible, and stops it again once the other app
    /// is gone, unless the user started it by hand.
    func setOtherAppsUsingMic(_ using: Bool) {
        guard using != otherAppsUsingMic else { return }
        otherAppsUsingMic = using
        reconcileMeter()
    }

    /// Starts the meter by hand, or stops it when it is already running.
    /// Retries after a failed start. Does nothing while the panel is hidden.
    func toggleManualMonitoring() {
        guard isPanelVisible else { return }
        if isMonitoring {
            isManuallyMonitoring = false
            setMonitoring(false)
        } else {
            isManuallyMonitoring = true
            reconcileMeter(retryAfterError: true)
        }
    }

    /// Turns the level meter on or off. Turning it on clears a previous error;
    /// if the meter cannot start, monitoring stays off and `meterError` is set.
    func setMonitoring(_ on: Bool) {
        if on {
            guard !isMonitoring else { return }
            meterError = false
            do {
                try meter.start { [weak self] value in
                    self?.level = value
                }
                isMonitoring = true
            } catch {
                meterError = true
            }
        } else {
            meterError = false
            guard isMonitoring else { return }
            meter.stop()
            isMonitoring = false
            level = 0
        }
    }

    // MARK: Private

    /// Starts or stops the meter to match the policy. A failed start is not
    /// retried by itself (`meterError`), so a denied permission does not prompt
    /// on every change.
    private func reconcileMeter(retryAfterError: Bool = false) {
        let wanted = isPanelVisible && (otherAppsUsingMic || isManuallyMonitoring)
        guard wanted != isMonitoring else { return }
        if wanted, meterError, !retryAfterError { return }
        setMonitoring(wanted)
    }

    /// The meter gave up after starting (permission denied at the prompt).
    private func meterFailed() {
        meter.stop()
        isMonitoring = false
        level = 0
        meterError = true
    }

    /// Re-reads the controller and updates the observable state. Restarts the
    /// meter when the selected input changed while monitoring.
    private func refresh() {
        devices = controller.devices()
        let uid = controller.defaultDeviceUID()
        let changed = uid != selectedUID
        if changed {
            volumeBeforeMute = nil
        }
        selectedUID = uid

        if let uid, let hardware = controller.hardwareVolume(uid: uid) {
            hasHardwareVolume = true
            volume = hardware
        } else {
            hasHardwareVolume = false
            volume = 1
        }

        if let uid, let muted = controller.hardwareMute(uid: uid) {
            hasHardwareMute = true
            canMute = true
            isMuted = muted
        } else {
            hasHardwareMute = false
            canMute = hasHardwareVolume
            isMuted = hasHardwareVolume && volumeBeforeMute != nil && volume == 0
            if !isMuted { volumeBeforeMute = nil }
        }

        if changed, isMonitoring {
            restartMeter()
        }
    }

    /// Stops and starts the meter, e.g. after the default input changed.
    private func restartMeter() {
        meter.stop()
        do {
            try meter.start { [weak self] value in
                self?.level = value
            }
        } catch {
            isMonitoring = false
            level = 0
            meterError = true
        }
    }
}
