import CoreAudio
import Darwin
import Foundation

/// The Core Audio implementation of `AudioProcessMonitor`.
///
/// Reads the HAL's process objects and observes them with property listeners,
/// all on the main actor. Every `OSStatus` is checked: a property that cannot be
/// read or observed is skipped rather than crashing, and listeners are removed
/// from process objects that have disappeared (DESIGN §1, §11).
@MainActor
final class CoreAudioProcessMonitor: AudioProcessMonitor {
    /// The HAL's system object, which owns the process object list.
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// Called on the main actor whenever something the monitor cares about
    /// changes.
    private var onChange: (@MainActor () -> Void)?

    /// Whether `start(onChange:)` has run without a matching `stop()`.
    private var isObserving = false

    /// The listener on the system object for process list changes.
    private var processListListener: AudioObjectPropertyListenerBlock?

    /// The listener per process object, keyed by object, kept so it can be
    /// removed again with `AudioObjectRemovePropertyListenerBlock`.
    private var outputListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]

    // MARK: AudioProcessMonitor

    func start(onChange: @escaping @MainActor () -> Void) {
        guard !isObserving else { return }
        isObserving = true
        self.onChange = onChange

        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.processListChanged()
            }
        }
        if AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, DispatchQueue.main, listener) == noErr {
            processListListener = listener
        }

        processListChanged()
    }

    func stop() {
        guard isObserving else { return }
        isObserving = false
        onChange = nil

        if let listener = processListListener {
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            // Removal has no recovery path; a stale listener already fails harmlessly.
            _ = AudioObjectRemovePropertyListenerBlock(Self.systemObject, &address, DispatchQueue.main, listener)
            processListListener = nil
        }

        for (object, listener) in outputListeners {
            var address = Self.address(kAudioProcessPropertyIsRunningOutput)
            _ = AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, listener)
        }
        outputListeners.removeAll()
    }

    func processes() -> [AudioProcess] {
        let ownPID = getpid()
        return processObjectIDs().compactMap { object in
            guard let pid = pid(of: object), pid != ownPID else { return nil }
            return AudioProcess(
                objectID: object,
                pid: pid,
                bundleID: bundleID(of: object),
                executablePath: executablePath(of: pid),
                isRunningOutput: isRunningOutput(of: object)
            )
        }
    }

    // MARK: Observation

    /// Re-syncs the per-process listeners with the current process objects and
    /// notifies `onChange`.
    private func processListChanged() {
        let current = Set(processObjectIDs())

        for object in Array(outputListeners.keys) where !current.contains(object) {
            if let listener = outputListeners[object] {
                var address = Self.address(kAudioProcessPropertyIsRunningOutput)
                _ = AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, listener)
            }
            outputListeners[object] = nil
        }

        for object in current where outputListeners[object] == nil {
            addOutputListener(for: object)
        }

        onChange?()
    }

    /// Starts observing the running-output state of one process object.
    private func addOutputListener(for object: AudioObjectID) {
        var address = Self.address(kAudioProcessPropertyIsRunningOutput)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, listener) == noErr {
            outputListeners[object] = listener
        }
    }

    // MARK: Property reads

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func processObjectIDs() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(Self.systemObject, &address, 0, nil, &size) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(Self.systemObject, &address, 0, nil, &size, &objects) == noErr else {
            return []
        }
        return objects
    }

    private func pid(of object: AudioObjectID) -> pid_t? {
        var address = Self.address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    /// Reads the process's bundle identifier.
    ///
    /// `kAudioProcessPropertyBundleID` is backed by a `CFString` returned with
    /// a +1 retain count, so the value is taken retained. Processes without a
    /// bundle (e.g. `afplay`) report an empty string, normalized to `nil`.
    private func bundleID(of object: AudioObjectID) -> String? {
        var address = Self.address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        let bundleID = value.takeRetainedValue() as String
        return bundleID.isEmpty ? nil : bundleID
    }

    private func isRunningOutput(of object: AudioObjectID) -> Bool {
        var address = Self.address(kAudioProcessPropertyIsRunningOutput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }

    private func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        guard !bytes.isEmpty else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }
}
