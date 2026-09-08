import XCTest
@testable import GymSync

/// NO BLOCK WITHOUT A GOAL (task B4, spec §5.4).
///
/// `ProgramBuilder.build` is `@MainActor` and does eleven network reads, so it
/// is deliberately NOT unit-tested end to end. What is tested is the pure seam
/// the goal enters through: the block length off the milestone date, the week
/// keys the ladder's rungs sit on, and the repository surface step 7b calls.
final class ProgramBuilderGoalTests: XCTestCase {

    /// Records what it was asked to write, and writes nothing.
    ///
    /// It also PROVES the protocol's shape: an actor that implements only the
    /// six original methods still conforms, because `saveDerivedLadder` — the
    /// requirement B4 adds for A11 to override — ships with a default.
    private actor Recorder: BlockGoalRepository {
        var saved: [BlockGoal] = []
        var ladders: [UUID] = []
        var materialised: [UUID] = []
        func activeGoal() async -> BlockGoal? { nil }
        func ladder(goalID: UUID) async -> Ladder? { nil }
        func page(goalID: UUID) async -> LadderPageModel? { nil }
        func save(_ goal: BlockGoal) async -> Bool { saved.append(goal); return true }
        func reLadder(goalID: UUID) async -> Ladder? { nil }
        func materialiseRung(goalID: UUID, weekStart: String) async -> WeeklyGoal? {
            materialised.append(goalID); return nil
        }
    }

    func testTheDurationComesFromTheMilestoneDate() {
        let now = Date(timeIntervalSince1970: 1_788_696_000)
        let byDate = now.addingTimeInterval(56 * 86_400)
        XCTAssertEqual(GoalBlockLength.weeks(byDate: byDate, from: now), 8)
        XCTAssertEqual(GoalBlockLength.weeks(byDate: nil, from: now), 8)
    }

    func testTheLadderWalksOneWeekPerRungFromTheBlockStart() {
        let start = Date(timeIntervalSince1970: 1_788_696_000)   // a Sunday-week start
        let weeks = LadderMath.weekStartStrings(from: start, count: 8)
        XCTAssertEqual(weeks.count, 8)
        XCTAssertEqual(Set(weeks).count, 8, "no two rungs describe the same week")
        XCTAssertEqual(weeks.first, WeekMath.weekStartString(start))
    }

    func testAZeroWeekBlockAsksForNoRungsRatherThanCrashing() {
        let start = Date(timeIntervalSince1970: 1_788_696_000)
        XCTAssertTrue(LadderMath.weekStartStrings(from: start, count: 0).isEmpty)
        XCTAssertTrue(LadderMath.weekStartStrings(from: start, count: -3).isEmpty)
    }

    func testStep7bWritesTheGoalThenItsLadderThenThisWeeksRung() async {
        let recorder = Recorder()
        let draft = BlockGoalDraft(metric: .liftOneRepMax,
                                   target: GoalTarget(exerciseID: UUID(),
                                                      targetWeightLbs: 225),
                                   byDate: nil, preset: .strength)
        let goal = BlockGoal(draft: draft, userID: UUID(), enrollmentID: UUID())

        let didSave = await recorder.save(goal)
        XCTAssertTrue(didSave)
        let ladder = await recorder.saveDerivedLadder(
            goal: goal,
            program: ProgramGenerator.Program(days: [], weeks: [], notes: []),
            catalog: [], startedOn: Date(timeIntervalSince1970: 1_788_696_000),
            unit: .lbs)
        XCTAssertNil(ladder,
                     "the protocol's default derives nothing — A11's live type overrides it")
        let rung = await recorder.materialiseRung(goalID: goal.id,
                                                  weekStart: "2099-01-04")
        XCTAssertNil(rung)

        let savedGoals = await recorder.saved
        XCTAssertEqual(savedGoals.count, 1)
        XCTAssertEqual(savedGoals.first?.enrollmentID, goal.enrollmentID,
                       "the goal hangs on the block it drives")
        let materialised = await recorder.materialised
        XCTAssertEqual(materialised, [goal.id])
    }

    private func exercise(_ id: UUID, _ name: String) -> Exercise {
        Exercise(id: id, name: name, slug: name.lowercased(),
                 category: "compound", primaryMuscle: "chest",
                 secondaryMuscles: [], equipment: "barbell",
                 defaultUnit: "lbs", demoVideoURL: nil)
    }

    /// THE BLOCK IS RECORDED AS WHAT IT WAS BUILT AS (review finding 1).
    ///
    /// The template name, the summary, the `focus_kind` column and the frozen
    /// config all used to read `profile.generatorFocus`. The goal moves the
    /// band for eight of the eleven presets, so a hypertrophy-profile athlete
    /// chasing a bench milestone would have got a STRENGTH block filed as a
    /// HYPERTROPHY one — on the pages whose whole job is to say what was built.
    func testAStrengthGoalOnAHypertrophyAthleteRecordsAStrengthBlock() {
        let bench = UUID()
        var profile = TrainingProfile()
        profile.rankedGoals = [.hypertrophy]
        XCTAssertEqual(profile.generatorFocus, .hypertrophy,
                       "the athlete's stored profile says hypertrophy")

        let inputs = profile.generatorInputs(
            durationWeeks: 8,
            goal: BlockGoalDraft(metric: .liftOneRepMax,
                                 target: GoalTarget(exerciseID: bench,
                                                    targetWeightLbs: 225),
                                 byDate: nil, preset: .strength))
        XCTAssertEqual(inputs.focus, .strength, "and the goal moved the band")

        let identity = ProgramBuilder.recordedIdentity(
            focus: inputs.focus, days: profile.daysPerWeek, duration: 8)
        XCTAssertEqual(identity.name, "Coach · Strength · 3-day")
        XCTAssertEqual(identity.summary,
                       "Generated 8-week strength block — 3 lifting days a week.")
        XCTAssertEqual(identity.focusKind, "strength",
                       "program_templates.focus_kind must not say hypertrophy")

        let config = ProgramBuilder.configSnapshot(
            profile: profile, inputs: inputs, duration: 8,
            standingRules: [], catalog: [exercise(bench, "Bench Press")])
        XCTAssertEqual(config["goal"], "Strength",
                       "the frozen snapshot the ledger renders verbatim")
        XCTAssertEqual(config["focus lifts"], "Bench Press",
                       "the goal's own lift reaches the provenance drawer")

        // The bug, spelled out: the profile's focus records a different block.
        XCTAssertNotEqual(
            identity,
            ProgramBuilder.recordedIdentity(focus: profile.generatorFocus,
                                            days: profile.daysPerWeek, duration: 8))
    }

    func testAGoalLessBuildStillRecordsExactlyWhatItAlwaysDid() {
        var profile = TrainingProfile()
        profile.rankedGoals = [.hypertrophy]
        let inputs = profile.generatorInputs(durationWeeks: 8)
        let identity = ProgramBuilder.recordedIdentity(
            focus: inputs.focus, days: profile.daysPerWeek, duration: 8)
        XCTAssertEqual(identity.name, "Coach · Hypertrophy · 3-day")
        XCTAssertEqual(identity.focusKind, "hypertrophy")
        XCTAssertEqual(
            identity,
            ProgramBuilder.recordedIdentity(focus: profile.generatorFocus,
                                            days: profile.daysPerWeek, duration: 8),
            "with no goal the two readings agree, which is why this went unseen")
    }

    func testWeightLossKeepsTheColumnsOwnSpelling() {
        let identity = ProgramBuilder.recordedIdentity(focus: .weightLoss, days: 4, duration: 6)
        XCTAssertEqual(identity.focusKind, "weight_loss")
        XCTAssertEqual(identity.name, "Coach · Weight Loss · 4-day")
    }

    func testTheInterimDetectedGoalMovesNothingTheGeneratorReads() {
        // Until Stream C hands the door's own milestone to `build`, both call
        // sites pass `LadderMath.detectedGoal`. It must not quietly rebuild
        // every athlete's block: consistency overrides no band and places no
        // cardio, which is exactly why it is the placeholder.
        var profile = TrainingProfile()
        profile.daysPerWeek = 4
        let goal = LadderMath.detectedGoal(profile: profile)
        XCTAssertEqual(goal.preset, .consistency)
        XCTAssertEqual(goal.target.days, 4)
        XCTAssertNil(goal.byDate)
        XCTAssertEqual(goal.source, .coach)
        XCTAssertNil(GoalGeneratorMapping.focus(for: goal))

        let withGoal = profile.generatorInputs(durationWeeks: 8, goal: goal)
        let without = profile.generatorInputs(durationWeeks: 8)
        XCTAssertEqual(withGoal.focus, without.focus)
        XCTAssertEqual(withGoal.focusMuscles, without.focusMuscles)
        XCTAssertEqual(withGoal.focusExerciseIDs, without.focusExerciseIDs)
        XCTAssertEqual(withGoal.cardioDays, without.cardioDays)
        XCTAssertEqual(withGoal.cardioMinutes, without.cardioMinutes)
        XCTAssertEqual(withGoal.fillWeekWithRecovery, without.fillWeekWithRecovery)
    }
}
