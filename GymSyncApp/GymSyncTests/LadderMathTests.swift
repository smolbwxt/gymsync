import XCTest
@testable import GymSync

final class LadderMathTests: XCTestCase {

    private func ladder(_ statuses: [RungStatus]) -> Ladder {
        Ladder(goalID: UUID(),
               rungs: statuses.enumerated().map { index, status in
                   .init(weekIndex: index,
                         weekStartString: String(format: "2026-09-%02d", 6 + index * 7),
                         target: GoalTarget(days: 3), status: status)
               },
               derivedAt: Date(timeIntervalSince1970: 0))
    }

    func testLowerIsBetterForABenchmarkAndHigherForEverythingElse() {
        XCTAssertTrue(LadderMath.reached(metric: .benchmarkTime,
                                         measured: GoalTarget(targetSeconds: 2_650),
                                         target: GoalTarget(targetSeconds: 2_700)))
        XCTAssertFalse(LadderMath.reached(metric: .benchmarkTime,
                                          measured: GoalTarget(targetSeconds: 2_750),
                                          target: GoalTarget(targetSeconds: 2_700)))
        XCTAssertTrue(LadderMath.reached(metric: .liftOneRepMax,
                                         measured: GoalTarget(targetWeightLbs: 230),
                                         target: GoalTarget(targetWeightLbs: 225)))
    }

    func testACutIsMetByGoingUnderAndAGainByGoingOver() {
        let cut = GoalTarget(bodyWeightLbs: 178, bodyWeightRatePercent: -0.75)
        XCTAssertTrue(LadderMath.reached(metric: .bodyWeight,
                                         measured: GoalTarget(bodyWeightLbs: 177), target: cut))
        XCTAssertFalse(LadderMath.reached(metric: .bodyWeight,
                                          measured: GoalTarget(bodyWeightLbs: 180), target: cut))
        let gain = GoalTarget(bodyWeightLbs: 175, bodyWeightRatePercent: 0.4)
        XCTAssertTrue(LadderMath.reached(metric: .bodyWeight,
                                         measured: GoalTarget(bodyWeightLbs: 176), target: gain))
    }

    func testAPastWeekWithNoReadingIsMissedAndTheCurrentOneIsCurrent() {
        let marked = LadderMath.statuses(
            rungs: ladder([.ahead, .ahead, .ahead]).rungs,
            metric: .trainingDaysPerWeek,
            measuredByWeek: ["2026-09-06": GoalTarget(days: 3)],
            currentWeekStart: "2026-09-13")
        XCTAssertEqual(marked.map(\.status), [.met, .current, .ahead])
    }

    func testAnOverriddenWeekStaysOverriddenEvenWhenItWasMet() {
        let marked = LadderMath.statuses(
            rungs: ladder([.ahead, .ahead]).rungs,
            metric: .trainingDaysPerWeek,
            measuredByWeek: ["2026-09-06": GoalTarget(days: 9)],
            currentWeekStart: "2026-09-13",
            overriddenWeeks: ["2026-09-06"])
        XCTAssertEqual(marked[0].status, .overridden,
                       "the athlete's own edit is the record of that week")
    }

    func testReLadderRewritesOnlyAheadAndCurrentRungs() {
        let existing = ladder([.met, .missed, .overridden, .current, .ahead, .ahead])
        let out = LadderMath.reLadder(
            existing: existing, metric: .trainingDaysPerWeek,
            current: GoalTarget(days: 2), milestone: GoalTarget(days: 5),
            constraints: LadderConstraints(),
            rule: StepEveryNWeeksLadderRule(step: 1, everyWeeks: 1,
                                            read: { $0.days }, write: { $0.days = $1 }),
            derivedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(out.rungs[0].target.days, 3, "a met week is history, untouched")
        XCTAssertEqual(out.rungs[1].target.days, 3, "a missed week stays visible")
        XCTAssertEqual(out.rungs[2].target.days, 3, "an override is the athlete's")
        XCTAssertEqual(out.rungs[3].target.days, 3, "current is re-derived: 2 + 1")
        XCTAssertEqual(out.rungs[4].target.days, 4)
        XCTAssertEqual(out.rungs[5].target.days, 5)
        XCTAssertEqual(out.rungs.map(\.status), existing.rungs.map(\.status),
                       "re-laddering moves TARGETS, never statuses")
        XCTAssertEqual(out.derivedAt, Date(timeIntervalSince1970: 100))
    }

    func testAFullyClosedLadderIsReturnedUnchanged() {
        let closed = ladder([.met, .missed, .overridden])
        let out = LadderMath.reLadder(
            existing: closed, metric: .trainingDaysPerWeek,
            current: GoalTarget(days: 2), milestone: GoalTarget(days: 5),
            constraints: LadderConstraints(), rule: HoldLadderRule(),
            derivedAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(out, closed, "nothing left to move")
    }
}
