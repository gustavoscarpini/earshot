import Testing
@testable import Earshot

struct TapPlannerTests {
    private func input(
        _ id: String,
        volume: Float = 1,
        muted: Bool = false,
        objects: [UInt32] = [1]
    ) -> TapPlanInput {
        TapPlanInput(id: id, volume: volume, muted: muted, processObjectIDs: objects)
    }

    @Test func fullVolumeAndFullMasterNeedNoTaps() {
        let plan = TapPlanner.plan(apps: [input("a")], softwareMaster: 1)
        #expect(plan == TapPlan(perApp: [:], global: nil))
    }

    @Test func appGainMultipliesBySoftwareMaster() {
        let plan = TapPlanner.plan(apps: [input("a", volume: 0.6, objects: [4, 2])], softwareMaster: 0.5)
        #expect(plan.perApp == ["a": TapSpec(processObjectIDs: [2, 4], gain: 0.3)])
    }

    @Test func globalTapAppearsOnlyBelowFullMaster() {
        #expect(TapPlanner.plan(apps: [], softwareMaster: 1).global == nil)
        #expect(TapPlanner.plan(apps: [], softwareMaster: 0.99).global == GlobalTapSpec(excludedProcessObjectIDs: [], gain: 0.99))
    }

    @Test func globalTapExcludesEveryTappedProcessSorted() {
        let plan = TapPlanner.plan(
            apps: [
                input("a", volume: 0.5, objects: [9, 3]),
                input("b", volume: 0.2, objects: [5, 3]),
                input("untapped", objects: [7])
            ],
            softwareMaster: 0.5
        )
        #expect(plan.global == GlobalTapSpec(excludedProcessObjectIDs: [3, 5, 9], gain: 0.5))
    }

    @Test func mutedAppHasZeroGain() {
        let plan = TapPlanner.plan(apps: [input("a", muted: true)], softwareMaster: 1)
        #expect(plan.perApp["a"]?.gain == 0)
        #expect(plan.global == nil)
    }

    @Test func softwareMuteMakesGlobalGainZero() {
        let plan = TapPlanner.plan(apps: [input("a", volume: 0.5)], softwareMaster: 0)
        #expect(plan.global?.gain == 0)
        #expect(plan.perApp["a"]?.gain == 0)
    }

    @Test func appWithoutProcessObjectsIsNotTapped() {
        let plan = TapPlanner.plan(apps: [input("a", volume: 0.5, objects: [])], softwareMaster: 1)
        #expect(plan.perApp.isEmpty)
    }
}
