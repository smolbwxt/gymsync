import XCTest
@testable import GymSync

/// Pure-function coverage for `PersonalRecordMath` — what the app is willing
/// to call a personal record, and what it will call a one-rep max.
///
/// The contract these pin is a product decision, not an implementation
/// detail (owner 2026-08-02): a PR is something you actually accomplished,
/// judged at the rep count you did it at; a 1RM is measured if you've ever
/// done a single and estimated otherwise. Expectations are hand-computed —
/// none of these re-derive the implementation's own arithmetic.
final class PersonalRecordMathTests: XCTestCase {

    /// Named `SetPair`, not `Set` — shadowing the standard library's `Set`
    /// inside a test class is a debugging trap nobody needs.
    private typealias SetPair = (weight: Decimal, reps: Int)

    /// Epley estimates run through `Decimal` division by 30, which repeats for
    /// most rep counts (10/30 = 0.333…), so an exact-equality assertion on an
    /// estimate is fragile by construction. Compare the value, not its last
    /// binary digit.
    private func assertPounds(_ actual: Decimal?, _ expected: Double,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { return XCTFail("expected \(expected), got nil", file: file, line: line) }
        XCTAssertEqual(NSDecimalNumber(decimal: actual).doubleValue, expected,
                       accuracy: 0.01, file: file, line: line)
    }

    // MARK: - A PR is judged at its rep count

    /// The case that motivated the rule: more reps at a weight you've already
    /// lifted IS an achievement, and the old weight-only rule celebrated
    /// nothing for it.
    func testMoreRepsAtTheSameWeightIsAPR() {
        let history: [SetPair] = [(100, 10)]
        XCTAssertTrue(PersonalRecordMath.isPR(weight: 100, reps: 12, basis: history))
    }

    /// The mirror: fewer reps at a weight you've already beaten is not an
    /// achievement. Having done 8 × 225, a 5 × 225 is demonstrably easier
    /// work — the "at least N reps" comparison is what catches this.
    func testFewerRepsAtAnAlreadyBeatenWeightIsNotAPR() {
        let history: [SetPair] = [(225, 8)]
        XCTAssertFalse(PersonalRecordMath.isPR(weight: 225, reps: 5, basis: history))
    }

    /// A heavy single and a hard set of ten are separate achievements: a new
    /// top single stands on its own even though the 10-rep work is "better"
    /// by estimated 1RM.
    func testAHeavySingleIsItsOwnRecord() {
        let history: [SetPair] = [(225, 10), (315, 1)]
        XCTAssertTrue(PersonalRecordMath.isPR(weight: 320, reps: 1, basis: history))
        // …and does not make every future 10-rep set look like a failure.
        XCTAssertTrue(PersonalRecordMath.isPR(weight: 230, reps: 10, basis: history))
    }

    /// Matching your best is not beating it.
    func testEqualingTheBestIsNotAPR() {
        let history: [SetPair] = [(200, 5)]
        XCTAssertFalse(PersonalRecordMath.isPR(weight: 200, reps: 5, basis: history))
    }

    /// First-ever qualifying work sets the bar and counts.
    func testFirstEverSetIsAPR() {
        XCTAssertTrue(PersonalRecordMath.isPR(weight: 95, reps: 5, basis: []))
    }

    /// No rep count means nothing to judge against — the app declines rather
    /// than inventing a comparison.
    func testMissingRepsIsNeverAPR() {
        XCTAssertFalse(PersonalRecordMath.isPR(weight: 500, reps: nil, basis: []))
        XCTAssertFalse(PersonalRecordMath.isPR(weight: 500, reps: 0, basis: []))
    }

    // MARK: - bestWeight(atLeastReps:)

    func testBestWeightConsidersOnlySetsMeetingTheRepThreshold() {
        let history: [SetPair] = [(315, 1), (225, 5), (185, 10)]
        XCTAssertEqual(PersonalRecordMath.bestWeight(atLeastReps: 1, in: history), 315)
        XCTAssertEqual(PersonalRecordMath.bestWeight(atLeastReps: 5, in: history), 225)
        XCTAssertEqual(PersonalRecordMath.bestWeight(atLeastReps: 10, in: history), 185)
        // Nothing done for 12+ reps yet.
        XCTAssertEqual(PersonalRecordMath.bestWeight(atLeastReps: 12, in: history), 0)
    }

    // MARK: - One-rep max: measured beats estimated

    /// A logged single is ground truth and outranks a larger estimate: 315 × 5
    /// estimates to 367.5, but this lifter has actually stood up with 405, and
    /// 405 is what they have.
    func testALoggedSingleIsTheOneRepMaxEvenWhenAnEstimateIsHigher() {
        let history: [SetPair] = [(405, 1), (315, 5)]
        let result = PersonalRecordMath.oneRepMax(from: history)
        assertPounds(result?.pounds, 405)
        XCTAssertEqual(result?.isMeasured, true)
    }

    /// Never lifted a single: estimate from the best work. 315 × 5 by Epley is
    /// 315 × (1 + 5/30) = 367.5.
    func testWithoutASingleTheOneRepMaxIsEstimated() {
        let history: [SetPair] = [(315, 5), (225, 10)]
        let result = PersonalRecordMath.oneRepMax(from: history)
        assertPounds(result?.pounds, 367.5)
        XCTAssertEqual(result?.isMeasured, false)
    }

    /// The estimate takes the BEST across their work, not the most recent:
    /// 225 × 10 is 300, which beats 250 × 3's 275.
    func testTheEstimateTakesTheStrongestPerformance() {
        let history: [SetPair] = [(250, 3), (225, 10)]
        assertPounds(PersonalRecordMath.oneRepMax(from: history)?.pounds, 300)
    }

    /// No history, no number — never a fabricated max.
    func testNoHistoryYieldsNoOneRepMax() {
        XCTAssertNil(PersonalRecordMath.oneRepMax(from: []))
    }
}
