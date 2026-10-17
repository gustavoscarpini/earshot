import Testing
@testable import Earshot

struct GainCalculatorTests {
    @Test func unmutedPassesThroughAtFullVolume() {
        #expect(GainCalculator.effectiveGain(app: 1.0, master: 1.0, muted: false) == 1.0)
    }

    @Test func multipliesAppAndMaster() {
        #expect(GainCalculator.effectiveGain(app: 0.5, master: 0.5, muted: false) == 0.25)
    }

    @Test func mutedIgnoresGains() {
        #expect(GainCalculator.effectiveGain(app: 1.0, master: 1.0, muted: true) == 0)
        #expect(GainCalculator.effectiveGain(app: 0.3, master: 0.7, muted: true) == 0)
    }

    @Test func clampsAboveOne() {
        #expect(GainCalculator.effectiveGain(app: 1.5, master: 1.5, muted: false) == 1.0)
    }

    @Test func clampsBelowZero() {
        #expect(GainCalculator.effectiveGain(app: -0.5, master: 1.0, muted: false) == 0)
    }

    @Test func zeroOnEitherInputIsSilence() {
        #expect(GainCalculator.effectiveGain(app: 0, master: 1.0, muted: false) == 0)
        #expect(GainCalculator.effectiveGain(app: 1.0, master: 0, muted: false) == 0)
    }
}
