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
}
