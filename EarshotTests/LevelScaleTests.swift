import Testing
@testable import Earshot

struct LevelScaleTests {
    @Test func silenceIsZero() {
        #expect(LevelScale.normalized(peak: 0) == 0)
    }

    @Test func fullScaleIsOne() {
        #expect(LevelScale.normalized(peak: 1) == 1)
    }

    @Test func minusSixtyDecibelsIsZero() {
        #expect(abs(LevelScale.normalized(peak: 0.001)) < 0.0001)
    }

    @Test func belowTheFloorIsZero() {
        #expect(LevelScale.normalized(peak: 0.0001) == 0)
    }

    @Test func minusThirtyDecibelsIsHalf() {
        #expect(abs(LevelScale.normalized(peak: 0.0316228) - 0.5) < 0.001)
    }

    @Test func aboveFullScaleClampsToOne() {
        #expect(LevelScale.normalized(peak: 2) == 1)
    }

    @Test func negativeIsZero() {
        #expect(LevelScale.normalized(peak: -0.5) == 0)
    }
}
