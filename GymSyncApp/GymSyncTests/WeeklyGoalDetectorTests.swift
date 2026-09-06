import XCTest
@testable import GymSync

/// `WeeklyGoalDetector` — the design's three detection rules, one test per
/// branch. Plan: Stream A task A10.
///
/// The law under all of it: detection NEVER returns nil. Rule 3 answers when
/// nothing else does, so an athlete has a goal on Home from their first week.
final class WeeklyGoalDetectorTests: XCTestCase {

    // MARK: - Fixtures

    private let userID = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!
    private let weekStart = "2026-09-06"
    private let now = Date(timeIntervalSince1970: 1_788_696_000)

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private func exercise(_ n: Int, _ name: String, _ primary: String,
                          secondaries: [String] = [],
                          category: String = "compound") -> Exercise {
        Exercise(id: id(n), name: name, slug: name.lowercased(),
                 category: category, primaryMuscle: primary,
                 secondaryMuscles: secondaries, equipment: "barbell",
                 defaultUnit: "lbs", demoVideoURL: nil)
    }

    private func routine(_ n: Int, _ name: String) -> Routine {
        Routine(id: id(n), ownerID: userID, name: name, description: nil,
                visibility: "private", createdAt: now, updatedAt: now)
    }

    private func row(_ routine: Routine, _ exercise: Exercise,
                     sets: Int?, position: Int = 1) -> RoutineExercise {
        RoutineExercise(id: UUID(), routineID: routine.id, exerciseID: exercise.id,
                        position: position, targetSets: sets, targetReps: "10",
                        targetWeight: nil, restSeconds: 90, notes: nil)
    }

    private func enrollment(focus: ProgramFocus = ProgramFocus(),
                            baseline: [String: Double] = [:],
                            weeks: Int = 6,
                            endedAt: Date? = nil) -> ProgramEnrollment {
        ProgramEnrollment(id: UUID(), userID: userID, templateSlug: "hypertrophy-8",
                          focus: focus, baseline: baseline,
                          startedOnString: "2026-09-01", weeks: weeks,
                          endedAt: endedAt, endedReason: nil, createdAt: now)
    }

    private func profile(_ goals: [TrainingGoal],
                         daysPerWeek: Int = 4,
                         focusExerciseIDs: [UUID]? = nil) -> TrainingProfile {
        var result = TrainingProfile()
        result.rankedGoals = goals
        result.daysPerWeek = daysPerWeek
        result.focusExerciseIDs = focusExerciseIDs
        return result
    }

    private func detect(enrollment: ProgramEnrollment? = nil,
                        weekRoutines: [Routine] = [],
                        routineExercises: [UUID: [RoutineExercise]] = [:],
                        catalog: [UUID: Exercise] = [:],
                        trainingProfile: TrainingProfile? = nil,
                        volumeTargets: [VolumeTarget] = [],
                        effectiveWeeklyGoal: Int = 3,
                        focusLiftBaselineLbs: Decimal? = nil,
                        unit: WeightUnit = .lbs) -> WeeklyGoal {
        WeeklyGoalDetector.detect(userID: userID, enrollment: enrollment,
                                  weekRoutines: weekRoutines,
                                  routineExercises: routineExercises,
                                  catalog: catalog,
                                  trainingProfile: trainingProfile,
                                  volumeTargets: volumeTargets,
                                  effectiveWeeklyGoal: effectiveWeeklyGoal,
                                  weekStart: weekStart,
                                  focusLiftBaselineLbs: focusLiftBaselineLbs,
                                  unit: unit, now: now)
    }

    // MARK: - The law

    func testDetectionNeverReturnsNilAndAlwaysStampsCoach() {
        let goal = detect()
        XCTAssertEqual(goal.kind, .days)
        XCTAssertNil(goal.params.count,
                     "a days goal carries no count — Profile.effectiveWeeklyGoal is the only source")
        XCTAssertEqual(goal.source, .coach,
                       "a detected goal is always Coach's — that is what makes A11's propose-only rule enforceable")
        XCTAssertEqual(goal.userID, userID)
        XCTAssertEqual(goal.weekStartString, weekStart)
        XCTAssertEqual(goal.setAt, now)
    }

    func testRuleThreeWithEveryInputEmptyReturnsDays() {
        let goal = detect(effectiveWeeklyGoal: 5)
        XCTAssertEqual(goal.kind, .days)
        XCTAssertEqual(goal.params, WeeklyGoalParams(),
                       "an empty payload: the target lives on the profile, not in params")
    }

    func testDetectionIsDeterministic() {
        let squat = exercise(1, "Back Squat", "quads", secondaries: ["glutes", "core"])
        let bench = exercise(2, "Bench Press", "chest", secondaries: ["triceps"])
        let push = routine(10, "Push")
        let inputs: () -> WeeklyGoal = {
            self.detect(enrollment: self.enrollment(focus: ProgramFocus(muscleGroup: "chest")),
                        weekRoutines: [push],
                        routineExercises: [push.id: [self.row(push, squat, sets: 4),
                                                     self.row(push, bench, sets: 5, position: 2)]],
                        catalog: [squat.id: squat, bench.id: bench])
        }
        XCTAssertEqual(inputs(), inputs(),
                       "a Dictionary's iteration order must not reach a stored goal")
    }

    // MARK: - Rule 1: an active block

    func testActiveBlockWithAFocusLiftAndBaselineDetectsLift() {
        let squat = exercise(1, "Back Squat", "quads")
        let block = enrollment(focus: ProgramFocus(exerciseIDs: [squat.id]),
                               baseline: [squat.id.uuidString.lowercased(): 200])
        let goal = detect(enrollment: block, trainingProfile: profile([.maxStrength]))

        XCTAssertEqual(goal.kind, .lift)
        XCTAssertEqual(goal.params.exerciseID, squat.id)
        XCTAssertEqual(goal.params.targetWeightLbs, 210, "200 + 5 %, on the 5 lb grid")
        XCTAssertEqual(goal.params.byDate,
                       Calendar.current.date(byAdding: .day, value: 42, to: block.startedOn),
                       "the block's own end — six weeks from its start")
    }

    func testActiveStrengthBlockWithNoFocusLiftDetectsMuscleSets() {
        let bench = exercise(2, "Bench Press", "chest", secondaries: ["triceps"])
        let push = routine(10, "Push")
        let goal = detect(enrollment: enrollment(focus: ProgramFocus(muscleGroup: "chest")),
                          weekRoutines: [push],
                          routineExercises: [push.id: [row(push, bench, sets: 10)]],
                          catalog: [bench.id: bench])

        XCTAssertEqual(goal.kind, .muscleSets)
        XCTAssertEqual(goal.params.muscleTargets?["chest"], 10)
        XCTAssertEqual(goal.params.muscleTargets?["arms"], 5, "10 sets x 0.5 secondary credit")
    }

    func testFocusMuscleGroupAloneMakesABlockStrengthFlavoured() {
        // No training profile at all — `focus.muscleGroup` is the signal.
        let goal = detect(enrollment: enrollment(focus: ProgramFocus(muscleGroup: "back")))
        XCTAssertEqual(goal.kind, .muscleSets)
    }

    func testActiveConditioningBlockDetectsSessionsOfTypeCardio() {
        let goal = detect(enrollment: enrollment(),
                          trainingProfile: profile([.conditioning], daysPerWeek: 5))

        XCTAssertEqual(goal.kind, .sessionsOfType)
        XCTAssertEqual(goal.params.sessionType, "cardio")
        XCTAssertEqual(goal.params.count, 5, "the profile's own training days")
    }

    func testACardioHeavyWeekMakesABlockConditioningFlavoured() {
        // The profile's goal is neither strength nor conditioning; the
        // ROUTINES are what say what this block is.
        let bike = exercise(3, "Assault Bike", "quads", category: "cardio")
        let row2 = exercise(4, "Rower", "back", category: "cardio")
        let press = exercise(5, "Press", "shoulders", category: "compound")
        let engine = routine(11, "Engine")
        let goal = detect(enrollment: enrollment(),
                          weekRoutines: [engine],
                          routineExercises: [engine.id: [row(engine, bike, sets: 3),
                                                         row(engine, row2, sets: 3, position: 2),
                                                         row(engine, press, sets: 3, position: 3)]],
                          catalog: [bike.id: bike, row2.id: row2, press.id: press],
                          trainingProfile: profile([.mobility]))

        XCTAssertEqual(goal.kind, .sessionsOfType)
        XCTAssertEqual(goal.params.sessionType, "cardio")
    }

    func testABlockWithAnUnrecognisedIntentFallsThroughToRuleTwo() {
        // Mobility block, no cardio, no focus muscle: rule 1 declines rather
        // than forcing a kind that would misdescribe it, and rule 2's
        // catch-all answers `days`.
        let stretch = exercise(6, "Hip Opener", "hip_flexors", category: "mobility")
        let flow = routine(12, "Flow")
        let goal = detect(enrollment: enrollment(),
                          weekRoutines: [flow],
                          routineExercises: [flow.id: [row(flow, stretch, sets: 3)]],
                          catalog: [stretch.id: stretch],
                          trainingProfile: profile([.mobility]), effectiveWeeklyGoal: 4)

        XCTAssertEqual(goal.kind, .days)
        XCTAssertNil(goal.params.count)
    }

    func testAnEndedBlockIsNoBlock() {
        let squat = exercise(1, "Back Squat", "quads")
        let finished = enrollment(focus: ProgramFocus(exerciseIDs: [squat.id]),
                                  baseline: [squat.id.uuidString.lowercased(): 200],
                                  endedAt: now)
        let goal = detect(enrollment: finished, trainingProfile: profile([.generalHealth]))

        XCTAssertEqual(goal.kind, .days,
                       "a finished block must not keep prescribing this week's goal")
    }

    // MARK: - Rule 2: no block, a profile

    func testMaxStrengthWithAFocusLiftAndBaselineDetectsLift() {
        let squat = exercise(1, "Back Squat", "quads")
        let goal = detect(trainingProfile: profile([.maxStrength],
                                                   focusExerciseIDs: [squat.id]),
                          focusLiftBaselineLbs: 300)

        XCTAssertEqual(goal.kind, .lift)
        XCTAssertEqual(goal.params.exerciseID, squat.id)
        XCTAssertEqual(goal.params.targetWeightLbs, 315)
        XCTAssertNil(goal.params.byDate, "no block, so no block end to aim at")
    }

    func testMaxStrengthWithNoBaselineFallsBackToMuscleSets() {
        let squat = exercise(1, "Back Squat", "quads")
        let goal = detect(trainingProfile: profile([.maxStrength],
                                                   focusExerciseIDs: [squat.id]),
                          volumeTargets: [VolumeTarget(muscle: "chest", weeklySets: 12,
                                                       reason: nil)])

        XCTAssertEqual(goal.kind, .muscleSets,
                       "a lift goal with no number to chase renders no meter — muscleSets is the better answer")
    }

    func testMaxStrengthWithNoFocusLiftDetectsMuscleSets() {
        let goal = detect(trainingProfile: profile([.maxStrength]),
                          volumeTargets: [VolumeTarget(muscle: "back", weeklySets: 14,
                                                       reason: nil)])
        XCTAssertEqual(goal.kind, .muscleSets)
    }

    func testHypertrophyDetectsMuscleSets() {
        let goal = detect(trainingProfile: profile([.hypertrophy]),
                          volumeTargets: [VolumeTarget(muscle: "chest", weeklySets: 12,
                                                       reason: nil)])
        XCTAssertEqual(goal.kind, .muscleSets)
        XCTAssertEqual(goal.params.muscleTargets?["chest"], 12)
    }

    func testConditioningDetectsDistanceScaledByTrainingDays() {
        let goal = detect(trainingProfile: profile([.conditioning], daysPerWeek: 4))

        XCTAssertEqual(goal.kind, .distance)
        XCTAssertEqual(goal.params.activity, "run")
        XCTAssertEqual(goal.params.distanceTarget, 12, "4 days x 3 mi")
    }

    func testFatLossDetectsDistanceInKilometresForAMetricAthlete() {
        let goal = detect(trainingProfile: profile([.fatLoss], daysPerWeek: 4),
                          unit: .kg)

        XCTAssertEqual(goal.kind, .distance)
        XCTAssertEqual(goal.params.distanceTarget, 20, "4 days x 5 km")
    }

    func testEveryOtherGoalDetectsDays() {
        for goalKind in [TrainingGoal.powerRFD, .boneDensity, .mobility,
                         .sportPrep, .generalHealth] {
            let goal = detect(trainingProfile: profile([goalKind]), effectiveWeeklyGoal: 3)
            XCTAssertEqual(goal.kind, .days, "\(goalKind)")
            XCTAssertNil(goal.params.count, "\(goalKind)")
        }
    }

    // MARK: - muscleSets targets: titration first

    func testTitrationIsReadBeforeTheRoutines() {
        let bench = exercise(2, "Bench Press", "chest")
        let push = routine(10, "Push")
        let goal = detect(enrollment: enrollment(focus: ProgramFocus(muscleGroup: "chest")),
                          weekRoutines: [push],
                          routineExercises: [push.id: [row(push, bench, sets: 99)]],
                          catalog: [bench.id: bench],
                          volumeTargets: [VolumeTarget(muscle: "chest", weeklySets: 14,
                                                       reason: "recovered in 2 days")])

        XCTAssertEqual(goal.params.targetSource, "titration")
        XCTAssertEqual(goal.params.muscleTargets?["chest"], 14,
                       "what the body answered outranks what the template prescribed")
    }

    func testTitrationSumsEveryMuscleInAGroup() {
        let targets = WeeklyGoalDetector.titratedTargets([
            VolumeTarget(muscle: "chest", weeklySets: 14, reason: nil),
            VolumeTarget(muscle: "upper_chest", weeklySets: 4, reason: nil),
            VolumeTarget(muscle: "lats", weeklySets: 12, reason: nil),
            VolumeTarget(muscle: "neck", weeklySets: 6, reason: nil),
        ])

        XCTAssertEqual(targets[.chest], 18, "chest + upper_chest")
        XCTAssertEqual(targets[.back], 12)
        XCTAssertEqual(targets.count, 2, "`neck` belongs to none of the six")
    }

    func testRoutinesAreTheFallbackAndSaySo() {
        let bench = exercise(2, "Bench Press", "chest", secondaries: ["triceps"])
        let push = routine(10, "Push")
        let goal = detect(enrollment: enrollment(focus: ProgramFocus(muscleGroup: "chest")),
                          weekRoutines: [push],
                          routineExercises: [push.id: [row(push, bench, sets: 12)]],
                          catalog: [bench.id: bench])

        XCTAssertEqual(goal.params.targetSource, "routines")
        XCTAssertEqual(goal.params.muscleTargets?["chest"], 12)
        XCTAssertEqual(goal.params.muscleTargets?["arms"], 6)
    }

    func testRoutineRowsWithNoTargetSetsContributeNothing() {
        // A cardio prescription carries minutes, not sets.
        let bike = exercise(3, "Assault Bike", "quads", category: "cardio")
        let bench = exercise(2, "Bench Press", "chest")
        let mixed = routine(13, "Mixed")
        let targets = WeeklyGoalDetector.routineTargets(
            weekRoutines: [mixed],
            routineExercises: [mixed.id: [row(mixed, bike, sets: nil),
                                          row(mixed, bench, sets: 8, position: 2)]],
            catalog: [bike.id: bike, bench.id: bench])

        XCTAssertEqual(targets[.chest], 8)
        XCTAssertNil(targets[.legs])
    }

    func testMuscleSetsNeverEmitsMoreThanSixGroups() {
        let everything: [VolumeTarget] = [
            .init(muscle: "chest", weeklySets: 12, reason: nil),
            .init(muscle: "upper_chest", weeklySets: 4, reason: nil),
            .init(muscle: "lats", weeklySets: 12, reason: nil),
            .init(muscle: "traps", weeklySets: 6, reason: nil),
            .init(muscle: "shoulders", weeklySets: 10, reason: nil),
            .init(muscle: "rear_delts", weeklySets: 4, reason: nil),
            .init(muscle: "quads", weeklySets: 16, reason: nil),
            .init(muscle: "hamstrings", weeklySets: 8, reason: nil),
            .init(muscle: "biceps", weeklySets: 8, reason: nil),
            .init(muscle: "triceps", weeklySets: 8, reason: nil),
            .init(muscle: "core", weeklySets: 6, reason: nil),
            .init(muscle: "obliques", weeklySets: 4, reason: nil),
        ]
        let params = WeeklyGoalDetector.muscleSetParams(
            volumeTargets: everything, weekRoutines: [], routineExercises: [:],
            catalog: [:])

        XCTAssertEqual(params.muscleTargets?.count, 6)
        XCTAssertEqual(params.targetSource, "titration")
    }

    // MARK: - The WEEK's routines, never the library

    private func completedSession(_ routine: Routine, dayOffset: Int) -> WorkoutSession {
        let when = Calendar.current.date(byAdding: .day, value: dayOffset, to: now)!
        return WorkoutSession(id: UUID(), routineID: routine.id, organizerID: userID,
                              state: "completed", startedAt: when, completedAt: when,
                              createdAt: when, groupID: nil, roomCode: nil,
                              scheduledFor: nil, seriesID: nil,
                              currentTurnUserID: nil, currentTurnStartedAt: nil)
    }

    private func bookedSession(_ routine: Routine, dayOffset: Int) -> WorkoutSession {
        let when = Calendar.current.date(byAdding: .day, value: dayOffset, to: now)!
        return WorkoutSession(id: UUID(), routineID: routine.id, organizerID: userID,
                              state: "scheduled", startedAt: nil, completedAt: nil,
                              createdAt: now, groupID: nil, roomCode: nil,
                              scheduledFor: when, seriesID: nil,
                              currentTurnUserID: nil, currentTurnStartedAt: nil)
    }

    /// THE DEFECT THIS PINS: `weekRoutines` used to be the athlete's whole
    /// routine LIBRARY, so five saved routines summed into one week's
    /// targets — a number several times what the week prescribes, and a goal
    /// that cannot be met.
    func testRoutinesTheWeekDoesNotUseContributeNothing() {
        let bench = exercise(2, "Bench Press", "chest")
        let squat = exercise(1, "Back Squat", "quads")
        let curl = exercise(7, "Curl", "biceps")

        let push = routine(10, "Push")          // trained this week
        let legs = routine(11, "Legs")          // in the library, NOT this week
        let arms = routine(12, "Arms")          // in the library, NOT this week
        let library = [push, legs, arms]

        let rows: [UUID: [RoutineExercise]] = [
            push.id: [row(push, bench, sets: 10)],
            legs.id: [row(legs, squat, sets: 20)],
            arms.id: [row(arms, curl, sets: 20)],
        ]
        let catalogByID = [bench.id: bench, squat.id: squat, curl.id: curl]

        // Only `push` has a session in this week.
        let weekRoutines = WeeklyGoalDetector.routinesForWeek(
            library: library,
            sessions: [completedSession(push, dayOffset: 0)],
            now: now, calendar: .current)

        XCTAssertEqual(weekRoutines.map(\.id), [push.id])

        let targets = WeeklyGoalDetector.routineTargets(
            weekRoutines: weekRoutines, routineExercises: rows, catalog: catalogByID)

        XCTAssertEqual(targets[.chest], 10)
        XCTAssertNil(targets[.legs], "a routine the week does not use is not a target")
        XCTAssertNil(targets[.arms], "nor is one saved for some other block")
    }

    func testABookedButUntrainedRoutineIsStillTheWeeksRoutine() {
        // Monday must not derive its targets from an empty week: a session
        // on the books counts as this week's, not only a completed one.
        let push = routine(10, "Push")
        let weekRoutines = WeeklyGoalDetector.routinesForWeek(
            library: [push], sessions: [bookedSession(push, dayOffset: 1)],
            now: now, calendar: .current)

        XCTAssertEqual(weekRoutines.map(\.id), [push.id])
    }

    func testASessionInAnotherWeekDoesNotPullItsRoutineIn() {
        let push = routine(10, "Push")
        let weekRoutines = WeeklyGoalDetector.routinesForWeek(
            library: [push], sessions: [completedSession(push, dayOffset: -21)],
            now: now, calendar: .current)

        XCTAssertTrue(weekRoutines.isEmpty)
    }

    func testASessionWithNoRoutineContributesNoRoutineID() {
        let freestyle = WorkoutSession(id: UUID(), routineID: nil, organizerID: userID,
                                       state: "completed", startedAt: now,
                                       completedAt: now, createdAt: now, groupID: nil,
                                       roomCode: nil, scheduledFor: nil, seriesID: nil,
                                       currentTurnUserID: nil, currentTurnStartedAt: nil)
        XCTAssertTrue(WeeklyGoalDetector.weekRoutineIDs(sessions: [freestyle],
                                                        now: now, calendar: .current)
                          .isEmpty)
    }

    // MARK: - The lift target's unit round trip

    func testLiftTargetRoundsOnTheGridTheAthletesPlatesAreMarkedIn() {
        XCTAssertEqual(WeeklyGoalDetector.liftTarget(fromBaselineLbs: 200, unit: .lbs),
                       210, "200 lb + 5 % = 210, already on the 5 lb grid")
        XCTAssertEqual(WeeklyGoalDetector.liftTarget(fromBaselineLbs: 185, unit: .lbs),
                       195, "194.25 rounds to the nearest 5")

        // 200 lb is 90.72 kg; +5 % is 95.25 kg; the 2.5 kg grid says 95.0 kg,
        // which is 209.44 lb back in canonical pounds. Rounding the POUNDS
        // figure to a kg step would land on a bar no metric gym can build.
        let metric = WeeklyGoalDetector.liftTarget(fromBaselineLbs: 200, unit: .kg)
        XCTAssertEqual(NSDecimalNumber(decimal: metric).doubleValue, 209.439,
                       accuracy: 0.01)
    }
}
