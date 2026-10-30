import Foundation
import Testing
@testable import Earshot

@MainActor
struct InputModelTests {
    private struct MeterFailure: Error {}

    private let builtIn = AudioDevice(uid: "builtin", name: "MacBook Microphone", transport: .builtIn)
    private let usb = AudioDevice(uid: "usb", name: "USB Mic", transport: .usb)

    /// `builtin` has hardware volume and no mute; `usb` has neither.
    private func makeController(defaultUID: String = "builtin") -> FakeAudioDeviceController {
        let controller = FakeAudioDeviceController()
        controller.devicesToReturn = [builtIn, usb]
        controller.volumes = ["builtin": 0.6]
        controller.defaultUID = defaultUID
        return controller
    }

    private func makeModel(
        _ controller: FakeAudioDeviceController,
        meter: FakeInputLevelMeter = FakeInputLevelMeter()
    ) -> InputModel {
        InputModel(controller: controller, meter: meter)
    }

    @Test func hardwareVolumeDeviceForwardsTheSlider() {
        let controller = makeController()
        let model = makeModel(controller)
        model.start()

        #expect(model.selectedUID == "builtin")
        #expect(model.hasHardwareVolume)
        #expect(model.volume == 0.6)

        model.setVolume(0.3)

        #expect(controller.volumes["builtin"] == 0.3)
        #expect(model.volume == 0.3)
    }

    @Test func deviceWithoutVolumeIgnoresSetVolume() {
        let controller = makeController(defaultUID: "usb")
        let model = makeModel(controller)
        model.start()

        model.setVolume(0.3)

        #expect(!model.hasHardwareVolume)
        #expect(controller.volumes["usb"] == nil)
    }

    @Test func hardwareMuteGoesToTheController() {
        let controller = makeController()
        controller.mutes = ["builtin": false]
        let model = makeModel(controller)
        model.start()
        #expect(model.canMute)

        model.toggleMute()

        #expect(controller.mutes["builtin"] == true)
        #expect(model.isMuted)
        #expect(controller.volumes["builtin"] == 0.6)

        model.toggleMute()

        #expect(controller.mutes["builtin"] == false)
        #expect(!model.isMuted)
    }

    @Test func volumeZeroMuteRestoresThePreviousVolume() {
        let controller = makeController()
        let model = makeModel(controller)
        model.start()
        #expect(model.canMute)

        model.toggleMute()

        #expect(controller.volumes["builtin"] == 0)
        #expect(model.isMuted)

        model.toggleMute()

        #expect(controller.volumes["builtin"] == 0.6)
        #expect(!model.isMuted)
    }

    @Test func movingTheSliderWhileVolumeMutedUnmutes() {
        let controller = makeController()
        let model = makeModel(controller)
        model.start()
        model.toggleMute()

        model.setVolume(0.4)

        #expect(!model.isMuted)
        #expect(controller.volumes["builtin"] == 0.4)

        model.toggleMute()
        #expect(controller.volumes["builtin"] == 0)
    }

    @Test func deviceWithoutVolumeAndMuteCannotMute() {
        let controller = makeController(defaultUID: "usb")
        let model = makeModel(controller)
        model.start()

        model.toggleMute()

        #expect(!model.canMute)
        #expect(!model.isMuted)
    }

    @Test func selectingADeviceChangesTheDefaultInput() {
        let controller = makeController()
        let model = makeModel(controller)
        model.start()

        model.select(uid: "usb")

        #expect(controller.defaultUID == "usb")
        #expect(model.selectedUID == "usb")
        #expect(!model.hasHardwareVolume)
    }

    @Test func monitoringStartsTheMeterAndTracksLevels() {
        let meter = FakeInputLevelMeter()
        let model = makeModel(makeController(), meter: meter)
        model.start()
        #expect(!model.isMonitoring)

        model.setMonitoring(true)
        meter.emit(0.7)

        #expect(model.isMonitoring)
        #expect(meter.startCallCount == 1)
        #expect(model.level == 0.7)
    }

    @Test func stoppingMonitoringStopsTheMeterAndResetsTheLevel() {
        let meter = FakeInputLevelMeter()
        let model = makeModel(makeController(), meter: meter)
        model.start()
        model.setMonitoring(true)
        meter.emit(0.7)

        model.setMonitoring(false)

        #expect(!model.isMonitoring)
        #expect(!meter.isRunning)
        #expect(meter.stopCallCount == 1)
        #expect(model.level == 0)
    }

    @Test func meterThrowingTurnsMonitoringOffWithAnError() {
        let meter = FakeInputLevelMeter()
        meter.startError = MeterFailure()
        let model = makeModel(makeController(), meter: meter)
        model.start()

        model.setMonitoring(true)

        #expect(!model.isMonitoring)
        #expect(model.meterError)

        meter.startError = nil
        model.setMonitoring(true)

        #expect(model.isMonitoring)
        #expect(!model.meterError)
    }

    @Test func lateMeterFailureTurnsMonitoringOffWithAnError() {
        let meter = FakeInputLevelMeter()
        let model = makeModel(makeController(), meter: meter)
        model.start()
        model.setMonitoring(true)

        meter.simulateFailure()

        #expect(!model.isMonitoring)
        #expect(model.meterError)
        #expect(!meter.isRunning)
    }

    @Test func switchingInputWhileMonitoringRestartsTheMeter() {
        let controller = makeController()
        let meter = FakeInputLevelMeter()
        let model = makeModel(controller, meter: meter)
        model.start()
        model.setMonitoring(true)

        model.select(uid: "usb")

        #expect(model.isMonitoring)
        #expect(meter.stopCallCount == 1)
        #expect(meter.startCallCount == 2)
        #expect(meter.isRunning)
    }

    @Test func startIsIdempotentAndStopStopsTheController() {
        let controller = makeController()
        let model = makeModel(controller)

        model.start()
        model.start()
        model.stop()
        model.stop()

        #expect(controller.startCallCount == 1)
        #expect(controller.stopCallCount == 1)
    }

    // MARK: Meter policy

    @Test func meterStartsAutomaticallyWhenAnotherAppUsesTheMicWithThePanelOpen() {
        let meter = FakeInputLevelMeter()
        let model = makeModel(makeController(), meter: meter)
        model.start()

        model.setOtherAppsUsingMic(true)
        #expect(!model.isMonitoring)

        model.panelDidAppear()
        #expect(model.isMonitoring)
        #expect(model.otherAppsUsingMic)
        #expect(meter.isRunning)
    }

    @Test func meterStopsWhenTheOtherAppLeavesUnlessStartedManually() {
        let meter = FakeInputLevelMeter()
        let model = makeModel(makeController(), meter: meter)
        model.start()
        model.panelDidAppear()

        model.setOtherAppsUsingMic(true)
        #expect(model.isMonitoring)
        model.setOtherAppsUsingMic(false)
        #expect(!model.isMonitoring)
        #expect(!meter.isRunning)

        model.toggleManualMonitoring()
        model.setOtherAppsUsingMic(true)
        model.setOtherAppsUsingMic(false)
        #expect(model.isMonitoring)
    }

    @Test func manualToggleStartsAndStopsTheMeter() {
        let meter = FakeInputLevelMeter()
        let model = makeModel(makeController(), meter: meter)
        model.start()
        model.panelDidAppear()
        #expect(!model.isMonitoring)

        model.toggleManualMonitoring()
        #expect(model.isMonitoring)

        model.toggleManualMonitoring()
        #expect(!model.isMonitoring)
        #expect(!meter.isRunning)
    }

    @Test func manualToggleDoesNothingWhileThePanelIsHidden() {
        let meter = FakeInputLevelMeter()
        let model = makeModel(makeController(), meter: meter)
        model.start()

        model.toggleManualMonitoring()

        #expect(!model.isMonitoring)
        #expect(meter.startCallCount == 0)
    }

    @Test func hidingThePanelStopsTheMeterAndForgetsTheManualChoice() {
        let meter = FakeInputLevelMeter()
        let model = makeModel(makeController(), meter: meter)
        model.start()
        model.panelDidAppear()
        model.toggleManualMonitoring()
        #expect(model.isMonitoring)

        model.panelDidDisappear()
        #expect(!model.isMonitoring)
        #expect(!meter.isRunning)

        model.panelDidAppear()
        #expect(!model.isMonitoring)
    }

    @Test func hidingThePanelStopsTheAutomaticMeter() {
        let meter = FakeInputLevelMeter()
        let model = makeModel(makeController(), meter: meter)
        model.start()
        model.panelDidAppear()
        model.setOtherAppsUsingMic(true)
        #expect(model.isMonitoring)

        model.panelDidDisappear()

        #expect(!model.isMonitoring)
        #expect(!meter.isRunning)
    }

    @Test func failedAutomaticStartIsNotRetriedUntilTheUserAsks() {
        let meter = FakeInputLevelMeter()
        meter.startError = MeterFailure()
        let model = makeModel(makeController(), meter: meter)
        model.start()
        model.panelDidAppear()

        model.setOtherAppsUsingMic(true)
        #expect(model.meterError)
        #expect(!model.isMonitoring)

        // Another change must not prompt again.
        model.setOtherAppsUsingMic(false)
        model.setOtherAppsUsingMic(true)
        #expect(meter.startCallCount == 0)

        meter.startError = nil
        model.toggleManualMonitoring()
        #expect(model.isMonitoring)
        #expect(!model.meterError)
    }
}
