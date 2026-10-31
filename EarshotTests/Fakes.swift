import Foundation
@testable import Earshot

/// Test double for `TapController` that records the last applied plan.
@MainActor
final class FakeTapController: TapController {
    private(set) var lastPlan = TapPlan(perApp: [:], global: nil)
    private(set) var applyCallCount = 0

    /// The per-app part of the last plan.
    var lastApplied: [String: TapSpec] { lastPlan.perApp }

    /// What `peaks()` returns.
    var peaksToReturn: [String: Float] = [:]

    func apply(_ plan: TapPlan) {
        lastPlan = plan
        applyCallCount += 1
    }

    func peaks() -> [String: Float] { peaksToReturn }
}

/// In-memory `VolumeStore` with the same "1.0 forgets" rule as the real one.
@MainActor
final class InMemoryVolumeStore: VolumeStore {
    private(set) var volumes: [String: Float] = [:]

    func volume(forBundleID bundleID: String) -> Float? {
        volumes[bundleID]
    }

    func setVolume(_ volume: Float, forBundleID bundleID: String) {
        volumes[bundleID] = volume == 1 ? nil : volume
    }
}

/// Test double for `AudioDeviceController` with settable devices.
///
/// A test configures `devicesToReturn`, `defaultUID`, `volumes` and `mutes`
/// (a device missing from `volumes` has no hardware volume; one missing from
/// `mutes` has no hardware mute) and fires the change callback with
/// `simulateChange()`.
@MainActor
final class FakeAudioDeviceController: AudioDeviceController {
    var devicesToReturn: [AudioDevice] = []
    var defaultUID: String?
    var volumes: [String: Float] = [:]
    var mutes: [String: Bool] = [:]
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private var onChange: (@MainActor () -> Void)?

    func devices() -> [AudioDevice] { devicesToReturn }

    func defaultDeviceUID() -> String? { defaultUID }

    func setDefaultDevice(uid: String) throws { defaultUID = uid }

    func hasHardwareVolume(uid: String) -> Bool { volumes[uid] != nil }

    func hardwareVolume(uid: String) -> Float? { volumes[uid] }

    func setHardwareVolume(_ volume: Float, uid: String) throws { volumes[uid] = volume }

    func hardwareMute(uid: String) -> Bool? { mutes[uid] }

    func setHardwareMute(_ muted: Bool, uid: String) throws { mutes[uid] = muted }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        startCallCount += 1
    }

    func stop() {
        onChange = nil
        stopCallCount += 1
    }

    /// Fires the change callback, as the real controller would on a change.
    func simulateChange() {
        onChange?()
    }
}

/// Test double for `InputLevelMeter` that records starts and stops.
///
/// A test emits levels with `emit(_:)`, makes the next `start` throw by setting
/// `startError`, and simulates a late failure with `simulateFailure()`.
@MainActor
final class FakeInputLevelMeter: InputLevelMeter {
    var onFailure: (@MainActor () -> Void)?
    var startError: (any Error)?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var isRunning = false
    private var onLevel: (@MainActor (Float) -> Void)?

    func start(onLevel: @escaping @MainActor (Float) -> Void) throws {
        if let startError { throw startError }
        startCallCount += 1
        isRunning = true
        self.onLevel = onLevel
    }

    func stop() {
        stopCallCount += 1
        isRunning = false
        onLevel = nil
    }

    /// Delivers a normalized level, as the real meter would.
    func emit(_ level: Float) {
        onLevel?(level)
    }

    /// Fires the failure callback, as the real meter would after a denied prompt.
    func simulateFailure() {
        onFailure?()
    }
}

/// Test double for `NowPlayingSource` that records starts, stops and sent
/// commands, and emits infos on demand.
@MainActor
final class FakeNowPlayingSource: NowPlayingSource {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var sentCommands: [NowPlayingCommand] = []
    private var onChange: (@MainActor (NowPlayingInfo?) -> Void)?

    func start(onChange: @escaping @MainActor (NowPlayingInfo?) -> Void) {
        self.onChange = onChange
        startCallCount += 1
    }

    func stop() {
        onChange = nil
        stopCallCount += 1
    }

    func send(_ command: NowPlayingCommand) {
        sentCommands.append(command)
    }

    /// Reports `info`, as the real source would when the item changes.
    func emit(_ info: NowPlayingInfo?) {
        onChange?(info)
    }
}

/// Test double for `GlobalHotKeys` that records registrations and lets a test
/// press a shortcut.
@MainActor
final class FakeGlobalHotKeys: GlobalHotKeys {
    var registrationSucceeds = true
    private(set) var registered: [HotKey] = []
    private var handlers: [@MainActor () -> Void] = []

    func register(_ hotKey: HotKey, handler: @escaping @MainActor () -> Void) -> Bool {
        guard registrationSucceeds else { return false }
        registered.append(hotKey)
        handlers.append(handler)
        return true
    }

    func unregisterAll() {
        registered.removeAll()
        handlers.removeAll()
    }

    /// Fires the handler of `hotKey`, as the system would on a key press.
    func press(_ hotKey: HotKey) {
        for (key, handler) in zip(registered, handlers) where key == hotKey {
            handler()
        }
    }
}

/// Test double for `VolumeKeyInterceptor`: trust is a flag, and a test sends
/// media keys through `send(_:fine:)`.
@MainActor
final class FakeVolumeKeyInterceptor: VolumeKeyInterceptor {
    var isTrusted = true
    private(set) var isRunning = false
    private(set) var startCallCount = 0
    private(set) var promptCount = 0
    private(set) var openSettingsCount = 0
    private var handler: (@MainActor (MediaKeyEvent, Bool) -> Bool)?

    func promptForTrust() { promptCount += 1 }

    func openAccessibilitySettings() { openSettingsCount += 1 }

    func start(handler: @escaping @MainActor (MediaKeyEvent, Bool) -> Bool) -> Bool {
        guard isTrusted else { return false }
        startCallCount += 1
        isRunning = true
        self.handler = handler
        return true
    }

    func stop() {
        isRunning = false
        handler = nil
    }

    /// Delivers a key to the handler; returns whether it was consumed, or
    /// `false` when the tap is not running (the system handles the key).
    func send(_ event: MediaKeyEvent, fine: Bool = false) -> Bool {
        handler?(event, fine) ?? false
    }
}

/// Test double for `LaunchAtLoginService` with a settable status.
@MainActor
final class FakeLaunchAtLogin: LaunchAtLoginService {
    var status: LaunchAtLoginStatus = .disabled

    /// What `register()` leaves the status at, to simulate `requiresApproval`.
    var statusAfterRegister: LaunchAtLoginStatus = .enabled
    var registerError: (any Error)?
    private(set) var openSettingsCount = 0

    func register() throws {
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws { status = .disabled }

    func openLoginItemsSettings() { openSettingsCount += 1 }
}
