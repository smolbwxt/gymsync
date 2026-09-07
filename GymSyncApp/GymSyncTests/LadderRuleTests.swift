import XCTest
@testable import GymSync

final class LadderRuleTests: XCTestCase {

    func testEveryMetricHasARule() {
        for metric in GoalMetric.allCases {
            let rungs = LadderRules.rule(for: metric).rungs(
                current: GoalTarget(), target: GoalTarget(days: 4), weeks: 6,
                constraints: LadderConstraints())
            XCTAssertEqual(rungs.count, 6, "\(metric.rawValue) must answer for six weeks")
        }
    }

    func testAZeroWeekBlockProducesNoRungsRatherThanCrashing() {
        let rungs = HoldLadderRule().rungs(current: GoalTarget(), target: GoalTarget(),
                                           weeks: 0, constraints: LadderConstraints())
        XCTAssertTrue(rungs.isEmpty)
    }
}
