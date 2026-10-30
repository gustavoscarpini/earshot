import Foundation
import Testing
@testable import Earshot

@MainActor
struct NowPlayingModelTests {
    private let track = NowPlayingInfo(
        bundleID: "com.example.player",
        title: "Song",
        artist: "Artist",
        isPlaying: true
    )

    @Test func startAndStopAreIdempotent() {
        let source = FakeNowPlayingSource()
        let model = NowPlayingModel(source: source)

        model.start()
        model.start()
        #expect(source.startCallCount == 1)

        model.stop()
        model.stop()
        #expect(source.stopCallCount == 1)
    }

    @Test func stopWithoutStartDoesNothing() {
        let source = FakeNowPlayingSource()
        NowPlayingModel(source: source).stop()

        #expect(source.stopCallCount == 0)
    }

    @Test func emittedInfoShowsUpAndClears() {
        let source = FakeNowPlayingSource()
        let model = NowPlayingModel(source: source)
        model.start()
        #expect(model.info == nil)

        source.emit(track)
        #expect(model.info == track)

        source.emit(nil)
        #expect(model.info == nil)
    }

    @Test func stopHidesTheCard() {
        let source = FakeNowPlayingSource()
        let model = NowPlayingModel(source: source)
        model.start()
        source.emit(track)

        model.stop()

        #expect(model.info == nil)
    }

    @Test func toggleSendsCommandAndFlipsPlaying() {
        let source = FakeNowPlayingSource()
        let model = NowPlayingModel(source: source)
        model.start()
        source.emit(track)

        model.togglePlayPause()

        #expect(source.sentCommands == [.togglePlayPause])
        #expect(model.info?.isPlaying == false)

        // The next stream update wins.
        source.emit(track)
        #expect(model.info?.isPlaying == true)
    }

    @Test func nextAndPreviousSendTheRightCommands() {
        let source = FakeNowPlayingSource()
        let model = NowPlayingModel(source: source)
        model.start()
        source.emit(track)

        model.nextTrack()
        model.previousTrack()

        #expect(source.sentCommands == [.nextTrack, .previousTrack])
    }

    @Test func commandsAreNoOpsWithoutInfo() {
        let source = FakeNowPlayingSource()
        let model = NowPlayingModel(source: source)
        model.start()

        model.togglePlayPause()
        model.nextTrack()
        model.previousTrack()

        #expect(source.sentCommands.isEmpty)
        #expect(model.info == nil)
    }

    @Test func commandRawValuesMatchTheAdapterIDs() {
        #expect(NowPlayingCommand.togglePlayPause.rawValue == 2)
        #expect(NowPlayingCommand.nextTrack.rawValue == 4)
        #expect(NowPlayingCommand.previousTrack.rawValue == 5)
    }

    // MARK: Progress

    private let t0 = Date(timeIntervalSinceReferenceDate: 10_000)

    private func playingTrack() -> NowPlayingInfo {
        NowPlayingInfo(
            bundleID: "com.example.player",
            title: "Song",
            isPlaying: true,
            duration: 200,
            elapsedTime: 50,
            timestamp: t0,
            playbackRate: 1
        )
    }

    @Test func togglingWhilePlayingFreezesElapsedAtTheEstimate() {
        let source = FakeNowPlayingSource()
        let clock = MutableClock(t0.addingTimeInterval(10))
        let model = NowPlayingModel(source: source, now: { clock.now })
        model.start()
        source.emit(playingTrack())

        model.togglePlayPause()

        #expect(model.info?.isPlaying == false)
        #expect(model.info?.elapsedTime == 60)
        #expect(model.info?.timestamp == clock.now)
        // Time passing while paused does not move the position.
        #expect(model.info?.elapsed(at: clock.now.addingTimeInterval(30)) == 60)
    }

    @Test func togglingWhilePausedResumesFromTheFrozenPosition() {
        let source = FakeNowPlayingSource()
        let clock = MutableClock(t0.addingTimeInterval(10))
        let model = NowPlayingModel(source: source, now: { clock.now })
        model.start()
        source.emit(playingTrack())
        model.togglePlayPause()

        clock.now = t0.addingTimeInterval(40)
        model.togglePlayPause()

        #expect(model.info?.isPlaying == true)
        #expect(model.info?.elapsedTime == 60)
        #expect(model.info?.timestamp == clock.now)
        #expect(model.info?.elapsed(at: clock.now.addingTimeInterval(5)) == 65)
    }

    @Test func resumingAfterAZeroPlaybackRateAssumesNormalSpeed() {
        let paused = NowPlayingInfo(
            bundleID: "a",
            title: "T",
            isPlaying: false,
            duration: 100,
            elapsedTime: 10,
            timestamp: t0,
            playbackRate: 0
        )

        let resumed = paused.togglingPlayback(at: t0)

        #expect(resumed.elapsed(at: t0.addingTimeInterval(4)) == 14)
    }

    @Test func sourceNameAndAmbientColorStayEmptyForUnknownAppsAndNoArtwork() {
        let source = FakeNowPlayingSource()
        let model = NowPlayingModel(source: source)
        model.start()

        source.emit(track)

        #expect(model.sourceName == nil)
        #expect(model.ambientColor == nil)
    }

    /// A clock whose value a test can advance.
    private final class MutableClock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }
}
