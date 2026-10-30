import Foundation
@testable import Earshot

/// Test double for `TapController` that records the last applied plan.
@MainActor
final class FakeTapController: TapController {
    private(set) var lastPlan = TapPlan(perApp: [:], global: nil)
    private(set) var applyCallCount = 0

    /// The per-app part of the last plan.
    var lastApplied: [String: TapSpec] { lastPlan.perApp }

    func apply(_ plan: TapPlan) {
        lastPlan = plan
        applyCallCount += 1
    }
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
