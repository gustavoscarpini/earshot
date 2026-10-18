import Testing
@testable import Earshot

struct TapReconcilerTests {
    private let spec = TapSpec(processObjectIDs: [2, 1], gain: 0.5)

    @Test func specSortsProcessObjectIDs() {
        #expect(spec.processObjectIDs == [1, 2])
    }

    @Test func nothingToNothingIsNoChange() {
        #expect(TapReconciler.changes(current: [:], desired: [:]).isEmpty)
    }

    @Test func newAppIsCreated() {
        #expect(TapReconciler.changes(current: [:], desired: ["a": spec]) == [.create(id: "a", spec: spec)])
    }

    @Test func identicalSpecIsNoChange() {
        #expect(TapReconciler.changes(current: ["a": spec], desired: ["a": spec]).isEmpty)
    }

    @Test func gainOnlyChangeUpdatesInPlace() {
        let louder = TapSpec(processObjectIDs: [1, 2], gain: 0.8)
        #expect(TapReconciler.changes(current: ["a": spec], desired: ["a": louder]) == [.updateGain(id: "a", gain: 0.8)])
    }

    @Test func processSetChangeRecreates() {
        let withHelper = TapSpec(processObjectIDs: [1, 2, 3], gain: 0.5)
        #expect(TapReconciler.changes(current: ["a": spec], desired: ["a": withHelper]) == [.recreate(id: "a", spec: withHelper)])
    }

    @Test func missingAppIsDestroyedBeforeOtherChanges() {
        let changes = TapReconciler.changes(current: ["z": spec], desired: ["a": spec])
        #expect(changes == [.destroy(id: "z"), .create(id: "a", spec: spec)])
    }

    // MARK: Global tap

    private let global = GlobalTapSpec(excludedProcessObjectIDs: [5, 3], gain: 0.5)

    @Test func globalSpecSortsExclusions() {
        #expect(global.excludedProcessObjectIDs == [3, 5])
    }

    @Test func noGlobalTapToNoGlobalTapIsNoChange() {
        #expect(TapReconciler.globalChange(current: nil, desired: nil) == nil)
    }

    @Test func newGlobalTapIsCreated() {
        #expect(TapReconciler.globalChange(current: nil, desired: global) == .create(global))
    }

    @Test func goneGlobalTapIsDestroyed() {
        #expect(TapReconciler.globalChange(current: global, desired: nil) == .destroy)
    }

    @Test func exclusionChangeRecreatesGlobalTap() {
        let more = GlobalTapSpec(excludedProcessObjectIDs: [3, 5, 9], gain: 0.5)
        #expect(TapReconciler.globalChange(current: global, desired: more) == .recreate(more))
    }

    @Test func exclusionAndGainChangeRecreatesGlobalTap() {
        let both = GlobalTapSpec(excludedProcessObjectIDs: [3], gain: 0.9)
        #expect(TapReconciler.globalChange(current: global, desired: both) == .recreate(both))
    }

    @Test func globalGainOnlyChangeUpdatesInPlace() {
        let louder = GlobalTapSpec(excludedProcessObjectIDs: [3, 5], gain: 0.8)
        #expect(TapReconciler.globalChange(current: global, desired: louder) == .updateGain(0.8))
    }

    @Test func identicalGlobalSpecIsNoChange() {
        #expect(TapReconciler.globalChange(current: global, desired: global) == nil)
    }
}
