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

    // MARK: - A10: the current rung becomes the week's goal (spec §4)

    private func blockGoal(_ metric: GoalMetric, target: GoalTarget) -> BlockGoal {
        BlockGoal(id: UUID(), userID: UUID(), enrollmentID: UUID(), metric: metric,
                  target: target, byDate: nil, preset: nil, source: .user,
                  outcome: nil, outcomeValue: nil,
                  createdAt: Date(timeIntervalSince1970: 0),
                  updatedAt: Date(timeIntervalSince1970: 0))
    }

    private func rung(_ target: GoalTarget) -> LadderRung {
        .init(weekIndex: 2, weekStartString: "2026-09-06", target: target, status: .current)
    }

    func testEveryPhaseOneMetricMaterialisesIntoARow() throws {
        let userID = UUID()
        let now = Date(timeIntervalSince1970: 1_788_696_000)
        let routineID = UUID(), exerciseID = UUID()

        let cases: [(GoalMetric, GoalTarget, WeeklyGoalKind)] = [
            (.liftOneRepMax, GoalTarget(exerciseID: exerciseID, targetWeightLbs: 200), .lift),
            (.liftRepsAtLoad, GoalTarget(exerciseID: exerciseID, targetReps: 8,
                                         loadLbs: 225), .lift),
            (.weeklyMuscleSets, GoalTarget(muscleTargets: ["chest": 12]), .muscleSets),
            (.weeklyDistance, GoalTarget(activity: "run", distance: 12), .distance),
            (.trainingDaysPerWeek, GoalTarget(days: 4), .days),
            (.sessionsOfTypePerWeek, GoalTarget(sessionType: "hiit", sessions: 3),
             .sessionsOfType),
            (.stretchingExercisesPerWeek, GoalTarget(lissMinutes: 120,
                                                     stretchingExercises: 6), .recovery),
            (.lissMinutesPerWeek, GoalTarget(lissMinutes: 150,
                                             stretchingExercises: 4), .recovery),
            (.bodyWeight, GoalTarget(bodyWeightLbs: 183), .bodyWeight),
            (.cumulativeVolume, GoalTarget(volumeLbs: 12_500), .volume),
            (.benchmarkTime, GoalTarget(routineID: routineID, targetSeconds: 2_800),
             .benchmark),
        ]

        XCTAssertEqual(cases.count, GoalMetric.allCases.count,
                       "every metric in the registry has a row shape, or the strip "
                       + "renders a kind nothing can read")

        for (metric, target, expected) in cases {
            let goal = blockGoal(metric, target: target)
            let row = try XCTUnwrap(LadderMath.weeklyGoal(from: rung(target), goal: goal,
                                                          userID: userID, now: now))
            XCTAssertEqual(row.kind, expected, "\(metric.rawValue)")
            XCTAssertEqual(row.source, .coach,
                           "materialisation is a Coach write — WeeklyGoalWriteRule governs it")
            XCTAssertEqual(row.params.goalID, goal.id, "the row knows its ladder")
            XCTAssertEqual(row.weekStartString, "2026-09-06")
        }
    }

    func testADaysRungWritesNoCountMirror() throws {
        let goal = blockGoal(.trainingDaysPerWeek, target: GoalTarget(days: 4))
        let row = try XCTUnwrap(LadderMath.weeklyGoal(
            from: rung(GoalTarget(days: 4)), goal: goal, userID: UUID(),
            now: Date(timeIntervalSince1970: 0)))
        XCTAssertNil(row.params.count,
                     "profiles.weekly_session_goal is the single source of truth for days")
    }

    func testRecoveryCarriesBothNumbersOnOneRow() throws {
        let target = GoalTarget(lissMinutes: 120, stretchingExercises: 6)
        let goal = blockGoal(.stretchingExercisesPerWeek, target: target)
        let row = try XCTUnwrap(LadderMath.weeklyGoal(from: rung(target), goal: goal,
                                                      userID: UUID(),
                                                      now: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(row.params.count, 6)
        XCTAssertEqual(row.params.lissMinutes, 120)
    }

    func testMuscleRungsRecordTheirProvenanceAsTheBlock() throws {
        let target = GoalTarget(muscleTargets: ["chest": 12])
        let goal = blockGoal(.weeklyMuscleSets, target: target)
        let row = try XCTUnwrap(LadderMath.weeklyGoal(from: rung(target), goal: goal,
                                                      userID: UUID(),
                                                      now: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(row.params.targetSource, "block")
    }

    /// A rep-strength rung's LOAD is fixed and its REPS are the rung, so the
    /// row must carry the load in `targetWeightLbs` and the rung in
    /// `targetReps` — the pair the strip branches on to tell the two lift
    /// readings apart.
    func testARepStrengthRungCarriesTheLoadAndTheRepTarget() throws {
        let exerciseID = UUID()
        let target = GoalTarget(exerciseID: exerciseID, targetReps: 8, loadLbs: 225)
        let goal = blockGoal(.liftRepsAtLoad, target: target)
        let row = try XCTUnwrap(LadderMath.weeklyGoal(from: rung(target), goal: goal,
                                                      userID: UUID(),
                                                      now: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(row.params.targetWeightLbs, 225, "the fixed load")
        XCTAssertEqual(row.params.targetReps, 8, "the rung")
        XCTAssertEqual(row.params.exerciseID, exerciseID)
    }

    func testTheRungForAWeekTheBlockDoesNotCoverIsNil() {
        let eight = ladder([.met, .current, .ahead])
        XCTAssertNotNil(LadderMath.rung(in: eight, weekStart: "2026-09-13"))
        XCTAssertNil(LadderMath.rung(in: eight, weekStart: "2027-01-03"))
    }
}
