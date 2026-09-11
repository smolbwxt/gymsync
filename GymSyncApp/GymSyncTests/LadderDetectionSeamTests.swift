import XCTest
@testable import GymSync

// MARK: - LadderDetectionSeamTests
//
// PLAN ITEM 6, THE CONTROLLER'S RULING (2026-09-07), and the final review's
// finding F1 — which is that the ruling was implemented and never called:
//
//   > "when `detectIfMissing` runs for a user with an active `BlockGoal`, it
//   > calls `reLadder` from actuals and then `materialiseRung` for the current
//   > week, and returns that row — so a new week re-ladders itself on its first
//   > Home load"
//
// THE WORLD THESE TESTS DESCRIBE IS WEEK 2 OF AN EIGHT-WEEK BLOCK: a
// `weekly_goals` row for last week only, an active goal, a ladder whose rungs
// still stand, and a changed actual. That is the world the ruling names and the
// one no test held before this file, which is why F1 survived four stream
// reviews and two green CI runs.
//
// The two halves are tested where each one lives:
//   * the ORDER — the ladder is asked before detection, and detection never
//     runs when the ladder answers — through `LiveWeeklyGoalRepository
//     .weekInEffect`, the seam lifted out of `detectIfMissing` so it has no
//     Supabase in it;
//   * the LADDER'S OWN ANSWER — `LadderMath.reLaddered`, which decides which
//     door a metric re-ladders through.
final class LadderDetectionSeamTests: XCTestCase {

    // MARK: - Fixtures: week 2 of an eight-week bench block

    private let userID = UUID()
    private let goalID = UUID()
    private let exerciseID = UUID()

    /// Sunday-keyed week starts, the shape `WeekMath` writes.
    private let weekKeys = ["2026-08-23", "2026-08-30", "2026-09-06", "2026-09-13",
                            "2026-09-20", "2026-09-27", "2026-10-04", "2026-10-11"]
    private var lastWeek: String { weekKeys[0] }
    private var thisWeek: String { weekKeys[1] }

    private func benchGoal(metric: GoalMetric = .liftOneRepMax) -> BlockGoal {
        BlockGoal(id: goalID, userID: userID, enrollmentID: UUID(),
                  metric: metric,
                  target: GoalTarget(exerciseID: exerciseID, targetWeightLbs: 225),
                  byDate: nil, preset: .strength, source: .user,
                  outcome: nil, outcomeValue: nil,
                  createdAt: Date(timeIntervalSince1970: 0),
                  updatedAt: Date(timeIntervalSince1970: 0))
    }

    /// The row the ladder materialises for week 2 — `source = coach`, carrying
    /// the `goalID` that is the whole difference between a rung and an ordinary
    /// weekly goal (spec §4).
    private func materialisedRung(pounds: Decimal) -> WeeklyGoal {
        WeeklyGoal(userID: userID, weekStartString: thisWeek, kind: .lift,
                   params: WeeklyGoalParams(exerciseID: exerciseID,
                                            targetWeightLbs: pounds,
                                            goalID: goalID),
                   source: .coach, setAt: Date(timeIntervalSince1970: 0))
    }

    /// What plain detection would have written instead: a goal with NO
    /// `goalID`, which is a standalone weekly goal by spec §4 — the strip loses
    /// its block kicker and its tap opens the editor rather than the ladder.
    private func detectedGoal() -> WeeklyGoal {
        WeeklyGoal(userID: userID, weekStartString: thisWeek, kind: .muscleSets,
                   params: WeeklyGoalParams(muscleTargets: ["chest": 12]),
                   source: .coach, setAt: Date(timeIntervalSince1970: 0))
    }

    /// Counts a closure ran, without a captured `var` — a `let` box mutates
    /// cleanly from an async closure in every concurrency mode.
    private final class Calls {
        var ladder = 0
        var detect = 0
    }

    // MARK: - The order: the ladder answers, detection does not run

    /// THE RULING'S OWN TEST. Week 2, no row for it, an active goal whose rung
    /// has moved — the week is the ladder's rung, and plain detection is never
    /// reached.
    func testTheLaddersRungIsTheWeekAndPlainDetectionNeverRuns() async {
        let calls = Calls()
        let rung = materialisedRung(pounds: 205)

        let answer = await LiveWeeklyGoalRepository.weekInEffect(
            existing: nil,
            weekStart: thisWeek,
            currentWeekStart: thisWeek,
            ladder: { calls.ladder += 1; return rung },
            detect: { calls.detect += 1; return self.detectedGoal() })

        XCTAssertEqual(answer, rung, "week 2's row is the ladder's rung")
        XCTAssertEqual(answer?.source, .coach)
        XCTAssertEqual(answer?.params.goalID, goalID,
                       "the goalID is what makes the strip say WEEK 2 OF 8 and its tap open the ladder")
        XCTAssertEqual(calls.ladder, 1)
        XCTAssertEqual(calls.detect, 0,
                       "detection would have written a row with no goalID over the top of the rung")
    }

    /// The rung the ladder hands back is THIS week's, not last week's
    /// projection — the "changed actual" half of the ruling. Last week was
    /// prescribed 195; the re-ladder moved week 2 to 205.
    func testTheRungHandedBackIsThisWeeksAndNotLastWeeksProjection() async {
        let lastWeeksRow = WeeklyGoal(userID: userID, weekStartString: lastWeek,
                                      kind: .lift,
                                      params: WeeklyGoalParams(exerciseID: exerciseID,
                                                               targetWeightLbs: 195,
                                                               goalID: goalID),
                                      source: .coach,
                                      setAt: Date(timeIntervalSince1970: 0))
        let answer = await LiveWeeklyGoalRepository.weekInEffect(
            existing: nil, weekStart: thisWeek, currentWeekStart: thisWeek,
            ladder: { self.materialisedRung(pounds: 205) },
            detect: { nil })

        XCTAssertEqual(answer?.weekStartString, thisWeek)
        XCTAssertNotEqual(answer?.params.targetWeightLbs,
                          lastWeeksRow.params.targetWeightLbs,
                          "a new week re-ladders itself rather than repeating the last one")
    }

    /// An athlete with no block — every account until they build one — takes
    /// the path that shipped before this seam existed, untouched.
    func testWithNoBlockTheWeekFallsThroughToPlainDetection() async {
        let calls = Calls()
        let detected = detectedGoal()

        let answer = await LiveWeeklyGoalRepository.weekInEffect(
            existing: nil, weekStart: thisWeek, currentWeekStart: thisWeek,
            ladder: { calls.ladder += 1; return nil },
            detect: { calls.detect += 1; return detected })

        XCTAssertEqual(answer, detected)
        XCTAssertEqual(calls.ladder, 1)
        XCTAssertEqual(calls.detect, 1)
    }

    /// `shouldDetectOnRead` still gates BOTH paths: a week that already has a
    /// row is neither laddered nor detected from a read.
    func testAWeekThatAlreadyHasARowIsNeitherLadderedNorDetected() async {
        let calls = Calls()
        let mine = WeeklyGoal(userID: userID, weekStartString: thisWeek,
                              kind: .days, params: WeeklyGoalParams(),
                              source: .user, setAt: Date(timeIntervalSince1970: 0))

        let answer = await LiveWeeklyGoalRepository.weekInEffect(
            existing: mine, weekStart: thisWeek, currentWeekStart: thisWeek,
            ladder: { calls.ladder += 1; return self.materialisedRung(pounds: 205) },
            detect: { calls.detect += 1; return self.detectedGoal() })

        XCTAssertEqual(answer, mine, "the athlete has spoken for this week")
        XCTAssertEqual(calls.ladder, 0)
        XCTAssertEqual(calls.detect, 0)
    }

    /// Reading a past week is not a reason to write one — the half of
    /// `shouldDetectOnRead` that is easy to lose when a branch is added above it.
    func testAPastWeekIsNeverWrittenFromARead() async {
        let calls = Calls()

        let answer = await LiveWeeklyGoalRepository.weekInEffect(
            existing: nil, weekStart: lastWeek, currentWeekStart: thisWeek,
            ladder: { calls.ladder += 1; return self.materialisedRung(pounds: 205) },
            detect: { calls.detect += 1; return self.detectedGoal() })

        XCTAssertNil(answer)
        XCTAssertEqual(calls.ladder, 0)
        XCTAssertEqual(calls.detect, 0)
    }

    /// THE WIRING ITSELF (F1's actual defect: correct logic, no call site).
    /// The live weekly repository's ladder source is the live block repository,
    /// by default, with nothing to inject at the call site in `HomeView`.
    func testTheLiveRepositoryAsksTheLiveBlockRepository() {
        XCTAssertTrue(LiveWeeklyGoalRepository().ladderSource is LiveBlockGoalRepository)
    }

    // MARK: - The ladder's own answer: which door a metric re-ladders through

    private func ladder(pounds: [Decimal], statuses: [RungStatus]) -> Ladder {
        Ladder(goalID: goalID,
               rungs: zip(pounds, statuses).enumerated().map { index, pair in
                   LadderRung(weekIndex: index, weekStartString: weekKeys[index],
                              target: GoalTarget(exerciseID: exerciseID,
                                                 targetWeightLbs: pair.0),
                              status: pair.1)
               },
               derivedAt: Date(timeIntervalSince1970: 0))
    }

    private var march: ProgramTemplate? {
        ProgramTemplate.all.first { $0.slug == "march-to-1rm" }
    }

    /// **THE REGRESSION PLAN ITEM 6 WOULD HAVE SHIPPED.**
    ///
    /// `LadderRules.rule(for: .liftOneRepMax)` is `HoldLadderRule` — the three
    /// metrics the generator prescribes have no ramp — and a hold answers
    /// "the milestone, every week". Re-laddering a bench block through it
    /// replaced weeks 3-8 with 225 apiece. Once F1 puts a re-ladder on the
    /// first Home load of every week, that stops being a button nobody pressed.
    func testAStrengthReLadderReReadsTheBlockAndNeverFlattensOntoTheMilestone() {
        let existing = ladder(pounds: [190, 195, 200, 205, 210, 175, 220, 225],
                              statuses: [.met, .current, .ahead, .ahead,
                                         .ahead, .ahead, .ahead, .ahead])
        // The athlete's best measured e1RM has moved to 215 — the "changed
        // actual" the ruling's test names.
        let measured = [lastWeek: GoalTarget(targetWeightLbs: 205),
                        thisWeek: GoalTarget(targetWeightLbs: 215)]

        let fresh = LadderMath.reLaddered(goal: benchGoal(), existing: existing,
                                          template: march, measured: measured,
                                          unit: .lbs, now: Date())

        let targets = fresh.rungs.map(\.target.targetWeightLbs)
        XCTAssertFalse(targets.dropFirst().allSatisfy { $0 == Decimal(225) },
                       "a hold rule would have written the milestone into every remaining week")
        // march-to-1rm's week 2 is 80 % of the baseline, snapped to the grid the
        // athlete's own plates are marked in. Stated as the block's arithmetic
        // rather than as a literal copied out of it: the rung moved, and it
        // moved to what the BLOCK prescribes at the new baseline.
        let week2 = LadderReadout.snapped(215 * Decimal(80) / 100, unit: .lbs)
        XCTAssertEqual(targets[1], week2,
                       "week 2 is re-read from the block at the new baseline")
        XCTAssertNotEqual(targets[1], Decimal(195), "the rung moved")
    }

    /// Re-laddering moves TARGETS in the window `reLadder` owns and nothing
    /// else: a week already met is the record of the climb.
    func testAReLadderLeavesAMetWeekExactlyWhereItWas() {
        let existing = ladder(pounds: [190, 195, 200, 205, 210, 175, 220, 225],
                              statuses: [.met, .current, .ahead, .ahead,
                                         .ahead, .ahead, .ahead, .ahead])
        let fresh = LadderMath.reLaddered(
            goal: benchGoal(), existing: existing, template: march,
            measured: [thisWeek: GoalTarget(targetWeightLbs: 215)],
            unit: .lbs, now: Date())

        XCTAssertEqual(fresh.rungs[0].target.targetWeightLbs, Decimal(190))
        XCTAssertEqual(fresh.rungs[0].status, .met)
    }

    /// With nothing measured there is no new baseline, and the ladder the block
    /// derived is left exactly as it is — never rebuilt out of thin air.
    func testNothingMeasuredLeavesTheBlocksOwnLadderAlone() {
        let existing = ladder(pounds: [190, 195, 200, 205, 210, 175, 220, 225],
                              statuses: [.met, .current, .ahead, .ahead,
                                         .ahead, .ahead, .ahead, .ahead])
        let fresh = LadderMath.reLaddered(goal: benchGoal(), existing: existing,
                                          template: march, measured: [:],
                                          unit: .lbs, now: Date())
        XCTAssertEqual(fresh.rungs, existing.rungs)
    }

    /// `weeklyMuscleSets` rungs are read off the generated PROGRAM, which no
    /// caller of this holds — so they keep what the block prescribed rather
    /// than collapsing onto the milestone.
    func testAMuscleSetsLadderKeepsWhatTheBlockPrescribed() {
        let goal = BlockGoal(id: goalID, userID: userID, enrollmentID: UUID(),
                             metric: .weeklyMuscleSets,
                             target: GoalTarget(muscleTargets: ["chest": 16]),
                             byDate: nil, preset: .muscle, source: .user,
                             outcome: nil, outcomeValue: nil,
                             createdAt: Date(timeIntervalSince1970: 0),
                             updatedAt: Date(timeIntervalSince1970: 0))
        let existing = Ladder(
            goalID: goalID,
            rungs: (0..<3).map {
                LadderRung(weekIndex: $0, weekStartString: weekKeys[$0],
                           target: GoalTarget(muscleTargets: ["chest": 10 + $0]),
                           status: $0 == 0 ? .met : .ahead)
            },
            derivedAt: Date(timeIntervalSince1970: 0))

        let fresh = LadderMath.reLaddered(goal: goal, existing: existing,
                                          template: march, measured: [:],
                                          unit: .lbs, now: Date())
        XCTAssertEqual(fresh.rungs, existing.rungs)
    }

    /// The eight metrics that DO ramp still ramp — this change narrows the door
    /// for three metrics and leaves the rest on `LadderMath.reLadder`.
    func testARampedLadderStillGoesThroughTheRamp() {
        let goal = BlockGoal(id: goalID, userID: userID, enrollmentID: UUID(),
                             metric: .trainingDaysPerWeek,
                             target: GoalTarget(days: 5),
                             byDate: nil, preset: .consistency, source: .user,
                             outcome: nil, outcomeValue: nil,
                             createdAt: Date(timeIntervalSince1970: 0),
                             updatedAt: Date(timeIntervalSince1970: 0))
        let existing = Ladder(
            goalID: goalID,
            rungs: (0..<4).map {
                LadderRung(weekIndex: $0, weekStartString: weekKeys[$0],
                           target: GoalTarget(days: 3), status: .ahead)
            },
            derivedAt: Date(timeIntervalSince1970: 0))

        let fresh = LadderMath.reLaddered(
            goal: goal, existing: existing, template: nil,
            measured: [weekKeys[0]: GoalTarget(days: 3)],
            unit: .lbs, now: Date())

        XCTAssertEqual(fresh.rungs.last?.target.days, 5,
                       "a step-every-two-weeks ramp still arrives at the milestone")
    }
}
