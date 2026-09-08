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

    // MARK: - A12: the ladder page's model (spec §6)
    //
    // THE DATES COME FROM `StubBlockGoalRepository`'s constants, not from epoch
    // literals. The plan's snippets used `1_792_411_200`, which is 2026-10-**19**
    // — the very literal Task 0's re-review replaced for being unreadable and
    // wrong — so a test written around it would have asserted "by Oct 18"
    // against a date that says the 19th and blamed the formatter.

    private let pageCalendar = Calendar(identifier: .gregorian)
    /// 2026-09-10, inside the fixture ladder's third week.
    private let pageNow = Date(timeIntervalSince1970: 1_789_000_000)

    private func strengthGoal(target: GoalTarget, byDate: Date?,
                              preset: GoalPreset? = .strength,
                              source: WeeklyGoalSource = .user,
                              metric: GoalMetric = .liftOneRepMax,
                              id: UUID = UUID()) -> BlockGoal {
        BlockGoal(id: id, userID: UUID(), enrollmentID: UUID(), metric: metric,
                  target: target, byDate: byDate, preset: preset, source: source,
                  outcome: nil, outcomeValue: nil,
                  createdAt: Date(timeIntervalSince1970: 0),
                  updatedAt: Date(timeIntervalSince1970: 0))
    }

    func testAStrengthPageIsHeadlinedByTheMilestoneItself() {
        let bench = UUID()
        let goal = strengthGoal(
            target: GoalTarget(exerciseID: bench, targetWeightLbs: 225),
            byDate: StubBlockGoalRepository.fixtureByDate)
        let page = LadderMath.page(
            goal: goal, ladder: StubBlockGoalRepository.fixtureLadder,
            liftName: "Bench", rungSets: 3, notesByWeek: [:], unit: .lbs,
            now: pageNow, calendar: pageCalendar)

        XCTAssertEqual(page.headline, "Bench 225 by Oct 18")
        XCTAssertEqual(page.dateLine, "Sunday 18 October",
                       "the date line spells out the day the headline abbreviates")
        XCTAssertEqual(page.rows.count, 8)
        XCTAssertEqual(page.weekCount, 8)
        XCTAssertEqual(page.weekNumber, 3, "exactly one rung is current")
        XCTAssertEqual(page.source, .user)
        XCTAssertEqual(page.coachLine, "On track")
        XCTAssertTrue(page.reachesMilestone)
    }

    func testALadderThatFallsShortSaysSoAndNamesTheNumber() {
        var ladder = StubBlockGoalRepository.fixtureLadder
        ladder.rungs[7].target.targetWeightLbs = 218     // the spec's own example
        let goal = strengthGoal(target: GoalTarget(targetWeightLbs: 225),
                                byDate: StubBlockGoalRepository.fixtureByDate,
                                id: ladder.goalID)
        let page = LadderMath.page(
            goal: goal, ladder: ladder, liftName: "Bench", rungSets: 3,
            notesByWeek: [:], unit: .lbs, now: pageNow, calendar: pageCalendar)

        XCTAssertFalse(page.reachesMilestone)
        XCTAssertTrue(page.coachLine.contains("218"),
                      "the ladder never lies about the gap")
        XCTAssertTrue(page.coachLine.contains("move the date?"),
                      "Coach PROPOSES — nothing is written here")
    }

    func testAHeldForTheBlockGoalHasNoDateLine() {
        let goal = strengthGoal(
            target: GoalTarget(muscleTargets: ["chest": 12, "back": 14]),
            byDate: nil, preset: .maintenance, source: .coach,
            metric: .weeklyMuscleSets)
        let page = LadderMath.page(
            goal: goal, ladder: StubBlockGoalRepository.fixtureLadder,
            liftName: "", rungSets: 3, notesByWeek: [:], unit: .lbs,
            now: pageNow, calendar: pageCalendar)

        XCTAssertEqual(page.dateLine, "")
        XCTAssertEqual(page.coachLine, "Held for the block.")
        XCTAssertEqual(page.headline, "Hold the recommended volumes")
        XCTAssertTrue(page.reachesMilestone,
                      "a goal with no date cannot fall short of one")
    }

    func testADeloadRungCarriesItsFlagAndTheGeneratorsOwnNote() {
        var ladder = StubBlockGoalRepository.fixtureLadder
        ladder.rungs[5].status = .ahead
        let goal = strengthGoal(target: GoalTarget(targetWeightLbs: 225),
                                byDate: nil, source: .coach, id: ladder.goalID)
        let page = LadderMath.page(
            goal: goal, ladder: ladder, liftName: "Bench", rungSets: 2,
            notesByWeek: [5: "Deload — move fast, leave fresh."],
            deloadWeeks: [5], unit: .lbs, now: pageNow, calendar: pageCalendar)

        XCTAssertTrue(page.rows[5].isDeload)
        XCTAssertEqual(page.rows[5].note, "Deload — move fast, leave fresh.")
        XCTAssertNil(page.rows[5].implication,
                     "a deload's e1RM reads as a setback; the number is true and "
                     + "the sentence it forms is not")
        XCTAssertEqual(page.rows.filter(\.isDeload).count, 1)
        XCTAssertNotNil(page.rows[4].implication, "an ordinary rung still implies one")
    }

    /// Every metric words a rung, and none of them says "—" for a target that
    /// has its number. A metric added without a spelling would print an em dash
    /// on the ladder page and nobody would see it until a screenshot.
    func testEveryMetricWordsItsOwnRung() {
        let targets: [GoalMetric: GoalTarget] = [
            .liftOneRepMax: GoalTarget(targetWeightLbs: 200, targetReps: 5),
            .liftRepsAtLoad: GoalTarget(targetWeightLbs: 225, targetReps: 8),
            .weeklyMuscleSets: GoalTarget(muscleTargets: ["chest": 12]),
            .weeklyDistance: GoalTarget(activity: "run", distance: 12),
            .trainingDaysPerWeek: GoalTarget(days: 4),
            .sessionsOfTypePerWeek: GoalTarget(sessionType: "hiit", sessions: 3),
            .lissMinutesPerWeek: GoalTarget(lissMinutes: 150, stretchingExercises: 4),
            .stretchingExercisesPerWeek: GoalTarget(lissMinutes: 120,
                                                    stretchingExercises: 6),
            .bodyWeight: GoalTarget(bodyWeightLbs: 183, bodyWeightRatePercent: -0.75),
            .cumulativeVolume: GoalTarget(volumeLbs: 12_500),
            .benchmarkTime: GoalTarget(routineID: UUID(), targetSeconds: 2_800),
        ]
        XCTAssertEqual(targets.count, GoalMetric.allCases.count)

        for metric in GoalMetric.allCases {
            guard let target = targets[metric] else {
                return XCTFail("\(metric.rawValue) has no fixture")
            }
            let goal = strengthGoal(target: target, byDate: nil, preset: nil,
                                    source: .coach, metric: metric)
            let ladder = Ladder(
                goalID: goal.id,
                rungs: [.init(weekIndex: 0, weekStartString: "2026-09-06",
                              target: target, status: .current)],
                derivedAt: Date(timeIntervalSince1970: 0))
            let page = LadderMath.page(goal: goal, ladder: ladder, liftName: "Bench",
                                       rungSets: 3, notesByWeek: [:], unit: .lbs,
                                       now: pageNow, calendar: pageCalendar)
            XCTAssertEqual(page.rows.count, 1, metric.rawValue)
            XCTAssertNotEqual(page.rows.first?.targetText, "—",
                              "\(metric.rawValue) must word its own rung")
            XCTAssertFalse(page.headline.isEmpty, "\(metric.rawValue) headline")
        }
    }

    // MARK: - A13: blocks that predate goals (spec §5.4)

    /// `ProgramEnrollment` is `Decodable`-ONLY (`ProgramEnrollment.swift:26`),
    /// so the fixture goes through JSON — the way a row actually arrives. A
    /// hand-built value could not drift from the wire shape because it could
    /// not exist.
    private func enrollment(focus: ProgramFocus, baseline: [String: Double],
                            weeks: Int = 8) -> ProgramEnrollment {
        let focusJSON = String(data: try! JSONEncoder().encode(focus),
                               encoding: .utf8)!
        let baselineJSON = String(data: try! JSONEncoder().encode(baseline),
                                  encoding: .utf8)!
        let json = """
        {"id":"\(UUID().uuidString)","user_id":"\(UUID().uuidString)",
         "template_slug":"coach-fixture","focus":\(focusJSON),
         "baseline":\(baselineJSON),
         "started_on":"2026-08-23","weeks":\(weeks),
         "ended_at":null,"ended_reason":null,
         "created_at":"2026-08-23T12:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(ProgramEnrollment.self, from: Data(json.utf8))
    }

    /// 2026-08-25, inside the fixture block's first week.
    private let detectNow = Date(timeIntervalSince1970: 1_787_745_600)

    func testAFocusLiftWithABaselineDetectsAStrengthGoalFivePercentUp() {
        let bench = UUID()
        let draft = LadderMath.detectedGoal(
            enrollment: enrollment(focus: ProgramFocus(exerciseIDs: [bench]),
                                   baseline: [bench.uuidString.lowercased(): 200]),
            volumeTargets: [], effectiveWeeklyGoal: 3, unit: .lbs,
            now: detectNow, calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(draft.metric, .liftOneRepMax)
        XCTAssertEqual(draft.target.exerciseID, bench)
        XCTAssertEqual(draft.target.targetWeightLbs, 210,
                       "200 × 1.05, rounded on the 5 lb grid — the same step "
                       + "WeeklyGoalDetector.liftTarget takes, called not re-derived")
        XCTAssertEqual(draft.source, .coach)
        XCTAssertNil(draft.preset, "this goal was not chosen at a door")
        XCTAssertNotNil(draft.byDate, "the block's end is the milestone date")
    }

    func testAMuscleGroupFocusDetectsWeeklyMuscleSets() {
        let draft = LadderMath.detectedGoal(
            enrollment: enrollment(focus: ProgramFocus(muscleGroup: "chest"),
                                   baseline: [:]),
            volumeTargets: [VolumeTarget(muscle: "chest", weeklySets: 14, reason: nil)],
            effectiveWeeklyGoal: 3, unit: .lbs,
            now: detectNow, calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(draft.metric, .weeklyMuscleSets)
        XCTAssertEqual(draft.target.muscleTargets?["chest"], 14,
                       "the titration is read first when it has a row")
    }

    func testAMuscleFocusWithNoTitrationFallsBackToTheBlocksPrescription() {
        let draft = LadderMath.detectedGoal(
            enrollment: enrollment(focus: ProgramFocus(muscleGroup: "chest"),
                                   baseline: [:]),
            volumeTargets: [], effectiveWeeklyGoal: 3,
            prescribedMuscleSets: ["chest": 11], unit: .lbs,
            now: detectNow, calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(draft.metric, .weeklyMuscleSets)
        XCTAssertEqual(draft.target.muscleTargets?["chest"], 11,
                       "the block's own prescribed sets, when the search has said nothing")
    }

    func testAMuscleFocusWithNeitherNumberDoesNotInventOne() {
        let draft = LadderMath.detectedGoal(
            enrollment: enrollment(focus: ProgramFocus(muscleGroup: "chest"),
                                   baseline: [:]),
            volumeTargets: [], effectiveWeeklyGoal: 4, unit: .lbs,
            now: detectNow, calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(draft.metric, .trainingDaysPerWeek,
                       "no titration and no prescription means no number to name — "
                       + "the days floor, not a target invented here")
        XCTAssertEqual(draft.target.days, 4)
    }

    func testAnEnrollmentWithNeitherFallsToDaysAndNeverToNil() {
        let draft = LadderMath.detectedGoal(
            enrollment: enrollment(focus: ProgramFocus(), baseline: [:]),
            volumeTargets: [], effectiveWeeklyGoal: 5, unit: .lbs,
            now: detectNow, calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(draft.metric, .trainingDaysPerWeek)
        XCTAssertEqual(draft.target.days, 5,
                       "the same never-empty floor WeeklyGoalDetector's rule 3 is")
    }

    /// A focus lift with NO baseline is not a strength goal: there is nothing to
    /// add 5 % to, and inventing a milestone off a number that does not exist is
    /// the one thing the detector must never do.
    func testAFocusLiftWithNoBaselineFallsThrough() {
        let draft = LadderMath.detectedGoal(
            enrollment: enrollment(focus: ProgramFocus(exerciseIDs: [UUID()]),
                                   baseline: [:]),
            volumeTargets: [], effectiveWeeklyGoal: 3, unit: .lbs,
            now: detectNow, calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(draft.metric, .trainingDaysPerWeek)
    }

    /// The milestone date is the BLOCK'S END, and it is the same arithmetic
    /// `WeeklyGoalDetector.blockEnd` does — asserted against that function
    /// rather than against a literal, so the two cannot drift.
    func testTheDetectedMilestoneDateIsTheBlocksOwnEnd() throws {
        let calendar = Calendar(identifier: .gregorian)
        let block = enrollment(focus: ProgramFocus(), baseline: [:], weeks: 6)
        let draft = LadderMath.detectedGoal(
            enrollment: block, volumeTargets: [], effectiveWeeklyGoal: 3,
            unit: .lbs, now: detectNow, calendar: calendar)
        let expected = try XCTUnwrap(WeeklyGoalDetector.blockEnd(block, calendar: calendar))
        XCTAssertEqual(draft.byDate, expected)
    }
}
