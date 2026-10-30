import Foundation
import Testing
@testable import Earshot

struct NowPlayingProgressTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 5_000)

    private func info(
        isPlaying: Bool,
        duration: TimeInterval? = 200,
        elapsedTime: TimeInterval? = 50,
        playbackRate: Double? = 1
    ) -> NowPlayingInfo {
        NowPlayingInfo(
            bundleID: "a",
            title: "T",
            isPlaying: isPlaying,
            duration: duration,
            elapsedTime: elapsedTime,
            timestamp: t0,
            playbackRate: playbackRate
        )
    }

    @Test func playingAdvancesWithTime() {
        #expect(info(isPlaying: true).elapsed(at: t0.addingTimeInterval(12)) == 62)
    }

    @Test func playingScalesByThePlaybackRate() {
        #expect(info(isPlaying: true, playbackRate: 2).elapsed(at: t0.addingTimeInterval(10)) == 70)
    }

    @Test func missingRateCountsAsNormalSpeed() {
        #expect(info(isPlaying: true, playbackRate: nil).elapsed(at: t0.addingTimeInterval(10)) == 60)
    }

    @Test func pausedStaysPut() {
        #expect(info(isPlaying: false).elapsed(at: t0.addingTimeInterval(500)) == 50)
    }

    @Test func clampsToTheDuration() {
        #expect(info(isPlaying: true).elapsed(at: t0.addingTimeInterval(1_000)) == 200)
    }

    @Test func clampsToZero() {
        #expect(info(isPlaying: false, elapsedTime: -5).elapsed(at: t0) == 0)
        // A clock earlier than the timestamp never goes backwards.
        #expect(info(isPlaying: true).elapsed(at: t0.addingTimeInterval(-30)) == 50)
    }

    @Test func unknownDurationOnlyClampsAtZero() {
        #expect(info(isPlaying: true, duration: nil).elapsed(at: t0.addingTimeInterval(1_000)) == 1_050)
    }

    @Test func nilWithoutElapsedTime() {
        #expect(info(isPlaying: true, elapsedTime: nil).elapsed(at: t0) == nil)
    }

    @Test func clockStringFormatsMinutesAndSeconds() {
        #expect(NowPlayingInfo.clockString(0) == "0:00")
        #expect(NowPlayingInfo.clockString(187.9) == "3:07")
        #expect(NowPlayingInfo.clockString(3_725) == "62:05")
        #expect(NowPlayingInfo.clockString(-4) == "0:00")
    }
}
