import Foundation
@testable import Earshot

/// Test double for `AudioProcessMonitor`.
///
/// Returns the processes a test sets on `processesToReturn` and lets the test
/// fire the change callback with `simulateChange()`.
@MainActor
final class FakeAudioProcessMonitor: AudioProcessMonitor {
    var processesToReturn: [AudioProcess] = []
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private var onChange: (@MainActor () -> Void)?

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        startCallCount += 1
    }

    func stop() {
        onChange = nil
        stopCallCount += 1
    }

    func processes() -> [AudioProcess] {
        processesToReturn
    }

    /// Fires the change callback, as the real monitor would on a property change.
    func simulateChange() {
        onChange?()
    }
}
