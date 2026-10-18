import AudioToolbox
import CoreAudio
import Foundation

/// The Core Audio implementation of `OutputDeviceController`.
///
/// Reads the HAL's devices and observes them with property listeners, all on the
/// main actor. Every `OSStatus` is checked: a property that cannot be read or
/// observed is skipped (or throws, for setters) rather than crashing
/// (DESIGN §3, §11).
@MainActor
final class CoreAudioOutputDeviceController: OutputDeviceController {
    /// The HAL's system object, which owns the device list and the defaults.
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// UIDs starting with this prefix belong to Earshot's own private aggregates.
    private static let ownUIDPrefix = "com.gustavoscarpini.Earshot"

    /// Called on the main actor whenever something the controller cares about
    /// changes.
    private var onChange: (@MainActor () -> Void)?

    /// Whether `start(onChange:)` has run without a matching `stop()`.
    private var isObserving = false

    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?

    /// The device whose volume and mute are observed, and its two listeners.
    private var observedDevice: AudioObjectID?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var muteListener: AudioObjectPropertyListenerBlock?

    // MARK: OutputDeviceController

    func devices() -> [OutputDevice] {
        deviceIDs().compactMap { device in
            guard hasOutputStreams(device),
                  !isHidden(device),
                  let uid = uid(of: device),
                  !uid.hasPrefix(Self.ownUIDPrefix) else {
                return nil
            }
            return OutputDevice(uid: uid, name: name(of: device) ?? uid)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func defaultDeviceUID() -> String? {
        defaultOutputDevice().flatMap(uid(of:))
    }

    func setDefaultDevice(uid: String) throws {
        guard var device = deviceID(forUID: uid) else {
            throw CoreAudioError(operation: "Find output device", status: kAudioHardwareBadDeviceError)
        }
        let size = UInt32(MemoryLayout<AudioObjectID>.size)

        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        try Self.check(
            "Set default output device",
            AudioObjectSetPropertyData(Self.systemObject, &address, 0, nil, size, &device)
        )

        // Alerts follow the default device; failing to move them is harmless.
        var systemAddress = Self.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        _ = AudioObjectSetPropertyData(Self.systemObject, &systemAddress, 0, nil, size, &device)
    }

    func hasHardwareVolume(uid: String) -> Bool {
        guard let device = deviceID(forUID: uid) else { return false }
        return isSettable(device, Self.volumeAddress)
    }

    func hardwareVolume(uid: String) -> Float? {
        guard let device = deviceID(forUID: uid), isSettable(device, Self.volumeAddress) else { return nil }
        var address = Self.volumeAddress
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return min(max(value, 0), 1)
    }

    func setHardwareVolume(_ volume: Float, uid: String) throws {
        guard let device = deviceID(forUID: uid) else {
            throw CoreAudioError(operation: "Find output device", status: kAudioHardwareBadDeviceError)
        }
        var address = Self.volumeAddress
        var value: Float32 = min(max(volume, 0), 1)
        try Self.check(
            "Set output volume",
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        )
    }

    func hardwareMute(uid: String) -> Bool? {
        guard let device = deviceID(forUID: uid), isSettable(device, Self.muteAddress) else { return nil }
        var address = Self.muteAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    func setHardwareMute(_ muted: Bool, uid: String) throws {
        guard let device = deviceID(forUID: uid) else {
            throw CoreAudioError(operation: "Find output device", status: kAudioHardwareBadDeviceError)
        }
        var address = Self.muteAddress
        var value: UInt32 = muted ? 1 : 0
        try Self.check(
            "Set output mute",
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        )
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        guard !isObserving else { return }
        isObserving = true
        self.onChange = onChange

        var listAddress = Self.address(kAudioHardwarePropertyDevices)
        let listListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
        if AudioObjectAddPropertyListenerBlock(Self.systemObject, &listAddress, DispatchQueue.main, listListener) == noErr {
            deviceListListener = listListener
        }

        var defaultAddress = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let defaultListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.defaultOutputChanged()
            }
        }
        if AudioObjectAddPropertyListenerBlock(Self.systemObject, &defaultAddress, DispatchQueue.main, defaultListener) == noErr {
            defaultOutputListener = defaultListener
        }

        observeDefaultDevice()
    }

    func stop() {
        guard isObserving else { return }
        isObserving = false
        onChange = nil

        // Removal has no recovery path; a stale listener already fails harmlessly.
        if let listener = deviceListListener {
            var address = Self.address(kAudioHardwarePropertyDevices)
            _ = AudioObjectRemovePropertyListenerBlock(Self.systemObject, &address, DispatchQueue.main, listener)
            deviceListListener = nil
        }
        if let listener = defaultOutputListener {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            _ = AudioObjectRemovePropertyListenerBlock(Self.systemObject, &address, DispatchQueue.main, listener)
            defaultOutputListener = nil
        }
        unobserveDefaultDevice()
    }

    // MARK: Observation

    /// The default output moved: re-attach the volume and mute listeners to the
    /// new device and notify.
    private func defaultOutputChanged() {
        observeDefaultDevice()
        onChange?()
    }

    /// Moves the volume and mute listeners to the current default output.
    private func observeDefaultDevice() {
        let device = defaultOutputDevice()
        guard device != observedDevice else { return }
        unobserveDefaultDevice()
        guard let device else { return }

        var volumeAddress = Self.volumeAddress
        let volume: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
        if AudioObjectAddPropertyListenerBlock(device, &volumeAddress, DispatchQueue.main, volume) == noErr {
            volumeListener = volume
        }

        var muteAddress = Self.muteAddress
        let mute: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
        if AudioObjectAddPropertyListenerBlock(device, &muteAddress, DispatchQueue.main, mute) == noErr {
            muteListener = mute
        }

        observedDevice = device
    }

    /// Removes the volume and mute listeners from the observed device.
    private func unobserveDefaultDevice() {
        if let device = observedDevice {
            if let listener = volumeListener {
                var address = Self.volumeAddress
                _ = AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, listener)
            }
            if let listener = muteListener {
                var address = Self.muteAddress
                _ = AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, listener)
            }
        }
        volumeListener = nil
        muteListener = nil
        observedDevice = nil
    }

    // MARK: Property reads

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
    }

    private static func check(_ operation: String, _ status: OSStatus) throws {
        guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
    }

    /// Whether `device` has `address` and it can be written.
    private func isSettable(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    private func deviceIDs() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(Self.systemObject, &address, 0, nil, &size) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(Self.systemObject, &address, 0, nil, &size, &devices) == noErr else {
            return []
        }
        return devices
    }

    private func defaultOutputDevice() -> AudioObjectID? {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(Self.systemObject, &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else {
            return nil
        }
        return device
    }

    /// Resolves a device UID to its object, scanning the device list.
    private func deviceID(forUID uid: String) -> AudioObjectID? {
        deviceIDs().first { self.uid(of: $0) == uid }
    }

    private func hasOutputStreams(_ device: AudioObjectID) -> Bool {
        var address = Self.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private func isHidden(_ device: AudioObjectID) -> Bool {
        var address = Self.address(kAudioDevicePropertyIsHidden)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private func uid(of device: AudioObjectID) -> String? {
        string(kAudioDevicePropertyDeviceUID, of: device)
    }

    private func name(of device: AudioObjectID) -> String? {
        string(kAudioObjectPropertyName, of: device)
    }

    /// Reads a `CFString` property, which comes back with a +1 retain count.
    private func string(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = Self.address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
