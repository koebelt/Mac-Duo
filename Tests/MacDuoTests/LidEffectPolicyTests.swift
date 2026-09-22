import Testing
@testable import MacDuo

struct LidEffectPolicyTests {
    private let highThreshold = LidEffectPolicy(threshold: 130, hysteresis: 4)

    @Test
    func testOpeningReleasesWithoutReachingHysteresisAngle() {
        #expect(activeEffect(angle: 129, opening: false))
        #expect(!activeEffect(angle: 130, opening: true, minimumDurationElapsed: false))
        #expect(!activeEffect(angle: 131, opening: true))
        #expect(!activeEffect(angle: 133, opening: true))
    }

    @Test
    func testStationaryLidBelowThresholdKeepsActiveEffect() {
        #expect(activeEffect(angle: 129, opening: false))
    }

    @Test
    func testJitterAroundThresholdUsesOrdinaryHysteresis() {
        #expect(activeEffect(angle: 129.8, opening: false))
        #expect(activeEffect(angle: 130.2, opening: false))
        #expect(activeEffect(angle: 129.9, opening: false))
    }

    @Test
    func testOrdinaryConfigurationStillReleasesAtHysteresisAngle() {
        let policy = LidEffectPolicy(threshold: 90, hysteresis: 4)

        #expect(wantsActiveEffect(policy: policy, angle: 93.9, opening: false))
        #expect(!wantsActiveEffect(policy: policy, angle: 94, opening: false))
    }

    @Test
    func testOpeningReversalInvalidatesClosingMemory() {
        var intent = LidMotionIntent()
        intent.update(angularVelocity: -3, at: 10, closingSpeed: 2, openingSpeed: 2)
        #expect(intent.wasClosingRecently(at: 10.1, memoryDuration: 1.5))

        intent.update(angularVelocity: 3, at: 10.2, closingSpeed: 2, openingSpeed: 2)
        #expect(!intent.wasClosingRecently(at: 10.2, memoryDuration: 1.5))

        // A sub-threshold jitter sample must not restore closing intent.
        intent.update(angularVelocity: -0.4, at: 10.3, closingSpeed: 2, openingSpeed: 2)
        #expect(!intent.wasClosingRecently(at: 10.3, memoryDuration: 1.5))
        #expect(
            !highThreshold.wantsEffect(
                isEnabled: true,
                isActive: false,
                angle: 129.9,
                predictedAngle: 129.9,
                riseSinceLowest: 0,
                riseSinceIdleLow: 0,
                hasBeenAboveThreshold: true,
                wasClosingRecently: intent.wasClosingRecently(at: 10.3, memoryDuration: 1.5),
                isClearlyOpening: false,
                hasDwelledOpen: false,
                minimumDurationElapsed: true
            )
        )
    }

    @Test
    func testRestingBelowThresholdDoesNotActivate() {
        #expect(
            !highThreshold.wantsEffect(
                isEnabled: true,
                isActive: false,
                angle: 129,
                predictedAngle: 129,
                riseSinceLowest: 0,
                riseSinceIdleLow: 0,
                hasBeenAboveThreshold: true,
                wasClosingRecently: false,
                isClearlyOpening: false,
                hasDwelledOpen: false,
                minimumDurationElapsed: true
            )
        )
    }

    @Test
    func testSlowOpeningReleasesAfterDwell() {
        #expect(activeEffect(angle: 133, opening: false))
        #expect(!activeEffect(angle: 133, opening: false, dwelled: true))
    }

    @Test
    func testDwellAngleIsTheThreshold() {
        // A hinge whose limit rounds to the threshold must still release.
        #expect(highThreshold.dwellAngle == 130)
    }

    @Test
    func testDwellRestartsWhenLidDropsBelowDwellAngle() {
        let dwellAngle = highThreshold.dwellAngle
        var dwell = LidOpenDwell()
        dwell.update(angle: 130, at: 10, dwellAngle: dwellAngle)
        #expect(!dwell.hasDwelled(at: 10.5, duration: 1))
        #expect(dwell.hasDwelled(at: 11, duration: 1))

        // Jitter back below the start angle restarts the wait.
        dwell.update(angle: 129.5, at: 11.1, dwellAngle: dwellAngle)
        dwell.update(angle: 130, at: 11.2, dwellAngle: dwellAngle)
        #expect(!dwell.hasDwelled(at: 12, duration: 1))
    }

    @Test
    func testOneWholeDegreeStepDoesNotReleaseOnOpening() {
        // A whole-degree sensor resting on a half-degree boundary alternates
        // 129/130. The step reads as fast opening, but the rise is only 1°.
        #expect(activeEffect(angle: 130, opening: true, rise: 1))
        #expect(activeEffect(angle: 130, opening: true, rise: 1, minimumDurationElapsed: false))
    }

    @Test
    func testRiseAboveOneStepReleasesOnOpening() {
        #expect(!activeEffect(angle: 130, opening: true, rise: LidEffectPolicy.minimumReleaseRise))
        #expect(!activeEffect(angle: 130.9, opening: true, rise: 70))
    }

    @Test
    func testSmallOpeningStillReleasesThroughDwell() {
        // Too small a rise for the speed release, but held above the threshold.
        #expect(!activeEffect(angle: 130, opening: false, dwelled: true, rise: 1))
    }

    // MARK: - Playing the effect in reverse as the lid opens

    @Test
    func testRisingLidStartsAnOpeningRun() {
        // The run macOS slept through: the lid comes back up from nearly shut
        // with nothing on screen.
        #expect(openingRun(angle: 30, rise: 12))
    }

    @Test
    func testOpeningRunNeedsAnOpeningLid() {
        #expect(!openingRun(angle: 30, rise: 12, opening: false))
    }

    @Test
    func testTiltingTheScreenUpDoesNotStartAnOpeningRun() {
        // A few degrees of adjustment while working must be ignored.
        #expect(!openingRun(angle: 60, rise: 4))
    }

    @Test
    func testOpeningRunNeedsRoomLeftBelowTheStartAngle() {
        #expect(openingRun(angle: 80, rise: 12))
        #expect(!openingRun(angle: 81, rise: 12))
    }

    @Test
    func testOpeningRunOnlyStartsWhenTheSettingIsOn() {
        #expect(!openingRun(angle: 30, rise: 12, playsOnOpen: false))
    }

    @Test
    func testOpeningRunReleasesBackAtTheStartAngle() {
        let policy = LidEffectPolicy(threshold: 90, hysteresis: 4, playsOnOpen: true)
        #expect(wantsActiveEffect(policy: policy, angle: 89, opening: true))
        #expect(!wantsActiveEffect(policy: policy, angle: 90, opening: true))
    }

    /// The lid rising with nothing on screen, at the default start angle.
    private func openingRun(
        angle: Double,
        rise: Double,
        opening: Bool = true,
        playsOnOpen: Bool = true
    ) -> Bool {
        LidEffectPolicy(threshold: 90, hysteresis: 4, playsOnOpen: playsOnOpen).wantsEffect(
            isEnabled: true,
            isActive: false,
            angle: angle,
            predictedAngle: angle,
            riseSinceLowest: 0,
            riseSinceIdleLow: rise,
            hasBeenAboveThreshold: false,
            wasClosingRecently: false,
            isClearlyOpening: opening,
            hasDwelledOpen: false,
            minimumDurationElapsed: true
        )
    }

    private func activeEffect(
        angle: Double,
        opening: Bool,
        dwelled: Bool = false,
        rise: Double = 40,
        minimumDurationElapsed: Bool = true
    ) -> Bool {
        wantsActiveEffect(
            policy: highThreshold,
            angle: angle,
            opening: opening,
            dwelled: dwelled,
            rise: rise,
            minimumDurationElapsed: minimumDurationElapsed
        )
    }

    private func wantsActiveEffect(
        policy: LidEffectPolicy,
        angle: Double,
        opening: Bool,
        dwelled: Bool = false,
        rise: Double = 40,
        minimumDurationElapsed: Bool = true
    ) -> Bool {
        policy.wantsEffect(
            isEnabled: true,
            isActive: true,
            angle: angle,
            predictedAngle: angle,
            riseSinceLowest: rise,
            riseSinceIdleLow: rise,
            hasBeenAboveThreshold: true,
            wasClosingRecently: false,
            isClearlyOpening: opening,
            hasDwelledOpen: dwelled,
            minimumDurationElapsed: minimumDurationElapsed
        )
    }
}
