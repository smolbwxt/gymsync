import XCTest
@testable import GymSync

/// Pure-function coverage for `SetProgression` — the within-session
/// next-set prefill rule.
final class SetProgressionTests: XCTestCase {

    func testEasySetStepsUp() {
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 355, rpe: 7, isFailed: false), 360)
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 225, rpe: 6, isFailed: false), 230)
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

    func testCustomStep() {
        XCTAssertEqual(SetProgression.nextWeight(afterPounds: 100, rpe: 7, isFailed: false, stepPounds: Decimal(2.5)),
                       Decimal(102.5))
    }
}
