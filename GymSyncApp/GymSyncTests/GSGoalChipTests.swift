import XCTest
@testable import GymSync

/// The chip's two rules, tested on the value the view draws rather than on
/// pixels: the fraction, and the override that exists for span kinds.
final class GSGoalChipTests: XCTestCase {

    func testTheFractionIsDoneOverTarget() {
        XCTAssertEqual(GSGoalChip(name: "CHEST", done: 6, target: 12).fraction, 0.5)
    }

    func testAnOvershootDrawsAFullMeterNotAnOverflowingOne() {
        XCTAssertEqual(GSGoalChip(name: "CHEST", done: 18, target: 12).fraction, 1.0)
    }

    func testAZeroTargetDrawsNothingRatherThanDividingByNothing() {
        XCTAssertEqual(GSGoalChip(name: "CHEST", done: 3, target: 0).fraction, 0)
    }

    /// The whole reason `fill` exists: a 205 → 225 lift on its first day.
    func testTheFillOverrideWinsOverThePrintedNumbers() {
        let chip = GSGoalChip(name: "BENCH PRESS", done: 205, target: 225, fill: 0.0)
        XCTAssertEqual(chip.fraction, 0.0,
                       "a lift rung must not draw 91% on the day the block opened")
    }

    func testTheOverrideIsClamped() {
        XCTAssertEqual(GSGoalChip(name: "X", done: 1, target: 2, fill: 4).fraction, 1.0)
        XCTAssertEqual(GSGoalChip(name: "X", done: 1, target: 2, fill: -1).fraction, 0.0)
    }
}
