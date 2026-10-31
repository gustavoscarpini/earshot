import Foundation
import Testing
@testable import Earshot

struct MeterPlannerTests {
    private func input(_ id: String, volume: Float = 1, muted: Bool = false, objects: [UInt32] = [1]) -> TapPlanInput {
        TapPlanInput(id: id, volume: volume, muted: muted, processObjectIDs: objects)
    }

    @Test func noMetersWhilePanelIsHidden() {
        let plan = MeterPlanner.plan(apps: [input("a")], playingIDs: ["a"], volumeTapIDs: [], panelVisible: false)
        #expect(plan.isEmpty)
    }

    @Test func untappedPlayingAppGetsMeterWithSortedObjects() {
        let plan = MeterPlanner.plan(apps: [input("a", objects: [5, 2])], playingIDs: ["a"], volumeTapIDs: [], panelVisible: true)
        #expect(plan == ["a": MeterSpec(processObjectIDs: [2, 5])])
    }

    @Test func volumeTappedLingeringAndEmptyAppsGetNoMeter() {
        let plan = MeterPlanner.plan(
            apps: [input("tapped", volume: 0.5), input("idle"), input("none", objects: [])],
            playingIDs: ["tapped", "none"],
            volumeTapIDs: ["tapped"],
            panelVisible: true
        )
        #expect(plan.isEmpty)
    }

    @Test func meterChangesCreateRecreateDestroy() {
        let old = MeterSpec(processObjectIDs: [1])
        let new = MeterSpec(processObjectIDs: [1, 2])
        let changes = TapReconciler.meterChanges(
            current: ["gone": old, "same": old, "grown": old],
            desired: ["same": old, "grown": new, "fresh": old]
        )
        #expect(changes == [
            .destroy(id: "gone"),
            .create(id: "fresh", spec: old),
            .recreate(id: "grown", spec: new)
        ])
    }
}

struct LevelSmootherTests {
    @Test func attackIsInstantAndFallIsLinear() {
        var smoother = LevelSmoother()
        let up = smoother.update(peaks: ["a": 1], elapsed: 0.04)
        #expect(up["a"] == 1)
        let down = smoother.update(peaks: ["a": 0], elapsed: 0.1)
        #expect(abs((down["a"] ?? 0) - (1 - LevelSmoother.fallPerSecond * 0.1)) < 0.0001)
    }

    @Test func missingIdsFallToZeroAndAreDropped() {
        var smoother = LevelSmoother()
        _ = smoother.update(peaks: ["a": 1], elapsed: 0.04)
        let gone = smoother.update(peaks: [:], elapsed: 10)
        #expect(gone.isEmpty)
    }

    @Test func peaksMapThroughTheDecibelScale() {
        var smoother = LevelSmoother()
        let levels = smoother.update(peaks: ["a": 0.1], elapsed: 0.04)
        #expect(levels["a"] == LevelScale.normalized(peak: 0.1))
    }
}

@MainActor
struct PlayingAppsMeterTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 2_000)

    private func process(pid: pid_t, bundleID: String, running: Bool = true) -> AudioProcess {
        AudioProcess(
            objectID: UInt32(pid) + 1_000,
            pid: pid,
            bundleID: bundleID,
            executablePath: nil,
            isRunningOutput: running,
            isRunningInput: false
        )
    }

    private func makeModel(
        _ processes: [AudioProcess],
        taps: FakeTapController
    ) -> PlayingAppsModel {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = processes
        let model = PlayingAppsModel(
            monitor: monitor,
            tapController: taps,
            volumeStore: InMemoryVolumeStore(),
            now: { Date(timeIntervalSinceReferenceDate: 2_000) },
            ownPID: 99,
            ownBundleID: "com.example.earshot"
        )
        model.refresh()
        return model
    }

    @Test func metersExistOnlyWhilePanelIsVisible() {
        let taps = FakeTapController()
        let model = makeModel([process(pid: 1, bundleID: "com.example.a")], taps: taps)
        #expect(taps.lastPlan.meters.isEmpty)
        #expect(model.level(for: "com.example.a") == nil)

        model.panelDidAppear()
        #expect(taps.lastPlan.meters == ["com.example.a": MeterSpec(processObjectIDs: [1_001])])
        #expect(model.level(for: "com.example.a") == 0)

        model.panelDidDisappear()
        #expect(taps.lastPlan.meters.isEmpty)
        #expect(model.level(for: "com.example.a") == nil)
        #expect(model.levels.isEmpty)
    }

    @Test func volumeChangeSwapsMeterForVolumeTapAndBack() {
        let taps = FakeTapController()
        let model = makeModel([process(pid: 1, bundleID: "com.example.a")], taps: taps)
        model.panelDidAppear()

        model.setVolume(0.5, for: "com.example.a")
        #expect(taps.lastPlan.meters.isEmpty)
        #expect(taps.lastPlan.perApp["com.example.a"]?.gain == 0.5)

        model.setVolume(1, for: "com.example.a")
        #expect(taps.lastPlan.perApp.isEmpty)
        #expect(taps.lastPlan.meters.keys.sorted() == ["com.example.a"])
    }

    @Test func mutedAppReadsZeroAndHasVolumeTapNotMeter() {
        let taps = FakeTapController()
        taps.peaksToReturn = ["com.example.a": 1]
        let model = makeModel([process(pid: 1, bundleID: "com.example.a")], taps: taps)
        model.panelDidAppear()
        model.toggleMute("com.example.a")

        model.pollLevels()

        #expect(taps.lastPlan.meters.isEmpty)
        #expect(model.level(for: "com.example.a") == 0)
    }

    @Test func pollingPublishesLevelsFromTheController() {
        let taps = FakeTapController()
        taps.peaksToReturn = ["com.example.a": 1]
        let model = makeModel([process(pid: 1, bundleID: "com.example.a")], taps: taps)
        model.panelDidAppear()

        model.pollLevels()

        #expect(model.level(for: "com.example.a") == 1)
    }

    @Test func ownProcessAndIdleAppsAreNeverMetered() {
        let taps = FakeTapController()
        let model = makeModel(
            [
                process(pid: 1, bundleID: "com.example.a", running: false),
                process(pid: 2, bundleID: "com.example.earshot.helper")
            ],
            taps: taps
        )
        model.panelDidAppear()
        #expect(taps.lastPlan.meters.isEmpty)
    }

    @Test func stopRemovesMeters() {
        let taps = FakeTapController()
        let model = makeModel([process(pid: 1, bundleID: "com.example.a")], taps: taps)
        model.start()
        model.panelDidAppear()
        model.stop()
        #expect(taps.lastPlan == TapPlan(perApp: [:], global: nil))
    }
}
