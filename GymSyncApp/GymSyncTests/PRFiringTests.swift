import XCTest
@testable import GymSync

/// Docket row 7 (2026-09-03, P1), pinned: WHEN the PR celebration fires.
///
/// The contract here is a product decision, not an implementation detail —
/// the owner's "not what we designed" had a logic half, and this is it. Two
/// rules: the first-ever log of a lift is a BASELINE (there was nothing to
/// beat), and the celebration waits for the last prescribed set of that
/// exercise. Waiting is not losing (ruling R-OD-1): the record is HELD and
/// fired at completion, which is what most of this suite exists to pin —
/// the first shape of the rule answered a `Bool` per set and dropped the
/// moment entirely on straight sets.
///
/// What these do NOT pin, deliberately: whether the set is a record. That is
/// `PersonalRecordMath.isPR`, its behaviour is unchanged, and the `record`
/// payload here is that answer arriving from the caller.
final class PRFiringTests: XCTestCase {

    private func context(basisIsEmpty: Bool = false,
                         setsLogged: Int = 1,
                         targetSets: Int? = nil) -> PRFiring.Context {
        PRFiring.Context(basisIsEmpty: basisIsEmpty,
                         setsLogged: setsLogged,
                         targetSets: targetSets)
    }

    private func record(_ weight: Decimal, _ reps: Int, prior: Decimal,
                        name: String = "Bench Press") -> PRFiring.Pending {
        PRFiring.Pending(exerciseName: name, weight: weight, reps: reps, priorBest: prior)
    }

    /// One exercise, set by set, exactly as both view bodies drive it: hold
    /// what `step` hands back, collect what it celebrates. The bodies own
    /// only the dictionary this stands in for.
    private func walk(_ sets: [(PRFiring.Pending?, PRFiring.Context)])
        -> (celebrations: [PRFiring.Pending], held: PRFiring.Pending?) {
        var held: PRFiring.Pending?
        var fired: [PRFiring.Pending] = []
        for (newRecord, setContext) in sets {
            let step = PRFiring.step(record: newRecord, context: setContext, held: held)
            held = step.held
            if let celebration = step.celebrate { fired.append(celebration) }
        }
        return (fired, held)
    }

    // MARK: - Rule (a): a first log is a baseline

    func testEmptyBasisNeverCelebratesAndHoldsNothing() {
        // The bug this exists for: `bestWeight` answers 0 for an empty basis,
        // so `weight > 0` made the first set of a never-logged lift a PR.
        // It must not celebrate AND it must not be held for later, or the
        // baseline would simply arrive three sets late.
        let step = PRFiring.step(
            record: record(135, 5, prior: 0),
            context: context(basisIsEmpty: true, setsLogged: 1, targetSets: nil),
            held: nil)
        XCTAssertNil(step.celebrate)
        XCTAssertNil(step.held)
    }

    func testEmptyBasisNeverCelebratesEvenOnTheLastSet() {
        // Rule (a) is not a "wait longer" rule — no amount of sets turns a
        // baseline into a record.
        let walked = walk([
            (record(135, 5, prior: 0), context(basisIsEmpty: true, setsLogged: 1, targetSets: 3)),
            (record(135, 5, prior: 0), context(basisIsEmpty: true, setsLogged: 2, targetSets: 3)),
            (record(135, 5, prior: 0), context(basisIsEmpty: true, setsLogged: 3, targetSets: 3))
        ])
        XCTAssertTrue(walked.celebrations.isEmpty)
        XCTAssertNil(walked.held)
    }

    // MARK: - Rule (b): the celebration waits for the last set, and DEFERS

    func testRecordMidExerciseIsHeldNotDropped() {
        let step = PRFiring.step(record: record(205, 5, prior: 200),
                                 context: context(setsLogged: 2, targetSets: 3),
                                 held: nil)
        XCTAssertNil(step.celebrate)
        XCTAssertEqual(step.held, record(205, 5, prior: 200))
    }

    func testEarlySetRecordIsCelebratedAtCompletionWithThePreExercisePrior() {
        // THE DOCKET'S CASE, and the one the first shape of this rule lost:
        // 3 × 5, prior best 200, 205 on all three sets. Set 1 is the record;
        // sets 2 and 3 are judged against a basis that now contains 205, so
        // they are not records at all. The moment must still arrive, once, at
        // set 3 — and it must read against 200, the best before the exercise
        // began.
        let walked = walk([
            (record(205, 5, prior: 200), context(setsLogged: 1, targetSets: 3)),
            (nil, context(setsLogged: 2, targetSets: 3)),
            (nil, context(setsLogged: 3, targetSets: 3))
        ])
        XCTAssertEqual(walked.celebrations, [record(205, 5, prior: 200)])
        XCTAssertNil(walked.held)
    }

    func testTwoRecordsInOneExerciseCelebrateOnceWithTheEarliestPriorAndTheBestValue() {
        // An ascending lifter: 205 on set 1, 215 on set 2 (now judged against
        // 205), 215 again on set 3. ONE celebration, the best number, and the
        // prior the exercise STARTED from — never "10 over your best" against
        // the lifter's own set four minutes ago.
        let walked = walk([
            (record(205, 5, prior: 200), context(setsLogged: 1, targetSets: 3)),
            (record(215, 5, prior: 205), context(setsLogged: 2, targetSets: 3)),
            (nil, context(setsLogged: 3, targetSets: 3))
        ])
        XCTAssertEqual(walked.celebrations.count, 1)
        XCTAssertEqual(walked.celebrations.first, record(215, 5, prior: 200))
        XCTAssertNil(walked.held)
    }

    func testRecordOnTheLastSetFiresAtOnce() {
        let walked = walk([
            (nil, context(setsLogged: 1, targetSets: 3)),
            (nil, context(setsLogged: 2, targetSets: 3)),
            (record(205, 5, prior: 200), context(setsLogged: 3, targetSets: 3))
        ])
        XCTAssertEqual(walked.celebrations, [record(205, 5, prior: 200)])
        XCTAssertNil(walked.held)
    }

    func testScaledDownPrescriptionCelebratesOnItsOwnLastSet() {
        // An accepted scale-down of 4 × 5 → 3 × 5 means the third set IS the
        // last one: `targetSets` comes from the EFFECTIVE routine row, the
        // number the screen printed, never the routine's original 4.
        XCTAssertTrue(PRFiring.isComplete(context(setsLogged: 3, targetSets: 3)))
        XCTAssertFalse(PRFiring.isComplete(context(setsLogged: 3, targetSets: 4)))
        // Which is the difference between a moment that arrives and one still
        // waiting for a fourth set the screen never asked for.
        let scaled = walk([
            (record(205, 5, prior: 200), context(setsLogged: 1, targetSets: 3)),
            (nil, context(setsLogged: 2, targetSets: 3)),
            (nil, context(setsLogged: 3, targetSets: 3))
        ])
        XCTAssertEqual(scaled.celebrations.count, 1)
    }

    func testAnExtraSetPastThePrescriptionStillCompletes() {
        // A fifth set of a 4-set prescription is past "all sets", not short of
        // it — `>=`, so a lifter who adds a set is not silently robbed.
        XCTAssertTrue(PRFiring.isComplete(context(setsLogged: 5, targetSets: 4)))
    }

    func testAHeldPayloadThatNeverCompletesStaysHeldForTheBodyToFlush() {
        // Sets skipped, the exercise swapped, the lifter moving on: `step`
        // keeps holding, and the VIEW BODY fires it on the way out (ruling
        // R-OD-2, `flushPendingPRs`). What is pinned here is that nothing is
        // dropped on the way.
        let walked = walk([
            (record(205, 5, prior: 200), context(setsLogged: 1, targetSets: 4)),
            (nil, context(setsLogged: 2, targetSets: 4))
        ])
        XCTAssertTrue(walked.celebrations.isEmpty)
        XCTAssertEqual(walked.held, record(205, 5, prior: 200))
    }

    func testUnprescribedExerciseCelebratesOnTheRecord() {
        // Freestyle, or a lift picked mid-session: there is no "all sets" to
        // wait for, and withholding the moment forever would delete it.
        let walked = walk([
            (record(205, 5, prior: 200), context(setsLogged: 1, targetSets: nil))
        ])
        XCTAssertEqual(walked.celebrations, [record(205, 5, prior: 200)])
        XCTAssertNil(walked.held)
    }

    // MARK: - Not a record at all

    func testAnOrdinarySetCelebratesNothingAndHoldsNothing() {
        let step = PRFiring.step(record: nil,
                                 context: context(setsLogged: 3, targetSets: 3),
                                 held: nil)
        XCTAssertNil(step.celebrate)
        XCTAssertNil(step.held)
    }

    // MARK: - The rep-PR twin reads the same rule

    func testRepPRFirstBodyweightSetIsABaselineToo() {
        // `priorBestReps` is `max() ?? 0`, so a first bodyweight set beat
        // nothing and celebrated for exactly the reason rule (a) names. The
        // rep form is `weight == 0` with `priorBest` carrying prior REPS.
        let baseline = PRFiring.step(record: record(0, 12, prior: 0),
                                     context: context(basisIsEmpty: true, setsLogged: 1, targetSets: 3),
                                     held: nil)
        XCTAssertNil(baseline.celebrate)
        XCTAssertNil(baseline.held)
        // With history, the same rep record defers to the last set and then
        // arrives — reps deciding "best" because both weights are 0.
        let walked = walk([
            (record(0, 12, prior: 10), context(setsLogged: 1, targetSets: 3)),
            (record(0, 14, prior: 12), context(setsLogged: 2, targetSets: 3)),
            (nil, context(setsLogged: 3, targetSets: 3))
        ])
        XCTAssertEqual(walked.celebrations, [record(0, 14, prior: 10)])
    }

    func testAWeightedRecordAndARepRecordAreNeverMergedIntoOne() {
        // Two different sentences with two different `priorBest` meanings (a
        // weight and a rep count). The later form replaces the earlier one
        // and travels with its own prior, rather than printing a rep count
        // where a weight belongs.
        let merged = PRFiring.merged(record(95, 5, prior: 90),
                                     into: record(0, 14, prior: 10))
        XCTAssertEqual(merged, record(95, 5, prior: 90))
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
