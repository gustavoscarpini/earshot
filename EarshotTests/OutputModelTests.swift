import Foundation
import Testing
@testable import Earshot

@MainActor
struct OutputModelTests {
    /// A suite per test, so tests running in parallel never share stored volumes.
    private let suiteName = "OutputModelTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    private let speakers = AudioDevice(uid: "speakers", name: "Speakers", transport: .builtIn)
    private let hdmi = AudioDevice(uid: "hdmi", name: "HDMI", transport: .hdmi)

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeController(defaultUID: String) -> FakeAudioDeviceController {
        let controller = FakeAudioDeviceController()
        controller.devicesToReturn = [hdmi, speakers]
        controller.volumes = ["speakers": 0.4]
        controller.mutes = ["speakers": false]
        controller.defaultUID = defaultUID
        return controller
    }

    private func makeModel(_ controller: FakeAudioDeviceController) -> OutputModel {
        OutputModel(controller: controller, defaults: defaults)
    }

    @Test func hardwareDeviceForwardsVolumeToTheController() {
        let controller = makeController(defaultUID: "speakers")
        let model = makeModel(controller)
        model.start()

        #expect(model.selectedUID == "speakers")
        #expect(!model.usesSoftwareMaster)
        #expect(model.volume == 0.4)

        model.setVolume(0.7)

        #expect(controller.volumes["speakers"] == 0.7)
        #expect(model.volume == 0.7)
        #expect(model.softwareMasterGain == 1)
    }

    @Test func hardwareDeviceMuteGoesToTheController() {
        let controller = makeController(defaultUID: "speakers")
        let model = makeModel(controller)
        model.start()

        model.toggleMute()

        #expect(controller.mutes["speakers"] == true)
        #expect(model.isMuted)
        #expect(model.softwareMasterGain == 1)
    }

    @Test func softwareDeviceFollowsVolumeAndPersistsPerUID() {
        let controller = makeController(defaultUID: "hdmi")
        let model = makeModel(controller)
        model.start()

        #expect(model.usesSoftwareMaster)
        #expect(model.softwareMasterGain == 1)

        model.setVolume(0.5)

        #expect(model.volume == 0.5)
        #expect(model.softwareMasterGain == 0.5)
        #expect(controller.volumes["hdmi"] == nil)

        let restored = makeModel(controller)
        restored.start()
        #expect(restored.volume == 0.5)
        #expect(restored.softwareMasterGain == 0.5)
    }

    @Test func fullSoftwareVolumeForgetsTheStoredEntry() {
        let controller = makeController(defaultUID: "hdmi")
        let model = makeModel(controller)
        model.start()
        model.setVolume(0.5)

        model.setVolume(1)

        let stored = defaults.dictionary(forKey: "softwareMasterVolumes")
        #expect(stored?["hdmi"] == nil)
    }

    @Test func softwareMuteGivesZeroGainAndIsNotPersisted() {
        let controller = makeController(defaultUID: "hdmi")
        let model = makeModel(controller)
        model.start()
        model.setVolume(0.5)

        model.toggleMute()

        #expect(model.isMuted)
        #expect(model.softwareMasterGain == 0)
        #expect(defaults.dictionary(forKey: "softwareMasterVolumes")?["hdmi"] as? Double == 0.5)

        let restored = makeModel(controller)
        restored.start()
        #expect(!restored.isMuted)
        #expect(restored.softwareMasterGain == 0.5)
    }

    @Test func switchingDefaultDeviceUpdatesStateAndNotifies() {
        let controller = makeController(defaultUID: "speakers")
        let model = makeModel(controller)
        var gains: [Float] = []
        model.onSoftwareMasterChange = { gains.append($0) }
        model.start()
        #expect(gains == [1])

        defaults.set(["hdmi": 0.3], forKey: "softwareMasterVolumes")
        controller.defaultUID = "hdmi"
        controller.simulateChange()

        #expect(model.selectedUID == "hdmi")
        #expect(model.usesSoftwareMaster)
        #expect(model.volume == Float(0.3))
        #expect(gains == [1, Float(0.3)])
    }

    @Test func selectingADeviceChangesTheDefault() {
        let controller = makeController(defaultUID: "speakers")
        let model = makeModel(controller)
        model.start()

        model.select(uid: "hdmi")

        #expect(controller.defaultUID == "hdmi")
        #expect(model.selectedUID == "hdmi")
        #expect(model.usesSoftwareMaster)
    }

    @Test func hardwareDeviceWithoutHardwareMuteMutesViaSoftwareMasterZero() {
        let controller = makeController(defaultUID: "speakers")
        controller.mutes = [:]
        let model = makeModel(controller)
        model.start()
        #expect(model.softwareMasterGain == 1)

        model.toggleMute()

        #expect(model.isMuted)
        #expect(model.softwareMasterGain == 0)
        #expect(controller.volumes["speakers"] == 0.4)
    }

    @Test func unchangedGainIsNotReportedTwice() {
        let controller = makeController(defaultUID: "speakers")
        let model = makeModel(controller)
        var count = 0
        model.onSoftwareMasterChange = { _ in count += 1 }
        model.start()

        controller.simulateChange()
        model.setVolume(0.9)

        #expect(count == 1)
    }

    @Test func startIsIdempotentAndStopStopsTheController() {
        let controller = makeController(defaultUID: "speakers")
        let model = makeModel(controller)

        model.start()
        model.start()
        model.stop()
        model.stop()

        #expect(controller.startCallCount == 1)
        #expect(controller.stopCallCount == 1)
    }
}
