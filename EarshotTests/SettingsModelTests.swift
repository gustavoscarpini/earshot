import Foundation
import Testing
@testable import Earshot

@MainActor
struct SettingsModelTests {
    private let suiteName = "SettingsModelTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    private let hotKeys = FakeGlobalHotKeys()
    private let volumeKeys = FakeVolumeKeyInterceptor()
    private let launch = FakeLaunchAtLogin()
    private let outputs = FakeAudioDeviceController()
    private let inputs = FakeAudioDeviceController()
    private let output: OutputModel
    private let input: InputModel

    @MainActor
    final class BeepCounter {
        var count = 0
    }

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        outputs.devicesToReturn = [
            AudioDevice(uid: "hdmi", name: "HDMI", transport: .hdmi),
            AudioDevice(uid: "speakers", name: "Speakers", transport: .builtIn),
        ]
        outputs.volumes = ["speakers": 0.4]
        outputs.defaultUID = "hdmi"
        inputs.devicesToReturn = [
            AudioDevice(uid: "builtin", name: "Mic", transport: .builtIn),
            AudioDevice(uid: "usb", name: "USB Mic", transport: .usb),
        ]
        inputs.volumes = ["builtin": 0.6]
        inputs.defaultUID = "builtin"
        output = OutputModel(controller: outputs, defaults: defaults)
        input = InputModel(controller: inputs, meter: FakeInputLevelMeter())
        output.start()
        input.start()
    }

    private func makeModel(beep: @escaping @MainActor () -> Void = {}) -> SettingsModel {
        SettingsModel(
            launchService: launch,
            volumeKeys: volumeKeys,
            hotKeys: hotKeys,
            input: input,
            output: output,
            defaults: defaults,
            beep: beep
        )
    }

    private let up = MediaKeyEvent(key: .soundUp, isDown: true)
    private let down = MediaKeyEvent(key: .soundDown, isDown: true)
    private let mute = MediaKeyEvent(key: .mute, isDown: true)

    // MARK: Mic shortcut

    @Test func startRegistersTheMicShortcutOnce() {
        let model = makeModel()
        model.start()
        model.start()
        #expect(hotKeys.registered == [.toggleMicrophoneMute])
        #expect(model.isMicShortcutRegistered)
    }

    @Test func shortcutTogglesTheMicrophoneMute() {
        let model = makeModel()
        model.start()

        hotKeys.press(.toggleMicrophoneMute)
        #expect(input.isMuted)
        #expect(inputs.volumes["builtin"] == 0)

        hotKeys.press(.toggleMicrophoneMute)
        #expect(!input.isMuted)
        #expect(inputs.volumes["builtin"] == 0.6)
    }

    @Test func menuItemStateFollowsTheMicrophone() {
        let model = makeModel()
        #expect(model.canMuteMicrophone)
        #expect(!model.isMicrophoneMuted)

        model.toggleMicrophoneMute()
        #expect(model.isMicrophoneMuted)

        inputs.defaultUID = "usb"
        input.select(uid: "usb")
        #expect(!model.canMuteMicrophone)
    }

    @Test func shortcutBeepsWhenTheMicrophoneCannotBeMuted() {
        let counter = BeepCounter()
        inputs.defaultUID = "usb"
        input.select(uid: "usb")
        let model = makeModel { counter.count += 1 }
        model.start()

        hotKeys.press(.toggleMicrophoneMute)

        #expect(counter.count == 1)
        #expect(!input.isMuted)
    }

    @Test func shortcutBeepsWithoutADevice() {
        let counter = BeepCounter()
        inputs.defaultUID = nil
        inputs.simulateChange()
        let model = makeModel { counter.count += 1 }
        model.start()
        hotKeys.press(.toggleMicrophoneMute)
        #expect(counter.count == 1)
    }

    @Test func stopUnregistersTheShortcut() {
        let model = makeModel()
        model.start()
        model.stop()
        #expect(hotKeys.registered.isEmpty)
    }

    // MARK: Volume keys

    @Test func volumeKeysAreOffByDefault() {
        let model = makeModel()
        model.start()
        #expect(!model.volumeKeysEnabled)
        #expect(!volumeKeys.isRunning)
        #expect(!volumeKeys.send(up))
    }

    @Test func enablingStartsTheTapAndPersists() {
        let model = makeModel()
        model.start()
        model.setVolumeKeysEnabled(true)

        #expect(volumeKeys.isRunning)
        #expect(model.isVolumeKeyTapRunning)
        #expect(defaults.bool(forKey: SettingsModel.volumeKeysKey))
        #expect(volumeKeys.promptCount == 0)
        #expect(makeModel().volumeKeysEnabled)
    }

    @Test func enablingWithoutTrustPromptsAndWaitsForThePanel() {
        volumeKeys.isTrusted = false
        let model = makeModel()
        model.start()
        model.setVolumeKeysEnabled(true)

        #expect(volumeKeys.promptCount == 1)
        #expect(!volumeKeys.isRunning)
        #expect(!model.isAccessibilityTrusted)

        volumeKeys.isTrusted = true
        model.panelDidAppear()

        #expect(volumeKeys.isRunning)
        #expect(model.isAccessibilityTrusted)
    }

    @Test func disablingStopsTheTap() {
        let model = makeModel()
        model.start()
        model.setVolumeKeysEnabled(true)
        model.setVolumeKeysEnabled(false)
        #expect(!volumeKeys.isRunning)
        #expect(!defaults.bool(forKey: SettingsModel.volumeKeysKey))
    }

    @Test func storedOptionStartsTheTapAtLaunch() {
        defaults.set(true, forKey: SettingsModel.volumeKeysKey)
        makeModel().start()
        #expect(volumeKeys.isRunning)
    }

    @Test func keysStepTheSoftwareMasterAndAreConsumed() {
        let model = makeModel()
        model.start()
        model.setVolumeKeysEnabled(true)
        #expect(output.usesSoftwareMaster)

        #expect(volumeKeys.send(down))
        #expect(output.volume == 0.9375)
        #expect(volumeKeys.send(down, fine: true))
        #expect(output.volume == 0.921875)
        #expect(volumeKeys.send(up))
        #expect(volumeKeys.send(up))
        #expect(output.volume == 1)
    }

    @Test func keyUpIsConsumedWithoutAChange() {
        let model = makeModel()
        model.start()
        model.setVolumeKeysEnabled(true)
        #expect(volumeKeys.send(MediaKeyEvent(key: .soundDown, isDown: false)))
        #expect(output.volume == 1)
    }

    @Test func muteKeyTogglesTheSoftwareMute() {
        let model = makeModel()
        model.start()
        model.setVolumeKeysEnabled(true)

        #expect(volumeKeys.send(mute))
        #expect(output.isMuted)
        #expect(volumeKeys.send(mute))
        #expect(!output.isMuted)
    }

    @Test func steppingWhileMutedUnmutes() {
        let model = makeModel()
        model.start()
        model.setVolumeKeysEnabled(true)
        _ = volumeKeys.send(mute)

        #expect(volumeKeys.send(down))

        #expect(!output.isMuted)
        #expect(output.volume == 0.9375)
    }

    @Test func keysPassThroughOnAHardwareVolumeOutput() {
        outputs.defaultUID = "speakers"
        outputs.simulateChange()
        let model = makeModel()
        model.start()
        model.setVolumeKeysEnabled(true)
        #expect(!output.usesSoftwareMaster)

        #expect(!volumeKeys.send(up))
        #expect(!volumeKeys.send(mute))
        #expect(outputs.volumes["speakers"] == 0.4)
    }

    // MARK: Launch at login

    @Test func launchAtLoginReflectsTheSystemStatus() {
        launch.status = .enabled
        let model = makeModel()
        model.start()
        #expect(model.launchAtLogin == .enabled)

        launch.status = .disabled
        model.panelDidAppear()
        #expect(model.launchAtLogin == .disabled)
    }

    @Test func togglingRegistersAndUnregisters() {
        let model = makeModel()
        model.start()

        model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin == .enabled)

        model.setLaunchAtLogin(false)
        #expect(model.launchAtLogin == .disabled)
    }

    @Test func requiresApprovalIsReportedAndOpensSettings() {
        launch.statusAfterRegister = .requiresApproval
        let model = makeModel()
        model.start()

        model.setLaunchAtLogin(true)
        #expect(model.launchAtLogin == .requiresApproval)

        model.openLoginItemsSettings()
        #expect(launch.openSettingsCount == 1)
    }

    @Test func failedRegistrationLeavesTheRealStatus() {
        struct Failure: Error {}
        launch.registerError = Failure()
        let model = makeModel()
        model.start()

        model.setLaunchAtLogin(true)

        #expect(model.launchAtLogin == .disabled)
    }

    @Test func accessibilitySettingsOpenThroughTheInterceptor() {
        let model = makeModel()
        model.openAccessibilitySettings()
        #expect(volumeKeys.openSettingsCount == 1)
    }
}
