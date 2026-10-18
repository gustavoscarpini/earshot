import Foundation
@testable import Earshot

/// Test double for `TapController` that records the last desired state.
@MainActor
final class FakeTapController: TapController {
    private(set) var lastApplied: [String: TapSpec] = [:]
    private(set) var applyCallCount = 0

    func apply(_ desired: [String: TapSpec]) {
        lastApplied = desired
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
