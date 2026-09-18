import XCTest
@testable import GymSync

/// Docket row 7 (2026-09-03, P1), pinned: WHEN the PR celebration fires.
///
/// The contract here is a product decision, not an implementation detail —
/// the owner's "not what we designed" had a logic half, and this is it. Two
/// rules: the first-ever log of a lift is a BASELINE (there was nothing to
/// beat), and the celebration waits for the last prescribed set of that
/// exercise. Neither rule was implemented anywhere before `PRFiring`; both
/// live-view bodies now read this one answer.
///
/// What these do NOT pin, deliberately: whether the set is a record. That is
/// `PersonalRecordMath.isPR`, its behaviour is unchanged, and `isRecord` here
/// is that answer arriving from the caller.
final class PRFiringTests: XCTestCase {

    private func context(basisIsEmpty: Bool = false,
                         setsLogged: Int = 1,
                         targetSets: Int? = nil) -> PRFiring.Context {
        PRFiring.Context(basisIsEmpty: basisIsEmpty,
                         setsLogged: setsLogged,
                         targetSets: targetSets)
    }

    // MARK: - Rule (a): a first log is a baseline

    func testEmptyBasisNeverCelebrates() {
        // The bug this exists for: `bestWeight` answers 0 for an empty basis,
        // so `weight > 0` made the first set of a never-logged lift a PR.
        XCTAssertFalse(PRFiring.shouldCelebrate(
            isRecord: true,
            context: context(basisIsEmpty: true, setsLogged: 1, targetSets: nil)))
    }

    func testEmptyBasisNeverCelebratesEvenOnTheLastSet() {
        // Rule (a) is not a "wait longer" rule — no amount of sets turns a
        // baseline into a record.
        XCTAssertFalse(PRFiring.shouldCelebrate(
            isRecord: true,
            context: context(basisIsEmpty: true, setsLogged: 3, targetSets: 3)))
    }

    // MARK: - Rule (b): the celebration waits for the last set

    func testRecordMidExerciseDoesNotCelebrate() {
        XCTAssertFalse(PRFiring.shouldCelebrate(
            isRecord: true,
            context: context(setsLogged: 2, targetSets: 3)))
    }

    func testRecordOnTheLastSetCelebrates() {
        XCTAssertTrue(PRFiring.shouldCelebrate(
            isRecord: true,
            context: context(setsLogged: 3, targetSets: 3)))
    }

    func testScaledDownPrescriptionCelebratesOnItsOwnLastSet() {
        // An accepted scale-down of 4 × 5 → 3 × 5 means the third set IS the
        // last one: `targetSets` comes from the EFFECTIVE routine row, the
        // number the screen printed, never the routine's original 4.
        XCTAssertTrue(PRFiring.shouldCelebrate(
            isRecord: true,
            context: context(setsLogged: 3, targetSets: 3)))
        XCTAssertFalse(PRFiring.shouldCelebrate(
            isRecord: true,
            context: context(setsLogged: 3, targetSets: 4)))
    }

    func testAnExtraSetPastThePrescriptionStillCelebrates() {
        // A fifth set of a 4-set prescription is past "all sets", not short of
        // it — `>=`, so a lifter who adds a set is not silently robbed.
        XCTAssertTrue(PRFiring.shouldCelebrate(
            isRecord: true,
            context: context(setsLogged: 5, targetSets: 4)))
    }

    func testUnprescribedExerciseCelebratesOnTheRecord() {
        // Freestyle, or a lift picked mid-session: there is no "all sets" to
        // wait for, and withholding the moment forever would delete it.
        XCTAssertTrue(PRFiring.shouldCelebrate(
            isRecord: true,
            context: context(setsLogged: 1, targetSets: nil)))
    }

    // MARK: - Not a record at all

    func testNoRecordNeverCelebrates() {
        XCTAssertFalse(PRFiring.shouldCelebrate(
            isRecord: false,
            context: context(setsLogged: 3, targetSets: 3)))
        XCTAssertFalse(PRFiring.shouldCelebrate(
            isRecord: false,
            context: context(basisIsEmpty: true, setsLogged: 1, targetSets: nil)))
    }

    // MARK: - The rep-PR twin reads the same rule

    func testRepPRFirstBodyweightSetIsABaselineToo() {
        // `priorBestReps` is `max() ?? 0`, so a first bodyweight set beat
        // nothing and celebrated for exactly the reason rule (a) names.
        XCTAssertFalse(PRFiring.shouldCelebrate(
            isRecord: true,
            context: context(basisIsEmpty: true, setsLogged: 1, targetSets: 3)))
        // With history, the same rep record still waits for the last set.
        XCTAssertFalse(PRFiring.shouldCelebrate(
            isRecord: true,
            context: context(setsLogged: 1, targetSets: 3)))
        XCTAssertTrue(PRFiring.shouldCelebrate(
            isRecord: true,
            context: context(setsLogged: 3, targetSets: 3)))
    }

    // MARK: - The guard the rule reads

    func testQualifyingBasisIsEmptyMeansNothingToBeat() {
        let basis: [(weight: Decimal, reps: Int)] = [(225, 8), (185, 12)]
        XCTAssertTrue(PersonalRecordMath.qualifyingBasisIsEmpty(atLeastReps: 5, in: []))
        XCTAssertFalse(PersonalRecordMath.qualifyingBasisIsEmpty(atLeastReps: 5, in: basis))
        // "At least" is load-bearing here too: a 15-rep set has no 15+ rep
        // history to be judged against, so it is a baseline at that rep count
        // even though the lifter has logged this lift before.
        XCTAssertTrue(PersonalRecordMath.qualifyingBasisIsEmpty(atLeastReps: 15, in: basis))
        // And `isPR` itself is unchanged by any of this — an empty basis still
        // says the set IS a record, because it is.
        XCTAssertTrue(PersonalRecordMath.isPR(weight: 135, reps: 5, basis: []))
    }
}
