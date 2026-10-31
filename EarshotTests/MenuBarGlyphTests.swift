import Foundation
import Testing
@testable import Earshot

struct MenuBarGlyphTests {
    private let speakers = AudioDevice(uid: "spk", name: "MacBook Pro Speakers", transport: .builtIn)
    private let airPods = AudioDevice(uid: "air", name: "Alex's AirPods Pro", transport: .bluetooth)

    @Test func idleOnBuiltInSpeakersShowsTheVolume() {
        let glyph = MenuBarGlyph.resolve(.init(outputVolume: 0.4, outputDevice: speakers))
        #expect(glyph == .speaker(volume: 0.4))
    }

    @Test func idleWithoutADeviceFallsBackToTheSpeaker() {
        #expect(MenuBarGlyph.resolve(.init(outputVolume: 1)) == .speaker(volume: 1))
    }

    @Test func volumeIsClamped() {
        #expect(MenuBarGlyph.resolve(.init(outputVolume: 1.7)) == .speaker(volume: 1))
        #expect(MenuBarGlyph.resolve(.init(outputVolume: -0.2)) == .speaker(volume: 0))
    }

    @Test func idleOnAnExternalOutputShowsItsSymbol() {
        #expect(MenuBarGlyph.resolve(.init(outputDevice: airPods)) == .device(symbol: "airpodspro"))
    }

    @Test func playbackShowsThePlayingGlyph() {
        #expect(MenuBarGlyph.resolve(.init(isPlaying: true, outputDevice: airPods)) == .playing)
    }

    @Test func mutedOutputWinsOverPlayback() {
        #expect(MenuBarGlyph.resolve(.init(isOutputMuted: true, isPlaying: true)) == .outputMuted)
    }

    @Test func mutedMicrophoneDoesNotChangeTheGlyph() {
        let inputs = MenuBarGlyph.Inputs(isMicMuted: true, isOutputMuted: true, isPlaying: true, outputDevice: airPods)
        #expect(MenuBarGlyph.resolve(inputs) == .outputMuted)
        #expect(MenuBarGlyph.resolve(.init(isMicMuted: true, isPlaying: true)) == .playing)
        #expect(MenuBarGlyph.resolve(.init(isMicMuted: true, outputVolume: 0.4, outputDevice: speakers)) == .speaker(volume: 0.4))
        #expect(MenuBarGlyph.resolve(.init(isMicMuted: true, outputDevice: airPods)) == .device(symbol: "airpodspro"))
    }

    @Test func iconHasNoBadgeWhileTheMicrophoneIsLive() {
        let icon = MenuBarIcon.resolve(.init(outputVolume: 0.4, outputDevice: speakers))
        #expect(icon == MenuBarIcon(glyph: .speaker(volume: 0.4), isMicMuted: false))
    }

    @Test func iconShowsTheBadgeNextToTheOutputGlyph() {
        let inputs = MenuBarGlyph.Inputs(isMicMuted: true, isPlaying: true, outputDevice: airPods)
        #expect(MenuBarIcon.resolve(inputs) == MenuBarIcon(glyph: .playing, isMicMuted: true))
    }

    @Test func iconBadgeKeepsTheMutedOutputGlyph() {
        let inputs = MenuBarGlyph.Inputs(isMicMuted: true, isOutputMuted: true)
        #expect(MenuBarIcon.resolve(inputs) == MenuBarIcon(glyph: .outputMuted, isMicMuted: true))
    }

    @Test func equalizerBarsAreFourAndInRange() {
        #expect(EqualizerLevels.bars.count == 4)
        #expect(EqualizerLevels.bars.allSatisfy { (0...1).contains($0) })
    }
}
