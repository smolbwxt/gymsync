import XCTest
@testable import GymSync

/// Pure-function coverage for `SetProgression` — the within-session
/// next-set prefill rule. Research-aligned step sizing (2026-08): ~2.5%
/// upper / ~5% lower of the load, floored to the lifter's unit increment,
/// minimum one increment — which reproduces the old flat +5 lb at typical
/// upper-body loads (the first three tests are the pre-upgrade suite,
/// unchanged on purpose).
final class SetProgressionTests: XCTestCase {

    func testEasySetStepsUp() {
        // 2.5% of 355 = 8.875 → floors to one 5-lb increment.
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 355, rpe: 7, isFailed: false), 360)
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 225, rpe: 6, isFailed: false), 230)
        // 2.5% of 100 = 2.5 → below one increment → the one-increment floor.
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 100, rpe: 5, isFailed: false), 105)
    }

    func testHardSetHolds() {
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 355, rpe: 8, isFailed: false), 355)
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 355, rpe: 9, isFailed: false), 355)
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 355, rpe: 10, isFailed: false), 355)
    }

    func testFailedSetHoldsRegardlessOfRPE() {
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 355, rpe: 7, isFailed: true), 355)
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 355, rpe: 10, isFailed: true), 355)
    }

    func testMissingRPEHolds() {
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 355, rpe: nil, isFailed: false), 355)
    }

    func testLowerBodyStepsBigger() {
        // 5% of 355 = 17.75 → floors to three 5-lb increments (+15).
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 355, rpe: 7, isFailed: false,
                                                 isLowerBody: true), 370)
        // 5% of 135 = 6.75 → floors to one increment (+5).
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 135, rpe: 7, isFailed: false,
                                                 isLowerBody: true), 140)
    }

    func testKgUserStepsOnKgGrid() {
        // The old flat +5 lb handed kg users +2.27 kg — unbuildable. Now a
        // 100 kg upper-body load steps by exactly one 2.5 kg increment.
        let pounds = Units.toPounds(100, from: .kg)
        let next = SetProgression.nextWeight(afterPounds: pounds, rpe: 7, isFailed: false, unit: .kg)
        let nextKg = NSDecimalNumber(decimal: Units.fromPounds(next, to: .kg)).doubleValue
        XCTAssertEqual(nextKg, 102.5, accuracy: 0.001)
    }

    func testKgLowerBodyStep() {
        // 5% of 180 kg = 9 kg → floors to three 2.5 kg increments (+7.5).
        let pounds = Units.toPounds(180, from: .kg)
        let next = SetProgression.nextWeight(afterPounds: pounds, rpe: 6, isFailed: false,
                                             isLowerBody: true, unit: .kg)
        let nextKg = NSDecimalNumber(decimal: Units.fromPounds(next, to: .kg)).doubleValue
        XCTAssertEqual(nextKg, 187.5, accuracy: 0.001)
    }

    // MARK: - rescaledBase strain asymmetry (owner 2026-08-25)

    func testGrindUnderTargetHoldsTheLoad() {
        // 315 x 3 @ 9.5 against a 5-rep target: fatigue, not
        // misprescription - the bar holds, reps are allowed to erode.
        let base = SetProgression.rescaledBase(lastPounds: 315, lastReps: 3,
                                               lastRPE: 9.5, targetReps: 5)
        XCTAssertEqual(base, 315)
    }

    func testUnstrainedSingleStillRescalesDown() {
        // The original hazard: a deliberate 405 x 1 (RPE 6) must not
        // carry 405 into a set of 5.
        let base = SetProgression.rescaledBase(lastPounds: 405, lastReps: 1,
                                               lastRPE: 6, targetReps: 5)
        XCTAssertLessThan(base, 405)
    }

    func testNoRPELowRepSetRescalesDown() {
        // Unlogged RPE can't prove a grind - the hazard protection wins.
        let base = SetProgression.rescaledBase(lastPounds: 405, lastReps: 1,
                                               lastRPE: nil, targetReps: 5)
        XCTAssertLessThan(base, 405)
    }

    func testOvershootAlwaysRescalesUp() {
        // 20 reps on an 8-rep target raises the next set regardless of RPE.
        let base = SetProgression.rescaledBase(lastPounds: 100, lastReps: 20,
                                               lastRPE: 10, targetReps: 8)
        XCTAssertGreaterThan(base, 100)
    }

    func testOnTargetHoldsExactly() {
        let base = SetProgression.rescaledBase(lastPounds: 225, lastReps: 5,
                                               lastRPE: 8, targetReps: 5)
        XCTAssertEqual(base, 225)
    }
}