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

    // MARK: - A7: the ramp rules (spec §3.4)
    //
    // Every one of these methods is `throws` because `let x = try XCTUnwrap(…)`
    // is a statement, not an autoclosure argument — the plan's snippets were
    // written without it and would not compile.

    func testDistanceRampsTenPercentWithEveryFourthWeekDown() throws {
        let rule = try XCTUnwrap(LadderRules.rampRule(for: .weeklyDistance) as? PercentRampLadderRule)
        let rungs = rule.rungs(current: GoalTarget(distance: 10),
                               target: GoalTarget(activity: "run", distance: 15),
                               weeks: 8, constraints: LadderConstraints())
        XCTAssertEqual(rungs.count, 8)
        XCTAssertEqual(try XCTUnwrap(rungs[0].distance), 11.0, accuracy: 0.05)
        XCTAssertLessThan(try XCTUnwrap(rungs[3].distance),
                          try XCTUnwrap(rungs[2].distance),
                          "every fourth week is a down week")
        XCTAssertGreaterThan(try XCTUnwrap(rungs[4].distance),
                             try XCTUnwrap(rungs[3].distance),
                             "the down week does not consume a step")
        XCTAssertEqual(try XCTUnwrap(rungs[7].distance), 15, accuracy: 0.001,
                       "the last rung IS the milestone")
        XCTAssertEqual(rungs[0].activity, "run", "the subject rides on every rung")
    }

    func testDaysStepOnceEveryTwoWeeksAndThenHold() throws {
        let rule = try XCTUnwrap(LadderRules.rampRule(for: .trainingDaysPerWeek))
        let rungs = rule.rungs(current: GoalTarget(days: 2), target: GoalTarget(days: 4),
                               weeks: 8, constraints: LadderConstraints())
        XCTAssertEqual(rungs.compactMap(\.days), [2, 3, 3, 4, 4, 4, 4, 4])
    }

    func testADeloadWeekNeverAdvances() throws {
        let rule = try XCTUnwrap(LadderRules.rampRule(for: .trainingDaysPerWeek))
        let rungs = rule.rungs(current: GoalTarget(days: 2), target: GoalTarget(days: 5),
                               weeks: 6,
                               constraints: LadderConstraints(deloadWeeks: [2]))
        XCTAssertEqual(rungs[2].days, rungs[1].days, "week 3 is a deload; it holds")
    }

    func testBodyWeightClampsIntoItsBandAndLandsOnTheTarget() throws {
        let rule = RateOfChangeLadderRule()
        // 190 -> 178 in 4 weeks is 1.6 %/wk implied: clamped to the 1 % ceiling,
        // so the ladder falls SHORT and says so by not reaching the target.
        let fast = rule.rungs(current: GoalTarget(bodyWeightLbs: 190),
                              target: GoalTarget(bodyWeightLbs: 178),
                              weeks: 4, constraints: LadderConstraints())
        XCTAssertEqual(fast.count, 4)
        XCTAssertGreaterThan(try XCTUnwrap(fast.last?.bodyWeightLbs), 178,
                             "a clamped ladder does not pretend to arrive")
        XCTAssertEqual(try XCTUnwrap(fast[0].bodyWeightRatePercent), -1.0, accuracy: 0.001)

        // 190 -> 183 in 8 weeks is 0.46 %/wk: inside the band, so the ladder
        // is exactly the athlete's own plan and lands on it.
        let steady = rule.rungs(current: GoalTarget(bodyWeightLbs: 190),
                                target: GoalTarget(bodyWeightLbs: 183),
                                weeks: 8, constraints: LadderConstraints())
        // Compared through the double rather than as a `Decimal` with an
        // `accuracy:`. Every accuracy assertion in this repo already goes
        // through `double(…)` (`UnitsAndWarmupTests:17`), and a body weight is
        // read as a number here, not as a stored quantity.
        let landed = NSDecimalNumber(decimal: try XCTUnwrap(steady.last?.bodyWeightLbs))
            .doubleValue
        XCTAssertEqual(landed, 183, accuracy: 0.6)

        let gaining = rule.rungs(current: GoalTarget(bodyWeightLbs: 160),
                                 target: GoalTarget(bodyWeightLbs: 175),
                                 weeks: 8, constraints: LadderConstraints())
        XCTAssertEqual(try XCTUnwrap(gaining[0].bodyWeightRatePercent), 0.5, accuracy: 0.001,
                       "gaining rides the 0.25-0.5 % band, not the loss band")
    }

    // MARK: - Cumulative volume (fix round 1, finding F1)
    //
    // `cumulativeVolume` is the ONE metric whose milestone is per-BLOCK rather
    // than per-week, so its rungs are TONNAGE-TO-DATE. These three pin that
    // shape: the climb arrives, a deload adds half a share, and re-deriving
    // mid-block spreads only what is left.

    /// The week's own share is the STEP between rungs, so a cumulative ladder
    /// is read by differencing it.
    private func weeklyShares(_ rungs: [GoalTarget]) -> [Double] {
        var previous = 0.0
        return rungs.compactMap(\.volumeLbs).map { total in
            defer { previous = total }
            return total - previous
        }
    }

    func testVolumeRungsAreCumulativeAndTheLastOneIsTheMilestone() throws {
        let rungs = CumulativeLadderRule().rungs(
            current: GoalTarget(volumeLbs: 0), target: GoalTarget(volumeLbs: 100_000),
            weeks: 8, constraints: LadderConstraints(deloadWeeks: [5]))
        XCTAssertEqual(rungs.count, 8)
        XCTAssertEqual(rungs.last?.volumeLbs, 100_000,
                       "the last rung IS the milestone, so standing can compare "
                       + "it against the milestone and get an honest answer")

        let climbs = rungs.compactMap(\.volumeLbs)
        XCTAssertEqual(climbs, climbs.sorted(),
                       "tonnage-to-date never goes down")

        let shares = weeklyShares(rungs)
        XCTAssertEqual(shares[5] * 2, shares[4], accuracy: 200,
                       "the deload week takes half a share of what remains")
    }

    /// The controller's own worked example: a 100,000 lb block sitting at
    /// 40,000 with five weeks to go asks for the 60,000 that is LEFT, not
    /// another 100,000.
    func testVolumeSpreadsOnlyWhatIsLeftOverTheWeeksThatRemain() throws {
        let rungs = CumulativeLadderRule().rungs(
            current: GoalTarget(volumeLbs: 40_000),
            target: GoalTarget(volumeLbs: 100_000),
            weeks: 5, constraints: LadderConstraints())
        XCTAssertEqual(rungs.count, 5)
        XCTAssertEqual(try XCTUnwrap(rungs[0].volumeLbs), 52_000, accuracy: 100,
                       "40,000 banked plus a fifth of the 60,000 that remains")
        XCTAssertEqual(rungs.last?.volumeLbs, 100_000)
        XCTAssertEqual(weeklyShares(rungs).dropFirst().reduce(0, +), 48_000,
                       accuracy: 400,
                       "the work already done is never asked for again")
    }

    func testAVolumeBlockAlreadyPastItsMilestoneAsksForNothingMore() throws {
        let rungs = CumulativeLadderRule().rungs(
            current: GoalTarget(volumeLbs: 120_000),
            target: GoalTarget(volumeLbs: 100_000),
            weeks: 4, constraints: LadderConstraints())
        XCTAssertEqual(rungs.compactMap(\.volumeLbs), [100_000, 100_000, 100_000, 100_000],
                       "done is clamped at the milestone, so the remainder is zero "
                       + "rather than negative")
    }

    func testBenchmarkTimeDescendsAndHoldsThroughADeload() {
        let rungs = DescendingLadderRule().rungs(
            current: GoalTarget(targetSeconds: 3_300),
            target: GoalTarget(routineID: UUID(), targetSeconds: 2_700),
            weeks: 6, constraints: LadderConstraints(deloadWeeks: [3]))
        XCTAssertEqual(rungs.count, 6)
        XCTAssertEqual(rungs[3].targetSeconds, rungs[2].targetSeconds)
        XCTAssertEqual(rungs.last?.targetSeconds, 2_700)
        XCTAssertNotNil(rungs[0].routineID, "the routine rides on every rung")
    }

    func testARuleWithNoMeasuredCurrentStateHoldsTheMilestone() throws {
        let rule = try XCTUnwrap(LadderRules.rampRule(for: .weeklyDistance))
        let rungs = rule.rungs(current: GoalTarget(), target: GoalTarget(distance: 15),
                               weeks: 4, constraints: LadderConstraints())
        XCTAssertEqual(rungs.compactMap(\.distance), [15, 15, 15, 15],
                       "no floor to climb from is a flat ladder, not a climb out of zero")
    }

    /// The three metrics the GENERATOR prescribes have no ramp, and that is the
    /// design rather than an omission: their rungs are read off `Program.weeks`
    /// (task A8). `rule(for:)` still answers for them — flat — so nothing that
    /// asks a metric for a ladder can get nil.
    func testTheThreeReadOutMetricsHaveNoRamp() {
        for metric in [GoalMetric.liftOneRepMax, .liftRepsAtLoad, .weeklyMuscleSets] {
            XCTAssertNil(LadderRules.rampRule(for: metric), metric.rawValue)
            XCTAssertTrue(LadderRules.rule(for: metric) is HoldLadderRule,
                          "\(metric.rawValue) falls through to the flat placeholder")
        }
    }
}
