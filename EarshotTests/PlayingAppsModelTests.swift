import Foundation
import Testing
@testable import Earshot

@MainActor
struct PlayingAppsModelTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 2_000)

    /// A clock whose value a test can advance.
    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func process(
        pid: pid_t,
        bundleID: String? = nil,
        executablePath: String? = nil,
        isRunningOutput: Bool = true
    ) -> AudioProcess {
        AudioProcess(
            objectID: UInt32(pid) + 1_000,
            pid: pid,
            bundleID: bundleID,
            executablePath: executablePath,
            isRunningOutput: isRunningOutput
        )
    }

    private func makeModel(
        _ monitor: FakeAudioProcessMonitor,
        clock: Clock,
        taps: FakeTapController = FakeTapController(),
        store: InMemoryVolumeStore = InMemoryVolumeStore()
    ) -> PlayingAppsModel {
        PlayingAppsModel(
            monitor: monitor,
            tapController: taps,
            volumeStore: store,
            now: { clock.now },
            appBundleIdentifier: { path in path == "/Applications/A.app" ? "com.example.a" : nil }
        )
    }

    // MARK: Volume, mute and taps

    @Test func fullVolumeUnmutedAppIsNotTapped() {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [process(pid: 1, bundleID: "com.example.a")]
        let taps = FakeTapController()
        let model = makeModel(monitor, clock: Clock(t0), taps: taps)

        model.refresh()

        #expect(model.volume(for: "com.example.a") == 1)
        #expect(taps.lastApplied == [:])
    }

    @Test func loweringVolumeTapsEveryProcessOfTheApp() {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [
            process(pid: 1, executablePath: "/Applications/A.app/Contents/MacOS/A", isRunningOutput: false),
            process(pid: 2, executablePath: "/Applications/A.app/Contents/Frameworks/H.app/Contents/MacOS/H")
        ]
        let taps = FakeTapController()
        let model = makeModel(monitor, clock: Clock(t0), taps: taps)
        model.refresh()

        model.setVolume(0.3, for: "/Applications/A.app")

        #expect(taps.lastApplied == [
            "/Applications/A.app": TapSpec(processObjectIDs: [1_001, 1_002], gain: 0.3)
        ])
    }

    @Test func softwareMasterAddsGlobalTapAndScalesAppGain() {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [process(pid: 1, bundleID: "com.example.a")]
        let taps = FakeTapController()
        let model = makeModel(monitor, clock: Clock(t0), taps: taps)
        model.refresh()
        model.setVolume(0.6, for: "com.example.a")

        model.setSoftwareMaster(0.5)

        #expect(taps.lastPlan.global == GlobalTapSpec(excludedProcessObjectIDs: [1_001], gain: 0.5))
        #expect(taps.lastPlan.perApp["com.example.a"]?.gain == 0.3)
    }

    @Test func backToFullVolumeRemovesTheTap() {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [process(pid: 1, bundleID: "com.example.a")]
        let taps = FakeTapController()
        let model = makeModel(monitor, clock: Clock(t0), taps: taps)
        model.refresh()

        model.setVolume(0.5, for: "com.example.a")
        model.setVolume(0.995, for: "com.example.a")

        #expect(model.volume(for: "com.example.a") == 1)
        #expect(taps.lastApplied == [:])
    }

    @Test func muteTapsWithZeroGainAndUnmuteRestores() {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [process(pid: 1, bundleID: "com.example.a")]
        let taps = FakeTapController()
        let model = makeModel(monitor, clock: Clock(t0), taps: taps)
        model.refresh()

        model.toggleMute("com.example.a")
        #expect(model.isMuted("com.example.a"))
        #expect(taps.lastApplied == ["com.example.a": TapSpec(processObjectIDs: [1_001], gain: 0)])

        model.toggleMute("com.example.a")
        #expect(!model.isMuted("com.example.a"))
        #expect(taps.lastApplied == [:])
    }

    @Test func volumeIsRememberedByParentBundleID() {
        let store = InMemoryVolumeStore()
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [process(pid: 1, executablePath: "/Applications/A.app/Contents/MacOS/A")]
        let first = makeModel(monitor, clock: Clock(t0), store: store)
        first.refresh()
        first.setVolume(0.4, for: "/Applications/A.app")
        #expect(store.volumes == ["com.example.a": 0.4])

        let taps = FakeTapController()
        let second = makeModel(monitor, clock: Clock(t0), taps: taps, store: store)
        second.refresh()

        #expect(second.volume(for: "/Applications/A.app") == 0.4)
        #expect(taps.lastApplied["/Applications/A.app"]?.gain == 0.4)
    }

    @Test func muteIsNotPersistedAndClearsWhenTheAppLeavesTheList() {
        let clock = Clock(t0)
        let store = InMemoryVolumeStore()
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [process(pid: 1, bundleID: "com.example.a")]
        let model = makeModel(monitor, clock: clock, store: store)
        model.refresh()
        model.toggleMute("com.example.a")
        #expect(store.volumes.isEmpty)

        monitor.processesToReturn = []
        clock.now = t0.addingTimeInterval(PlayingAppsTracker.lingerDuration)
        model.refresh()

        #expect(!model.isMuted("com.example.a"))
    }

    @Test func pidOnlyAppsAreControllableButNotPersisted() {
        let store = InMemoryVolumeStore()
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [process(pid: 42, executablePath: "/usr/bin/afplay")]
        let taps = FakeTapController()
        let model = makeModel(monitor, clock: Clock(t0), taps: taps, store: store)
        model.refresh()

        model.setVolume(0.2, for: "pid:42")

        #expect(store.volumes.isEmpty)
        #expect(taps.lastApplied == ["pid:42": TapSpec(processObjectIDs: [1_042], gain: 0.2)])
    }

    @Test func stopRemovesEveryTap() {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [process(pid: 1, bundleID: "com.example.a")]
        let taps = FakeTapController()
        let model = makeModel(monitor, clock: Clock(t0), taps: taps)
        model.start()
        model.setVolume(0.5, for: "com.example.a")
        #expect(!taps.lastApplied.isEmpty)

        model.stop()

        #expect(taps.lastApplied == [:])
    }

    @Test func groupsTwoChromeHelpersIntoOneEntry() {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [
            process(
                pid: 1,
                bundleID: "com.google.Chrome.helper",
                executablePath: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
            ),
            process(
                pid: 2,
                bundleID: "com.google.Chrome.helper.renderer",
                executablePath: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
            )
        ]
        let model = makeModel(monitor, clock: Clock(t0))

        model.refresh()

        #expect(model.apps.count == 1)
        #expect(model.apps[0].id == "/Applications/Google Chrome.app")
        #expect(model.apps[0].name == "Google Chrome")
        #expect(model.apps[0].isPlaying == true)
    }

    @Test func excludesProcessesNotRunningOutput() {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [
            process(pid: 1, bundleID: "com.example.playing", isRunningOutput: true),
            process(pid: 2, bundleID: "com.example.idle", isRunningOutput: false)
        ]
        let model = makeModel(monitor, clock: Clock(t0))

        model.refresh()

        #expect(model.apps.map(\.id) == ["com.example.playing"])
    }

    @Test func fallsBackToBundleIDWhenThereIsNoAppBundlePath() {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [process(pid: 7, bundleID: "com.example.tool")]
        let model = makeModel(monitor, clock: Clock(t0))

        model.refresh()

        #expect(model.apps == [
            PlayingApp(id: "com.example.tool", name: "com.example.tool", isPlaying: true, lastPlayedAt: t0)
        ])
    }

    @Test func fallsBackToPIDWhenThereIsNoBundleIDOrPath() {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [process(pid: 42)]
        let model = makeModel(monitor, clock: Clock(t0))

        model.refresh()

        #expect(model.apps == [
            PlayingApp(id: "pid:42", name: "PID 42", isPlaying: true, lastPlayedAt: t0)
        ])
    }

    @Test func emptyBundleIDFallsBackToPIDNamedAfterExecutable() {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [
            process(pid: 50, bundleID: "", executablePath: "/usr/bin/afplay"),
            process(pid: 51, bundleID: "", executablePath: "/usr/bin/afplay")
        ]
        let model = makeModel(monitor, clock: Clock(t0))

        model.refresh()

        #expect(model.apps.map(\.id) == ["pid:50", "pid:51"])
        #expect(model.apps.map(\.name) == ["afplay", "afplay"])
    }

    @Test func appThatStopsPlayingDisappearsAfterLingeringTenSeconds() {
        let clock = Clock(t0)
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [process(pid: 9, bundleID: "com.example.a")]
        let model = makeModel(monitor, clock: clock)
        model.refresh()
        #expect(model.apps.count == 1)

        monitor.processesToReturn = []
        clock.now = t0.addingTimeInterval(5)
        model.refresh()
        #expect(model.apps.count == 1)
        #expect(model.apps[0].isPlaying == false)

        clock.now = t0.addingTimeInterval(PlayingAppsTracker.lingerDuration)
        model.refresh()
        #expect(model.apps.isEmpty)
    }

    @Test func startObservesAndTracksMonitorChanges() {
        let clock = Clock(t0)
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [process(pid: 9, bundleID: "com.example.a")]
        let model = makeModel(monitor, clock: clock)

        model.start()
        #expect(monitor.startCallCount == 1)
        #expect(model.apps.map(\.id) == ["com.example.a"])

        // The monitor reports the new app; the old one lingers, dimmed.
        monitor.processesToReturn = [process(pid: 10, bundleID: "com.example.b")]
        monitor.simulateChange()
        #expect(model.apps.map(\.id) == ["com.example.a", "com.example.b"])
        #expect(model.apps.first { $0.id == "com.example.a" }?.isPlaying == false)
        #expect(model.apps.first { $0.id == "com.example.b" }?.isPlaying == true)

        // After the linger window the stopped app is gone.
        clock.now = t0.addingTimeInterval(PlayingAppsTracker.lingerDuration)
        model.refresh()
        #expect(model.apps.map(\.id) == ["com.example.b"])

        model.stop()
        #expect(monitor.stopCallCount == 1)
    }

    @Test func groupBuildsOneEntryPerIDWithInjectedDisplayName() {
        let processes = [
            process(pid: 1, bundleID: "com.example.a", executablePath: "/Applications/A.app/Contents/MacOS/A"),
            process(
                pid: 2,
                bundleID: "com.example.a",
                executablePath: "/Applications/A.app/Contents/Frameworks/A Helper.app/Contents/MacOS/A Helper"
            ),
            process(pid: 3, bundleID: "com.example.b")
        ]

        let grouped = PlayingAppsModel.group(processes) { _ in "A" }

        #expect(grouped.map(\.id) == ["/Applications/A.app", "com.example.b"])
        #expect(grouped.map(\.name) == ["A", "com.example.b"])
    }
}
