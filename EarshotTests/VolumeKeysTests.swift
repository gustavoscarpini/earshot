import Foundation
import Testing
@testable import Earshot

struct VolumeKeysTests {
    private func data1(key: Int, state: Int) -> Int { (key << 16) | (state << 8) }

    @Test func decodesKeyDownAndKeyUp() {
        #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(key: 0, state: 0xA)) == MediaKeyEvent(key: .soundUp, isDown: true))
        #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(key: 1, state: 0xB)) == MediaKeyEvent(key: .soundDown, isDown: false))
        #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(key: 7, state: 0xA)) == MediaKeyEvent(key: .mute, isDown: true))
    }

    @Test func repeatFlagStillDecodesAsDown() {
        // Bit 0 of the low byte is the repeat flag.
        #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(key: 0, state: 0xA) | 1)?.isDown == true)
    }

    @Test func ignoresOtherKeysAndSubtypes() {
        #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(key: 16, state: 0xA)) == nil)
        #expect(MediaKeyEvent.decode(subtype: 7, data1: data1(key: 0, state: 0xA)) == nil)
        #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(key: 0, state: 0x3)) == nil)
    }

    @Test func stepsAreAnSixteenthOrASixtyFourth() {
        let up = MediaKeyEvent(key: .soundUp, isDown: true)
        let down = MediaKeyEvent(key: .soundDown, isDown: true)
        #expect(VolumeKeyMapper.action(for: up, fine: false) == .step(1.0 / 16))
        #expect(VolumeKeyMapper.action(for: down, fine: false) == .step(-1.0 / 16))
        #expect(VolumeKeyMapper.action(for: up, fine: true) == .step(1.0 / 64))
        #expect(VolumeKeyMapper.action(for: down, fine: true) == .step(-1.0 / 64))
    }

    @Test func muteTogglesAndKeyUpIsIgnored() {
        #expect(VolumeKeyMapper.action(for: MediaKeyEvent(key: .mute, isDown: true), fine: false) == .toggleMute)
        for key in [MediaKeyEvent.Key.soundUp, .soundDown, .mute] {
            #expect(VolumeKeyMapper.action(for: MediaKeyEvent(key: key, isDown: false), fine: false) == .ignore)
        }
    }

    @Test func steppedClampsToTheRange() {
        #expect(VolumeKeyMapper.stepped(0.98, by: 1.0 / 16) == 1)
        #expect(VolumeKeyMapper.stepped(0.02, by: -1.0 / 16) == 0)
    }

    @Test func steppedDoesNotDrift() {
        var volume: Float = 0
        for _ in 0..<16 { volume = VolumeKeyMapper.stepped(volume, by: VolumeKeyMapper.coarseStep) }
        #expect(volume == 1)
        for _ in 0..<64 { volume = VolumeKeyMapper.stepped(volume, by: -VolumeKeyMapper.fineStep) }
        #expect(volume == 0)
    }

    @Test func hotKeyDisplaysInSystemOrder() {
        #expect(HotKey.toggleMicrophoneMute.display == "⌃⌘M")
        #expect(HotKey(keyCode: 0, modifiers: [.command, .shift, .option, .control], keyLabel: "A").display == "⌃⌥⇧⌘A")
    }
}
