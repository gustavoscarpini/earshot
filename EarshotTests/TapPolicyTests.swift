import Testing
@testable import Earshot

struct TapPolicyTests {
    @Test func fullVolumeUnmutedNeedsNoTap() {
        #expect(TapPolicy.needsTap(volume: 1.0, muted: false) == false)
    }

    @Test func mutedAlwaysNeedsTap() {
        #expect(TapPolicy.needsTap(volume: 1.0, muted: true))
        #expect(TapPolicy.needsTap(volume: 0.4, muted: true))
    }

    @Test func anyVolumeBelowFullNeedsTap() {
        #expect(TapPolicy.needsTap(volume: 0.999, muted: false))
        #expect(TapPolicy.needsTap(volume: 0.0, muted: false))
    }

    @Test func volumeAboveFullNeedsTap() {
        #expect(TapPolicy.needsTap(volume: 1.001, muted: false))
    }
}
