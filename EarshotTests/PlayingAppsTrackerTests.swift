import Foundation
import Testing
@testable import Earshot

struct PlayingAppsTrackerTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func newAppAppearsPlaying() {
        var tracker = PlayingAppsTracker()

        tracker.update(playing: [(id: "com.example.a", name: "A")], now: t0)

        #expect(tracker.apps == [
            PlayingApp(id: "com.example.a", name: "A", isPlaying: true, lastPlayedAt: t0)
        ])
    }

    @Test func appThatStopsPlayingLingersDimmed() {
        var tracker = PlayingAppsTracker()
        tracker.update(playing: [(id: "com.example.a", name: "A")], now: t0)

        tracker.update(playing: [], now: t0.addingTimeInterval(5))

        #expect(tracker.apps.count == 1)
        #expect(tracker.apps[0].isPlaying == false)
        #expect(tracker.apps[0].lastPlayedAt == t0)
    }

    @Test func lingersJustBeforeTenSeconds() {
        var tracker = PlayingAppsTracker()
        tracker.update(playing: [(id: "com.example.a", name: "A")], now: t0)

        tracker.update(playing: [], now: t0.addingTimeInterval(9.9))

        #expect(tracker.apps.count == 1)
        #expect(tracker.apps[0].isPlaying == false)
    }

    @Test func removedAtTenSeconds() {
        var tracker = PlayingAppsTracker()
        tracker.update(playing: [(id: "com.example.a", name: "A")], now: t0)

        tracker.update(playing: [], now: t0.addingTimeInterval(PlayingAppsTracker.lingerDuration))

        #expect(tracker.apps.isEmpty)
    }

    @Test func updatesWithSamePlayingPruneExpiredEntries() {
        var tracker = PlayingAppsTracker()
        tracker.update(playing: [
            (id: "com.example.a", name: "A"),
            (id: "com.example.b", name: "B")
        ], now: t0)
        tracker.update(playing: [(id: "com.example.a", name: "A")], now: t0.addingTimeInterval(1))

        tracker.update(playing: [(id: "com.example.a", name: "A")], now: t0.addingTimeInterval(11))

        #expect(tracker.apps.map(\.id) == ["com.example.a"])
        #expect(tracker.apps[0].isPlaying == true)
    }

    @Test func returningWhileLingeringBecomesPlayingAgainWithoutDuplicate() {
        var tracker = PlayingAppsTracker()
        tracker.update(playing: [(id: "com.example.a", name: "A")], now: t0)
        tracker.update(playing: [], now: t0.addingTimeInterval(5))

        let resumedAt = t0.addingTimeInterval(6)
        tracker.update(playing: [(id: "com.example.a", name: "A")], now: resumedAt)

        #expect(tracker.apps.count == 1)
        #expect(tracker.apps[0].isPlaying == true)
        #expect(tracker.apps[0].lastPlayedAt == resumedAt)
    }

    @Test func appsAreSortedByNameCaseInsensitively() {
        var tracker = PlayingAppsTracker()

        tracker.update(playing: [
            (id: "com.example.b", name: "beta"),
            (id: "com.example.a", name: "Alpha"),
            (id: "com.example.g", name: "Gamma")
        ], now: t0)

        #expect(tracker.apps.map(\.name) == ["Alpha", "beta", "Gamma"])
    }
}
