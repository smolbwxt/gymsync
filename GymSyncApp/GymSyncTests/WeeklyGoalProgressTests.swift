import XCTest
@testable import GymSync

/// `WeeklyGoalProgressMath` — the pure arithmetic behind the weekly goal
/// strip. Plan: Stream A tasks A3-A7.
///
/// The contract these pin: a penalty is not training, a missed single is
/// not a set, a failed triple IS two reps of work, and the six-group
/// rollup is applied once per counted log.
final class WeeklyGoalProgressTests: XCTestCase {

    // MARK: - Fixtures

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

    private func log(_ exercise: Exercise, reps: Int?, index: Int = 1,
                     failed: Bool = false, penalty: Bool = false) -> SetLog {
        SetLog(id: UUID(), userID: id(9001), sessionID: id(9002),
               exerciseID: exercise.id, setIndex: index, reps: reps,
               weight: 135, rpe: nil, isFailed: failed, isPenalty: penalty,
               note: nil, loggedAt: Date(timeIntervalSince1970: 1_788_696_000))
    }

    private func catalog(_ exercises: [Exercise]) -> [UUID: Exercise] {
        Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
    }

    /// The plan's own worked example: chest 1.0, arms 0.5, shoulders 0.5.
    private let benchPrimary = "chest"
    private let benchSecondaries = ["triceps", "front_delts"]

    // MARK: - A3: what counts as a set

    func testCleanSetCreditsThePerSetMap() {
        let bench = exercise(1, "Bench Press", benchPrimary,
                             secondaries: benchSecondaries)
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(bench, reps: 8)], catalog: catalog([bench]))

        XCTAssertEqual(tally[.chest], 1.0)
        XCTAssertEqual(tally[.arms], 0.5)
        XCTAssertEqual(tally[.shoulders], 0.5)
        XCTAssertNil(tally[.back])
    }

    func testFailedSingleCreditsNothing() {
        let bench = exercise(1, "Bench Press", benchPrimary,
                             secondaries: benchSecondaries)
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(bench, reps: 1, failed: true)], catalog: catalog([bench]))

        XCTAssertTrue(tally.isEmpty,
                      "a missed single completed zero reps — nothing was lifted")
    }

    func testFailedTripleCreditsFully() {
        let bench = exercise(1, "Bench Press", benchPrimary,
                             secondaries: benchSecondaries)
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(bench, reps: 3, failed: true)], catalog: catalog([bench]))

        XCTAssertEqual(tally[.chest], 1.0,
                       "a failed triple completed 2 reps — that is a set of work")
        XCTAssertEqual(tally[.arms], 0.5)
        XCTAssertEqual(tally[.shoulders], 0.5)
    }

    func testPenaltySetCreditsNothing() {
        let burpee = exercise(2, "Burpee", "legs", secondaries: ["chest", "core"])
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(burpee, reps: 20, penalty: true)], catalog: catalog([burpee]))

        XCTAssertTrue(tally.isEmpty,
                      "the late-arrival burpee tax is not training volume")
    }

    func testNilRepsCreditsNothing() {
        let bench = exercise(1, "Bench Press", benchPrimary)
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(bench, reps: nil)], catalog: catalog([bench]))

        XCTAssertTrue(tally.isEmpty, "a log with no reps proves no work")
    }

    func testTwoSetsCreditTwiceThePerSetMap() {
        let bench = exercise(1, "Bench Press", benchPrimary,
                             secondaries: benchSecondaries)
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(bench, reps: 8, index: 1), log(bench, reps: 6, index: 2)],
            catalog: catalog([bench]))

        XCTAssertEqual(tally[.chest], 2.0)
        XCTAssertEqual(tally[.arms], 1.0)
        XCTAssertEqual(tally[.shoulders], 1.0)
    }

    func testUnknownExerciseIsSkippedNotGuessed() {
        let bench = exercise(1, "Bench Press", benchPrimary)
        let ghost = exercise(99, "Ghost Lift", "back")
        // `ghost` is logged but absent from the catalog — a stale local copy.
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(bench, reps: 8), log(ghost, reps: 8)],
            catalog: catalog([bench]))

        XCTAssertEqual(tally[.chest], 1.0)
        XCTAssertNil(tally[.back], "an exercise the catalog does not carry credits nothing")
    }

    func testUnmappedMuscleCreditsNothingAndIsNotAnError() {
        let shrug = exercise(3, "Neck Curl", "neck", secondaries: ["neck"])
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(shrug, reps: 12)], catalog: catalog([shrug]))

        XCTAssertTrue(tally.isEmpty,
                      "`neck` is real catalog data that belongs to none of the six groups")
    }

    func testEmptyWeekIsAnEmptyTally() {
        XCTAssertTrue(WeeklyGoalProgressMath.muscleSetCredit(logs: [], catalog: [:]).isEmpty)
    }

    func testBackSquatPaysLegsOnceNotTwice() {
        // The rollup-before-dedupe rule, exercised through the tally rather
        // than through `MuscleGroup.credit` directly: glutes and hamstrings
        // both roll up to `legs`, which is already the primary's group.
        let squat = exercise(4, "Back Squat", "quads",
                             secondaries: ["glutes", "hamstrings", "core"])
        let tally = WeeklyGoalProgressMath.muscleSetCredit(
            logs: [log(squat, reps: 5)], catalog: catalog([squat]))

        XCTAssertEqual(tally[.legs], 1.0, "legs is paid once, as the primary")
        XCTAssertEqual(tally[.core], 0.5)
        XCTAssertEqual(tally.count, 2)
    }

    // MARK: - A4 fixtures

    /// A calendar with a fixed timezone, `firstWeekday` and LOCALE, so
    /// "this week" is the same week — and its day letters the same letters —
    /// on every machine that runs these. The locale is pinned because
    /// `weekdayLetters` reads `veryShortWeekdaySymbols`, which is localised.
    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        return calendar
    }

    /// Wednesday 2026-09-09, noon Eastern. Its week (firstWeekday 1) runs
    /// Sun 09-06 … Sat 09-12, so `daysRemaining` is 4 (Wed, Thu, Fri, Sat).
    private var wednesday: Date {
        testCalendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))!
    }

    private func goal(_ kind: WeeklyGoalKind,
                      params: WeeklyGoalParams = .init(),
                      source: WeeklyGoalSource = .coach) -> WeeklyGoal {
        WeeklyGoal(userID: id(9001),
                   weekStartString: WeekMath.weekStartString(wednesday, calendar: testCalendar),
                   kind: kind, params: params, source: source,
                   setAt: wednesday)
    }

    /// A session on the books but not yet done — `scheduledFor` set,
    /// `completedAt` nil.
    private func scheduledSession(dayOffset: Int) -> WorkoutSession {
        let when = testCalendar.date(byAdding: .day, value: dayOffset, to: wednesday)!
        return WorkoutSession(id: UUID(), routineID: nil, organizerID: id(9001),
                              state: "scheduled", startedAt: nil, completedAt: nil,
                              createdAt: wednesday, groupID: nil, roomCode: nil,
                              scheduledFor: when, seriesID: nil,
                              currentTurnUserID: nil, currentTurnStartedAt: nil)
    }

    private func session(completedDaysFromWednesday offset: Int) -> WorkoutSession {
        let completed = testCalendar.date(byAdding: .day, value: offset, to: wednesday)!
        return WorkoutSession(id: UUID(), routineID: nil, organizerID: id(9001),
                              state: "completed", startedAt: completed,
                              completedAt: completed, createdAt: completed,
                              groupID: nil, roomCode: nil, scheduledFor: nil,
                              seriesID: nil, currentTurnUserID: nil,
                              currentTurnStartedAt: nil)
    }

    // MARK: - A4: muscleSets

    func testChipsAreTheFourLargestTargets() {
        let targets = ["chest": 12, "back": 14, "legs": 16, "arms": 8,
                       "shoulders": 10, "core": 6]
        let progress = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets, params: .init(muscleTargets: targets)),
            logs: [], catalog: [:], now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.chips.map(\.name), ["LEGS", "BACK", "CHEST", "SHOULDERS"],
                       "the four LARGEST targets, in descending order")
        XCTAssertEqual(progress.chips.map(\.target), [16, 14, 12, 10])
    }

    func testEqualTargetsBreakTiesByDeclarationOrder() {
        // All six at the same target: the rendered four must be the first
        // four of `MuscleGroup.allCases`, every time.
        let targets = ["chest": 10, "back": 10, "shoulders": 10, "legs": 10,
                       "arms": 10, "core": 10]
        let params = WeeklyGoalParams(muscleTargets: targets)
        let first = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets, params: params), logs: [], catalog: [:],
            now: wednesday, calendar: testCalendar)
        let second = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets, params: params), logs: [], catalog: [:],
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(first.chips.map(\.name), ["CHEST", "BACK", "SHOULDERS", "LEGS"])
        XCTAssertEqual(first.chips, second.chips,
                       "a dictionary's order must never reach the strip")
    }

    func testIsNextPicksTheLargestDeficitNotTheSmallestFraction() {
        let bench = exercise(1, "Bench Press", "chest")          // chest only
        let curl = exercise(2, "Curl", "biceps")                 // arms only
        // chest 10/12 → deficit 2, fraction 0.83
        // arms   4/8  → deficit 4, fraction 0.50 … and 4 > 2, so ARMS is next.
        // A smallest-fraction rule would also say arms here, so make them
        // disagree: chest 4/12 (deficit 8, fraction 0.33) vs arms 7/8
        // (deficit 1, fraction 0.875). Largest deficit = CHEST.
        let logs = Array(repeating: log(bench, reps: 8), count: 4)
            + Array(repeating: log(curl, reps: 10), count: 7)
        let progress = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets, params: .init(muscleTargets: ["chest": 12, "arms": 8])),
            logs: logs, catalog: catalog([bench, curl]),
            now: wednesday, calendar: testCalendar)

        let next = progress.chips.filter(\.isNext)
        XCTAssertEqual(next.count, 1, "exactly one chip is next")
        XCTAssertEqual(next.first?.name, "CHEST",
                       "8 sets short beats 1 set short, even at a worse fraction")
    }

    func testZeroTargetGroupIsNeverNextAndIsNeverMet() {
        let progress = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets, params: .init(muscleTargets: ["chest": 0, "back": 0])),
            logs: [], catalog: [:], now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.chips.count, 2)
        XCTAssertTrue(progress.chips.allSatisfy { !$0.isNext },
                      "a 0/0 chip draws an empty meter and prompts nothing")
        XCTAssertFalse(progress.met,
                       "an athlete who trained nothing must not open Home to GOAL MET — a 0 target is reachable through the editor's steppers AND through a volume_targets row at weekly_sets = 0")
    }

    func testARealTargetAlongsideAZeroOneStillDecidesMet() {
        let bench = exercise(1, "Bench Press", "chest")
        let progress = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets, params: .init(muscleTargets: ["chest": 2, "back": 0])),
            logs: [log(bench, reps: 8), log(bench, reps: 8, index: 2)],
            catalog: catalog([bench]), now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.met,
                      "one chip with a real target, and it is met — the 0-target chip does not veto it")
    }

    func testNoChipIsNextWhenEveryChipIsMet() {
        let bench = exercise(1, "Bench Press", "chest")
        let logs = Array(repeating: log(bench, reps: 8), count: 12)
        let progress = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets, params: .init(muscleTargets: ["chest": 12])),
            logs: logs, catalog: catalog([bench]),
            now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.met)
        XCTAssertTrue(progress.chips.allSatisfy { !$0.isNext })
        XCTAssertEqual(progress.kicker, "GOAL MET · 4 DAYS LEFT")
    }

    func testUnknownMuscleTargetKeyIsDropped() {
        let progress = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets, params: .init(muscleTargets: ["chest": 12, "neck": 20])),
            logs: [], catalog: [:], now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.chips.map(\.name), ["CHEST"],
                       "a target for a group that does not exist renders no chip")
    }

    func testMuscleSetsCarriesTheKickerAndRightHandRead() {
        let coach = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets, params: .init(muscleTargets: ["chest": 12])),
            logs: [], catalog: [:], now: wednesday, calendar: testCalendar)
        let user = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets, params: .init(muscleTargets: ["chest": 12]),
                       source: .user),
            logs: [], catalog: [:], now: wednesday, calendar: testCalendar)

        XCTAssertEqual(coach.kicker, "THIS WEEK · COACH'S GOAL")
        XCTAssertEqual(user.kicker, "THIS WEEK · YOUR GOAL")
        XCTAssertEqual(coach.rightHandRead, "4 DAYS LEFT")
    }

    func testEmptyTargetsAreNotVacuouslyMet() {
        let progress = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets), logs: [], catalog: [:],
            now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.chips.isEmpty)
        XCTAssertFalse(progress.met,
                       "a goal with no targets has not been met — it has not been set")
    }

    // MARK: - A4: days

    func testDaysCountsDistinctDaysNotSessions() {
        // Two sessions the same day, one the day before → 2 days.
        let sessions = [session(completedDaysFromWednesday: 0),
                        session(completedDaysFromWednesday: 0),
                        session(completedDaysFromWednesday: -1)]
        let progress = WeeklyGoalProgressMath.daysProgress(
            goal: goal(.days), sessions: sessions, effectiveWeeklyGoal: 4,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 2)
        XCTAssertEqual(progress.target, 4)
        XCTAssertFalse(progress.met)
        XCTAssertEqual(progress.rightHandRead, "4 DAYS LEFT")
    }

    func testDaysIgnoresSessionsOutsideThisWeek() {
        // -4 days from Wednesday is Saturday 09-05, the PREVIOUS week under
        // firstWeekday 1 (weeks run Sun…Sat).
        let sessions = [session(completedDaysFromWednesday: 0),
                        session(completedDaysFromWednesday: -4)]
        let progress = WeeklyGoalProgressMath.daysProgress(
            goal: goal(.days), sessions: sessions, effectiveWeeklyGoal: 4,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 1)
    }

    func testDaysIgnoresIncompleteSessions() {
        let inProgress = WorkoutSession(id: UUID(), routineID: nil,
                                        organizerID: id(9001), state: "in_progress",
                                        startedAt: wednesday, completedAt: nil,
                                        createdAt: wednesday, groupID: nil,
                                        roomCode: nil, scheduledFor: nil,
                                        seriesID: nil, currentTurnUserID: nil,
                                        currentTurnStartedAt: nil)
        let progress = WeeklyGoalProgressMath.daysProgress(
            goal: goal(.days), sessions: [inProgress], effectiveWeeklyGoal: 3,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 0, "a session still running is not a training day")
    }

    /// THE AGREEMENT LAW. `HomeView.daysThisWeek` (:950) is reproduced here
    /// literally — the same rule, spelled out — and must classify the same
    /// fixtures identically. When Stream B's task B1 replaces HomeView's copy
    /// with a call to `distinctTrainingDays`, this test is what proves the
    /// replacement was behaviour-preserving.
    func testDaysAgreesWithHomeViewsOwnRule() {
        let sessions = [session(completedDaysFromWednesday: 0),
                        session(completedDaysFromWednesday: 0),
                        session(completedDaysFromWednesday: -1),
                        session(completedDaysFromWednesday: -4),   // last week
                        session(completedDaysFromWednesday: 2)]
        let calendar = testCalendar

        // HomeView.daysThisWeek, verbatim but for the two injected globals.
        let homeViewsAnswer = Set(sessions.compactMap { session -> Date? in
            guard let completedAt = session.completedAt,
                  calendar.isDate(completedAt, equalTo: wednesday,
                                  toGranularity: .weekOfYear)
            else { return nil }
            return calendar.startOfDay(for: completedAt)
        }).count

        XCTAssertEqual(
            WeeklyGoalProgressMath.distinctTrainingDays(sessions: sessions,
                                                        now: wednesday,
                                                        calendar: calendar),
            homeViewsAnswer,
            "the goal strip and the streak tile must count the same week")
        XCTAssertEqual(homeViewsAnswer, 3)
    }

    func testDaysMetFlipsTheKicker() {
        // Wed, Tue, Mon — three distinct days, all inside the Sun-Sat week.
        let sessions = [session(completedDaysFromWednesday: 0),
                        session(completedDaysFromWednesday: -1),
                        session(completedDaysFromWednesday: -2)]
        let progress = WeeklyGoalProgressMath.daysProgress(
            goal: goal(.days), sessions: sessions, effectiveWeeklyGoal: 3,
            now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.met)
        XCTAssertEqual(progress.kicker, "GOAL MET · 4 DAYS LEFT")
    }

    // MARK: - A4: the copy helpers

    func testDaysLeftPhraseIsSingularAtOne() {
        XCTAssertEqual(WeeklyGoalProgressMath.daysLeftPhrase(1), "1 DAY LEFT")
        XCTAssertEqual(WeeklyGoalProgressMath.daysLeftPhrase(3), "3 DAYS LEFT")
        XCTAssertEqual(WeeklyGoalProgressMath.daysLeftPhrase(0), "0 DAYS LEFT")
    }

    // MARK: - A4: the dispatcher

    func testDispatcherRoutesMuscleSetsAndDays() {
        let bench = exercise(1, "Bench Press", "chest")
        let muscleSets = WeeklyGoalProgressMath.progress(
            goal: goal(.muscleSets, params: .init(muscleTargets: ["chest": 12])),
            logs: [log(bench, reps: 8)], catalog: catalog([bench]),
            sessions: [], effectiveWeeklyGoal: 3,
            now: wednesday, calendar: testCalendar)
        let days = WeeklyGoalProgressMath.progress(
            goal: goal(.days), logs: [], catalog: [:],
            sessions: [session(completedDaysFromWednesday: 0)],
            effectiveWeeklyGoal: 3, now: wednesday, calendar: testCalendar)

        XCTAssertEqual(muscleSets.chips.count, 1)
        XCTAssertEqual(days.value, 1)
    }

    // MARK: - A5: lift

    private func liftLog(_ exercise: Exercise, weight: Decimal, reps: Int,
                         failed: Bool = false, dayOffset: Int = 0) -> SetLog {
        SetLog(id: UUID(), userID: id(9001), sessionID: id(9002),
               exerciseID: exercise.id, setIndex: 1, reps: reps, weight: weight,
               rpe: 7, isFailed: failed, isPenalty: false, note: nil,
               loggedAt: testCalendar.date(byAdding: .day, value: dayOffset,
                                           to: wednesday)!)
    }

    private func liftGoal(_ squat: Exercise, targetLbs: Decimal,
                          byDate: Date? = nil) -> WeeklyGoal {
        goal(.lift, params: .init(exerciseID: squat.id,
                                  targetWeightLbs: targetLbs, byDate: byDate))
    }

    func testLiftMeterRunsFromTheBlockStartNotFromZero() {
        let squat = exercise(5, "Back Squat", "quads")
        // 190 x 5 → Epley 190 x (1 + 5/30) = 221.666…
        let progress = WeeklyGoalProgressMath.liftProgress(
            goal: liftGoal(squat, targetLbs: 225),
            blockLogs: [liftLog(squat, weight: 190, reps: 5)],
            blockStartLbs: 200, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 221.666, accuracy: 0.01,
                       "value is the READABLE current e1RM")
        XCTAssertEqual(progress.target, 225, accuracy: 0.001)
        XCTAssertEqual(progress.chips.count, 1)
        XCTAssertEqual(progress.chips[0].target, 25, accuracy: 0.001,
                       "the meter's span is target − block start, not target")
        XCTAssertEqual(progress.chips[0].done, 21.666, accuracy: 0.01)
        XCTAssertFalse(progress.met)
        XCTAssertEqual(progress.unitLabel, "lbs")
    }

    func testLiftWithNoLogsRendersZeroAndDoesNotCrash() {
        let squat = exercise(5, "Back Squat", "quads")
        let progress = WeeklyGoalProgressMath.liftProgress(
            goal: liftGoal(squat, targetLbs: 225), blockLogs: [],
            blockStartLbs: 200, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 0)
        XCTAssertEqual(progress.target, 225, accuracy: 0.001)
        XCTAssertEqual(progress.chips[0].done, 0,
                       "below the floor clamps to an empty meter, never negative")
        XCTAssertFalse(progress.met)
    }

    func testLiftBlockStartEqualToTargetDoesNotDivideByZero() {
        let squat = exercise(5, "Back Squat", "quads")
        let progress = WeeklyGoalProgressMath.liftProgress(
            goal: liftGoal(squat, targetLbs: 225), blockLogs: [],
            blockStartLbs: 225, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.chips[0].target, 1,
                       "no span to fill renders full-or-empty, not 0/0")
        XCTAssertEqual(progress.chips[0].done, 0)
        XCTAssertTrue(progress.chips[0].target > 0,
                      "the meter's denominator is never zero")
    }

    func testLiftFallsBackToTheEarliestE1RMWhenTheBlockCarriesNoBaseline() {
        let squat = exercise(5, "Back Squat", "quads")
        let logs = [liftLog(squat, weight: 180, reps: 5, dayOffset: -3),   // 210
                    liftLog(squat, weight: 200, reps: 5, dayOffset: 0)]    // 233.33
        let progress = WeeklyGoalProgressMath.liftProgress(
            goal: liftGoal(squat, targetLbs: 260), blockLogs: logs,
            blockStartLbs: nil, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        // floor = earliest = 210, current = best = 233.33, span = 50
        XCTAssertEqual(progress.chips[0].target, 50, accuracy: 0.001)
        XCTAssertEqual(progress.chips[0].done, 23.333, accuracy: 0.01)
    }

    func testLiftUsesCompletedRepsAndThePlainEpleyVariant() {
        let squat = exercise(5, "Back Squat", "quads")
        // A failed single completed nothing and must not set an e1RM; the
        // clean 200 x 5 must, at the PLAIN estimate (233.33) and not the
        // RPE-aware one, which at rpe 7 would treat it as an 8-rep set (253.33).
        let logs = [liftLog(squat, weight: 315, reps: 1, failed: true),
                    liftLog(squat, weight: 200, reps: 5)]
        let best = WeeklyGoalProgressMath.bestE1RMPounds(logs: logs,
                                                         exerciseID: squat.id)

        XCTAssertNotNil(best)
        XCTAssertEqual(WeeklyGoalProgressTests.double(best ?? 0), 233.333,
                       accuracy: 0.01,
                       "a record is what you DID — the plain variant, and no credit for a missed single")
    }

    func testLiftConvertsTheReadableNumbersToTheAthletesUnit() {
        let squat = exercise(5, "Back Squat", "quads")
        let progress = WeeklyGoalProgressMath.liftProgress(
            goal: liftGoal(squat, targetLbs: 225),
            blockLogs: [liftLog(squat, weight: 200, reps: 5)],
            blockStartLbs: 200, unit: .kg,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.unitLabel, "kg")
        XCTAssertEqual(progress.target, 102.06, accuracy: 0.05, "225 lb in kg")
        XCTAssertEqual(progress.value, 105.84, accuracy: 0.05, "233.33 lb in kg")
    }

    func testLiftMetFlipsTheKicker() {
        let squat = exercise(5, "Back Squat", "quads")
        let progress = WeeklyGoalProgressMath.liftProgress(
            goal: liftGoal(squat, targetLbs: 225),
            blockLogs: [liftLog(squat, weight: 200, reps: 5)],   // 233.33 ≥ 225
            blockStartLbs: 200, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.met)
        XCTAssertEqual(progress.kicker, "GOAL MET · 4 DAYS LEFT")
    }

    func testLiftWithoutAnExerciseOrTargetRendersChromeNotAMetZero() {
        let progress = WeeklyGoalProgressMath.liftProgress(
            goal: goal(.lift), blockLogs: [], blockStartLbs: nil, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.chips.isEmpty)
        XCTAssertFalse(progress.met)
        XCTAssertEqual(progress.kicker, "THIS WEEK · COACH'S GOAL")
    }

    func testWeeksLeftPhrase() {
        let calendar = testCalendar
        func phrase(_ dayOffset: Int) -> String? {
            WeeklyGoalProgressMath.weeksLeftPhrase(
                to: calendar.date(byAdding: .day, value: dayOffset, to: wednesday),
                from: wednesday, calendar: calendar)
        }

        XCTAssertEqual(phrase(15), "3 WEEKS LEFT")
        XCTAssertEqual(phrase(7), "1 WEEK LEFT")
        XCTAssertEqual(phrase(1), "1 WEEK LEFT")
        XCTAssertEqual(phrase(-3), "0 WEEKS LEFT",
                       "a deadline behind you is 0 weeks, not invented copy")
        XCTAssertNil(WeeklyGoalProgressMath.weeksLeftPhrase(to: nil, from: wednesday,
                                                            calendar: calendar))
    }

    func testLiftRightHandReadIsWeeksWhenTheGoalNamesADate() {
        let squat = exercise(5, "Back Squat", "quads")
        let byDate = testCalendar.date(byAdding: .day, value: 15, to: wednesday)!
        let dated = WeeklyGoalProgressMath.liftProgress(
            goal: liftGoal(squat, targetLbs: 225, byDate: byDate),
            blockLogs: [], blockStartLbs: 200, unit: .lbs,
            now: wednesday, calendar: testCalendar)
        let undated = WeeklyGoalProgressMath.liftProgress(
            goal: liftGoal(squat, targetLbs: 225), blockLogs: [],
            blockStartLbs: 200, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(dated.rightHandRead, "3 WEEKS LEFT")
        XCTAssertEqual(undated.rightHandRead, "4 DAYS LEFT",
                       "no date falls back to the week's own read")
    }

    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    func testDispatcherRoutesLift() {
        let squat = exercise(5, "Back Squat", "quads")
        let progress = WeeklyGoalProgressMath.progress(
            goal: liftGoal(squat, targetLbs: 225), logs: [], catalog: [:],
            sessions: [], effectiveWeeklyGoal: 3,
            blockLogs: [liftLog(squat, weight: 190, reps: 5)],
            blockStartLbs: 200, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.chips.count, 1)
        XCTAssertEqual(progress.unitLabel, "lbs")
    }

    // MARK: - A6: sessionsOfType

    private func routine(_ n: Int, _ name: String) -> Routine {
        Routine(id: id(n), ownerID: id(9001), name: name, description: nil,
                visibility: "private", createdAt: wednesday, updatedAt: wednesday)
    }

    private func routineRow(_ routine: Routine, _ exercise: Exercise,
                            position: Int) -> RoutineExercise {
        RoutineExercise(id: UUID(), routineID: routine.id, exerciseID: exercise.id,
                        position: position, targetSets: 3, targetReps: "10",
                        targetWeight: nil, restSeconds: 90, notes: nil)
    }

    private func sessionOf(_ routine: Routine?, dayOffset: Int = 0) -> WorkoutSession {
        let completed = testCalendar.date(byAdding: .day, value: dayOffset,
                                          to: wednesday)!
        return WorkoutSession(id: UUID(), routineID: routine?.id,
                              organizerID: id(9001), state: "completed",
                              startedAt: completed, completedAt: completed,
                              createdAt: completed, groupID: nil, roomCode: nil,
                              scheduledFor: nil, seriesID: nil,
                              currentTurnUserID: nil, currentTurnStartedAt: nil)
    }

    func testCardioCountsWhenHalfTheRoutineIsCardio() {
        let bike = exercise(10, "Assault Bike", "quads", category: "cardio")
        let row = exercise(11, "Rower", "back", category: "cardio")
        let press = exercise(12, "Bench Press", "chest", category: "compound")
        let conditioning = routine(20, "Tuesday Engine")
        let rows = [routineRow(conditioning, bike, position: 1),
                    routineRow(conditioning, row, position: 2),
                    routineRow(conditioning, press, position: 3)]

        XCTAssertTrue(WeeklyGoalProgressMath.sessionCounts(
            towardType: "cardio", session: sessionOf(conditioning),
            routines: [conditioning.id: conditioning],
            routineExercises: [conditioning.id: rows],
            catalog: catalog([bike, row, press]), calendar: testCalendar),
            "2 of 3 cardio clears the half threshold")
    }

    func testCardioDoesNotCountWhenOnlyOneExerciseIsCardio() {
        let bike = exercise(10, "Assault Bike", "quads", category: "cardio")
        let press = exercise(12, "Bench Press", "chest", category: "compound")
        let squat = exercise(13, "Back Squat", "quads", category: "compound")
        let strength = routine(21, "Push Day")
        let rows = [routineRow(strength, press, position: 1),
                    routineRow(strength, squat, position: 2),
                    routineRow(strength, bike, position: 3)]

        XCTAssertFalse(WeeklyGoalProgressMath.sessionCounts(
            towardType: "cardio", session: sessionOf(strength),
            routines: [strength.id: strength],
            routineExercises: [strength.id: rows],
            catalog: catalog([bike, press, squat]), calendar: testCalendar),
            "five minutes on the bike does not make a strength day a cardio day")
    }

    func testHiitCountsOnTheRoutineNameBecauseItHasNoCategory() {
        let burpee = exercise(14, "Burpee", "legs", category: "compound")
        let hiit = routine(22, "Saturday HIIT Blast")
        let rows = [routineRow(hiit, burpee, position: 1)]

        XCTAssertTrue(WeeklyGoalProgressMath.sessionCounts(
            towardType: "hiit", session: sessionOf(hiit),
            routines: [hiit.id: hiit], routineExercises: [hiit.id: rows],
            catalog: catalog([burpee]), calendar: testCalendar),
            "hiit has no category — the name is the only signal")
        XCTAssertFalse(WeeklyGoalProgressMath.sessionCounts(
            towardType: "class", session: sessionOf(hiit),
            routines: [hiit.id: hiit], routineExercises: [hiit.id: rows],
            catalog: catalog([burpee]), calendar: testCalendar))
    }

    func testNameMatchIsCaseInsensitive() {
        let stretch = exercise(15, "Hip Opener", "hip_flexors", category: "mobility")
        let named = routine(23, "SUNDAY MOBILITY")
        XCTAssertTrue(WeeklyGoalProgressMath.sessionCounts(
            towardType: "mobility", session: sessionOf(named),
            routines: [named.id: named],
            routineExercises: [named.id: [routineRow(named, stretch, position: 1)]],
            catalog: catalog([stretch]), calendar: testCalendar))
    }

    /// Health workouts are matched to a session by its OWN WINDOW, not by
    /// calendar day. Keyed by day, one Saturday run promoted every session
    /// that Saturday: two lifting sessions credited toward a `cardio` goal,
    /// and neither of them was the run.
    private func healthTag(_ type: String, minutesFromWednesday offset: Int,
                           lengthMinutes: Int = 40) -> HealthWorkoutTag {
        let start = wednesday.addingTimeInterval(TimeInterval(offset * 60))
        return HealthWorkoutTag(type: type, start: start,
                                end: start.addingTimeInterval(TimeInterval(lengthMinutes * 60)))
    }

    func testHealthKitWorkoutOverlappingTheSessionOutranksTheInference() {
        let press = exercise(12, "Bench Press", "chest", category: "compound")
        let strength = routine(21, "Push Day")
        let pushSession = sessionOf(strength)   // startedAt == completedAt == noon

        XCTAssertTrue(WeeklyGoalProgressMath.sessionCounts(
            towardType: "cardio", session: pushSession,
            routines: [strength.id: strength],
            routineExercises: [strength.id: [routineRow(strength, press, position: 1)]],
            catalog: catalog([press]),
            healthWorkouts: [healthTag("cardio", minutesFromWednesday: -10)],
            calendar: testCalendar),
            "a real HealthKit workout over this session's own window is fact")
    }

    func testHealthKitWorkoutElsewhereInTheDayDoesNotPromoteASession() {
        let press = exercise(12, "Bench Press", "chest", category: "compound")
        let strength = routine(21, "Push Day")
        let pushSession = sessionOf(strength)   // noon

        XCTAssertFalse(WeeklyGoalProgressMath.sessionCounts(
            towardType: "cardio", session: pushSession,
            routines: [strength.id: strength],
            routineExercises: [strength.id: [routineRow(strength, press, position: 1)]],
            catalog: catalog([press]),
            // A 7 a.m. run, five hours before the lift. Same day, different
            // training — it must not make a push day into a cardio session.
            healthWorkouts: [healthTag("cardio", minutesFromWednesday: -300)],
            calendar: testCalendar),
            "the day is not the window: a morning run does not promote an evening lift")
    }

    func testHealthKitToleranceCoversClockSkewAtTheEdges() {
        let press = exercise(12, "Bench Press", "chest", category: "compound")
        let strength = routine(21, "Push Day")
        let pushSession = sessionOf(strength)

        // Ends 10 minutes BEFORE the session's instant — inside the 15-minute
        // tolerance, because the watch closes its workout on its own clock
        // and the lifter taps Finish a few minutes later.
        XCTAssertTrue(WeeklyGoalProgressMath.sessionCounts(
            towardType: "cardio", session: pushSession,
            routines: [strength.id: strength], routineExercises: [:],
            catalog: [:],
            healthWorkouts: [healthTag("cardio", minutesFromWednesday: -50,
                                       lengthMinutes: 40)],
            calendar: testCalendar))

        // Ends 20 minutes before — outside it.
        XCTAssertFalse(WeeklyGoalProgressMath.sessionCounts(
            towardType: "cardio", session: pushSession,
            routines: [strength.id: strength], routineExercises: [:],
            catalog: [:],
            healthWorkouts: [healthTag("cardio", minutesFromWednesday: -60,
                                       lengthMinutes: 40)],
            calendar: testCalendar))
    }

    func testHealthKitWorkoutOfADifferentTypeDoesNotMatch() {
        let strength = routine(21, "Push Day")
        XCTAssertFalse(WeeklyGoalProgressMath.sessionCounts(
            towardType: "cardio", session: sessionOf(strength),
            routines: [strength.id: strength], routineExercises: [:], catalog: [:],
            healthWorkouts: [healthTag("mobility", minutesFromWednesday: 0)],
            calendar: testCalendar))
    }

    /// THE LIMITATION, MADE EXPLICIT. The count's spine is app sessions, so
    /// a run recorded only on a watch cannot move a `cardio` goal by itself
    /// — it can only corroborate a session the app already has.
    func testHealthWorkoutWithNoAppSessionCountsNothing() {
        let progress = WeeklyGoalProgressMath.sessionsOfTypeProgress(
            goal: goal(.sessionsOfType, params: .init(sessionType: "cardio", count: 3)),
            sessions: [],                       // the athlete logged nothing in the app
            routines: [:], routineExercises: [:], catalog: [:],
            healthWorkouts: [healthTag("cardio", minutesFromWednesday: 0),
                             healthTag("cardio", minutesFromWednesday: -1440)],
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 0,
                       "two real Health runs, no app sessions, and the count is 0 — documented, not accidental")
    }

    func testTheNameMatchIsAWordNotASubstring() {
        // "old-school classic".contains("class") is true, and a routine
        // called Classic is not a class.
        let classic = routine(25, "Old-School Classic")
        XCTAssertFalse(WeeklyGoalProgressMath.sessionCounts(
            towardType: "class", session: sessionOf(classic),
            routines: [classic.id: classic], routineExercises: [:], catalog: [:],
            calendar: testCalendar),
            "a substring match let Classic satisfy a class goal outright")

        let realClass = routine(26, "Tuesday Spin Class")
        XCTAssertTrue(WeeklyGoalProgressMath.sessionCounts(
            towardType: "class", session: sessionOf(realClass),
            routines: [realClass.id: realClass], routineExercises: [:], catalog: [:],
            calendar: testCalendar),
            "and the word itself still matches")
    }

    func testNameWordsSplitsOnEverythingThatIsNotAlphanumeric() {
        XCTAssertEqual(WeeklyGoalProgressMath.nameWords("Old-School Classic"),
                       ["old", "school", "classic"])
        XCTAssertEqual(WeeklyGoalProgressMath.nameWords("Saturday HIIT Blast"),
                       ["saturday", "hiit", "blast"])
        XCTAssertEqual(WeeklyGoalProgressMath.nameWords("Coach · Pull A"),
                       ["coach", "pull", "a"],
                       "the Coach routine prefix's middle dot is a separator, not a word")
    }

    func testSessionWithNoRoutineCountsNothing() {
        XCTAssertFalse(WeeklyGoalProgressMath.sessionCounts(
            towardType: "cardio", session: sessionOf(nil),
            routines: [:], routineExercises: [:], catalog: [:],
            calendar: testCalendar),
            "a freestyle session carries no type signal at all")
    }

    func testSessionWithTwoMatchingSignalsIsCountedOnce() {
        let bike = exercise(10, "Assault Bike", "quads", category: "cardio")
        // Named "Cardio" AND all-cardio by category — two signals, one session.
        let both = routine(24, "Cardio Engine")
        let rows = [routineRow(both, bike, position: 1)]
        let progress = WeeklyGoalProgressMath.sessionsOfTypeProgress(
            goal: goal(.sessionsOfType, params: .init(sessionType: "cardio", count: 3)),
            sessions: [sessionOf(both)], routines: [both.id: both],
            routineExercises: [both.id: rows], catalog: catalog([bike]),
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 1, "sessions are counted, not signals")
        XCTAssertEqual(progress.target, 3)
        XCTAssertFalse(progress.met)
    }

    func testSessionsOfTypeIgnoresOtherWeeks() {
        let bike = exercise(10, "Assault Bike", "quads", category: "cardio")
        let cardio = routine(24, "Cardio Engine")
        let rows = [routineRow(cardio, bike, position: 1)]
        let progress = WeeklyGoalProgressMath.sessionsOfTypeProgress(
            goal: goal(.sessionsOfType, params: .init(sessionType: "cardio", count: 2)),
            sessions: [sessionOf(cardio, dayOffset: 0),
                       sessionOf(cardio, dayOffset: -4)],   // last week
            routines: [cardio.id: cardio], routineExercises: [cardio.id: rows],
            catalog: catalog([bike]), now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 1)
    }

    func testSessionsOfTypeMetFlipsTheKicker() {
        let bike = exercise(10, "Assault Bike", "quads", category: "cardio")
        let cardio = routine(24, "Cardio Engine")
        let rows = [routineRow(cardio, bike, position: 1)]
        let progress = WeeklyGoalProgressMath.sessionsOfTypeProgress(
            goal: goal(.sessionsOfType, params: .init(sessionType: "cardio", count: 2)),
            sessions: [sessionOf(cardio, dayOffset: 0),
                       sessionOf(cardio, dayOffset: -1)],
            routines: [cardio.id: cardio], routineExercises: [cardio.id: rows],
            catalog: catalog([bike]), now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.met)
        XCTAssertEqual(progress.kicker, "GOAL MET · 4 DAYS LEFT")
    }

    func testSessionsOfTypeWithNoCountIsNotMet() {
        let progress = WeeklyGoalProgressMath.sessionsOfTypeProgress(
            goal: goal(.sessionsOfType, params: .init(sessionType: "cardio")),
            sessions: [], routines: [:], routineExercises: [:], catalog: [:],
            now: wednesday, calendar: testCalendar)

        XCTAssertFalse(progress.met, "0 of 0 is a goal that was never finished being set")
    }

    func testDispatcherRoutesSessionsOfType() {
        let bike = exercise(10, "Assault Bike", "quads", category: "cardio")
        let cardio = routine(24, "Cardio Engine")
        let progress = WeeklyGoalProgressMath.progress(
            goal: goal(.sessionsOfType, params: .init(sessionType: "cardio", count: 3)),
            logs: [], catalog: catalog([bike]), sessions: [sessionOf(cardio)],
            effectiveWeeklyGoal: 3,
            routines: [cardio.id: cardio],
            routineExercises: [cardio.id: [routineRow(cardio, bike, position: 1)]],
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 1)
        XCTAssertEqual(progress.target, 3)
    }

    // MARK: - A7: distance

    private func distanceGoal(_ activity: String, target: Double) -> WeeklyGoal {
        goal(.distance, params: .init(activity: activity, distanceTarget: target))
    }

    func testDistanceConvertsMetresToMilesWithPounds() {
        // 15 000 m = 9.3206 mi against a 15 mi target.
        let progress = WeeklyGoalProgressMath.distanceProgress(
            goal: distanceGoal("run", target: 15), metres: 15_000, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 9.3206, accuracy: 0.001)
        XCTAssertEqual(progress.target, 15)
        XCTAssertEqual(progress.unitLabel, "mi")
        XCTAssertFalse(progress.met)
    }

    func testDistanceConvertsMetresToKilometresWithKilograms() {
        let progress = WeeklyGoalProgressMath.distanceProgress(
            goal: distanceGoal("run", target: 20), metres: 15_000, unit: .kg,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 15, accuracy: 0.0001)
        XCTAssertEqual(progress.unitLabel, "km")
    }

    func testDistanceUnitFollowsTheWeightSetting() {
        XCTAssertEqual(WeeklyGoalProgressMath.distanceUnitLabel(.lbs), "mi")
        XCTAssertEqual(WeeklyGoalProgressMath.distanceUnitLabel(.kg), "km")
        XCTAssertEqual(WeeklyGoalProgressMath.distanceValue(metres: 1609.344, unit: .lbs),
                       1, accuracy: 0.000_001, "the mile is defined, not measured")
        XCTAssertEqual(WeeklyGoalProgressMath.distanceValue(metres: 1000, unit: .kg),
                       1, accuracy: 0.000_001)
    }

    func testDistanceDeniedOrEmptyReadsZeroNotNil() {
        // HealthKit never discloses a read denial, so "denied" and "no data"
        // are the same 0 metres — and the strip must render 0 / 15 mi.
        let progress = WeeklyGoalProgressMath.distanceProgress(
            goal: distanceGoal("run", target: 15), metres: 0, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 0)
        XCTAssertEqual(progress.target, 15)
        XCTAssertFalse(progress.met)
        XCTAssertEqual(progress.rightHandRead, "4 DAYS LEFT")
    }

    func testDistanceMetFlipsTheKicker() {
        let progress = WeeklyGoalProgressMath.distanceProgress(
            goal: distanceGoal("run", target: 9), metres: 15_000, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.met)
        XCTAssertEqual(progress.kicker, "GOAL MET · 4 DAYS LEFT")
    }

    func testDistanceWithNoTargetIsNotMet() {
        let progress = WeeklyGoalProgressMath.distanceProgress(
            goal: goal(.distance, params: .init(activity: "run")),
            metres: 15_000, unit: .lbs, now: wednesday, calendar: testCalendar)

        XCTAssertFalse(progress.met, "0 target is a goal never finished being set")
    }

    func testDistanceNeverGoesNegative() {
        let progress = WeeklyGoalProgressMath.distanceProgress(
            goal: distanceGoal("run", target: 15), metres: -500, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 0)
    }

    // MARK: - The subject-chip contract (Stream C, controller 2026-09-06)

    func testDistanceEmitsOneSubjectChipNamedForTheActivity() {
        let progress = WeeklyGoalProgressMath.distanceProgress(
            goal: distanceGoal("bike", target: 15), metres: 15_000, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.chips.count, 1)
        XCTAssertEqual(progress.chips[0].name, "BIKE",
                       "the strip picks figure.outdoor.cycle from this name")
        XCTAssertEqual(progress.chips[0].done, progress.value)
        XCTAssertEqual(progress.chips[0].target, progress.target)
        XCTAssertFalse(progress.chips[0].isNext)
    }

    func testSessionsOfTypeEmitsOneSubjectChipNamedForTheType() {
        let bike = exercise(10, "Assault Bike", "quads", category: "cardio")
        let cardio = routine(24, "Cardio Engine")
        let progress = WeeklyGoalProgressMath.sessionsOfTypeProgress(
            goal: goal(.sessionsOfType, params: .init(sessionType: "hiit", count: 3)),
            sessions: [sessionOf(cardio)], routines: [cardio.id: cardio],
            routineExercises: [cardio.id: [routineRow(cardio, bike, position: 1)]],
            catalog: catalog([bike]), now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.chips.count, 1)
        XCTAssertEqual(progress.chips[0].name, "HIIT",
                       "the strip prints this noun after the count")
        XCTAssertEqual(progress.chips[0].target, 3)
    }

    func testLiftSubjectChipIsNamedForTheExercise() {
        let squat = exercise(5, "Back Squat", "quads")
        let progress = WeeklyGoalProgressMath.progress(
            goal: liftGoal(squat, targetLbs: 225), logs: [],
            catalog: catalog([squat]), sessions: [], effectiveWeeklyGoal: 3,
            blockLogs: [liftLog(squat, weight: 190, reps: 5)],
            blockStartLbs: 200, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.chips[0].name, "Back Squat",
                       "the dispatcher reads the name out of the catalog it already has")
    }

    func testDaysEmitsSevenChipsInTheDeviceCalendarsWeekOrder() {
        // firstWeekday 1 → the week runs Sunday…Saturday.
        let progress = WeeklyGoalProgressMath.daysProgress(
            goal: goal(.days), sessions: [], effectiveWeeklyGoal: 4,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.chips.count, 7)
        XCTAssertEqual(progress.chips.map(\.name), ["S", "M", "T", "W", "T", "F", "S"])
    }

    func testDaysChipsMarkTrainedBookedAndToday() {
        let sessions = [
            session(completedDaysFromWednesday: -1),                 // Tuesday, trained
            scheduledSession(dayOffset: 2),                          // Friday, booked
        ]
        let progress = WeeklyGoalProgressMath.daysProgress(
            goal: goal(.days), sessions: sessions, effectiveWeeklyGoal: 4,
            now: wednesday, calendar: testCalendar)

        // Sun Mon Tue Wed Thu Fri Sat  →  index 2 = Tuesday, 3 = Wednesday, 5 = Friday
        XCTAssertEqual(progress.chips[2].done, 1, "Tuesday was trained")
        XCTAssertEqual(progress.chips[2].target, 1, "a trained day counts as booked too")
        XCTAssertEqual(progress.chips[5].done, 0, "Friday has not happened")
        XCTAssertEqual(progress.chips[5].target, 1, "Friday is on the books")
        XCTAssertEqual(progress.chips[0].done, 0)
        XCTAssertEqual(progress.chips[0].target, 0, "Sunday is neither")

        let today = progress.chips.filter(\.isNext)
        XCTAssertEqual(today.count, 1, "exactly one chip is today")
        XCTAssertEqual(progress.chips[3].isNext, true, "and it is Wednesday")
    }

    func testDaysChipDoneNeverExceedsItsTarget() {
        let progress = WeeklyGoalProgressMath.daysProgress(
            goal: goal(.days),
            sessions: [session(completedDaysFromWednesday: 0)],
            effectiveWeeklyGoal: 4, now: wednesday, calendar: testCalendar)

        XCTAssertTrue(progress.chips.allSatisfy { $0.done <= $0.target })
    }

    func testMetGoalsLeaveTheRightHandReadEmpty() {
        // The met kicker already ends in "{n} DAYS LEFT"; printing it twice
        // on one line is the defect this rule closes.
        let bench = exercise(1, "Bench Press", "chest")
        let muscleSets = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets, params: .init(muscleTargets: ["chest": 2])),
            logs: [log(bench, reps: 8), log(bench, reps: 8, index: 2)],
            catalog: catalog([bench]), now: wednesday, calendar: testCalendar)
        let days = WeeklyGoalProgressMath.daysProgress(
            goal: goal(.days), sessions: [session(completedDaysFromWednesday: 0)],
            effectiveWeeklyGoal: 1, now: wednesday, calendar: testCalendar)
        let distance = WeeklyGoalProgressMath.distanceProgress(
            goal: distanceGoal("run", target: 1), metres: 15_000, unit: .lbs,
            now: wednesday, calendar: testCalendar)

        XCTAssertTrue(muscleSets.met)
        XCTAssertEqual(muscleSets.rightHandRead, "")
        XCTAssertTrue(days.met)
        XCTAssertEqual(days.rightHandRead, "")
        XCTAssertTrue(distance.met)
        XCTAssertEqual(distance.rightHandRead, "")
        XCTAssertEqual(days.kicker, "GOAL MET · 4 DAYS LEFT",
                       "the kicker still carries the number")
    }

    // MARK: - CONNECT HEALTH (controller ruling, 2026-09-06)

    func testDistanceSaysConnectHealthRatherThanZeroMiles() {
        // The failure this closes: a permission never asked for returns 0
        // metres, and `0 / 15 mi` then says "you have not run" when the
        // truth is "nobody ever asked you".
        let progress = WeeklyGoalProgressMath.distanceProgress(
            goal: distanceGoal("run", target: 15), metres: 0, unit: .lbs,
            healthNeedsConnecting: true, now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.rightHandRead, "CONNECT HEALTH")
        XCTAssertEqual(progress.value, 0)
        XCTAssertEqual(progress.chips.first?.done, 0)
        XCTAssertFalse(progress.met)
    }

    func testDistanceNeverReadsMetWhileHealthIsUnconnected() {
        // Metres cannot arrive while unconnected, but if they somehow did,
        // an unconnected strip must not claim the goal was met.
        let progress = WeeklyGoalProgressMath.distanceProgress(
            goal: distanceGoal("run", target: 1), metres: 15_000, unit: .lbs,
            healthNeedsConnecting: true, now: wednesday, calendar: testCalendar)

        XCTAssertFalse(progress.met)
        XCTAssertEqual(progress.value, 0)
    }

    func testConnectedDistanceReadsNormally() {
        let progress = WeeklyGoalProgressMath.distanceProgress(
            goal: distanceGoal("run", target: 15), metres: 15_000, unit: .lbs,
            healthNeedsConnecting: false, now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.rightHandRead, "4 DAYS LEFT")
        XCTAssertEqual(progress.value, 9.3206, accuracy: 0.001)
    }

    func testSessionsOfTypeSaysConnectHealthButKeepsItsRealCount() {
        // DELIBERATE DEVIATION from the ruling's "chips with done 0", and
        // the reason is the ruling's own: this count's spine is the app's
        // OWN completed sessions, so zeroing it would render a false 0 for
        // data this app recorded itself.
        let bike = exercise(10, "Assault Bike", "quads", category: "cardio")
        let cardio = routine(24, "Cardio Engine")
        let progress = WeeklyGoalProgressMath.sessionsOfTypeProgress(
            goal: goal(.sessionsOfType, params: .init(sessionType: "cardio", count: 3)),
            sessions: [sessionOf(cardio)], routines: [cardio.id: cardio],
            routineExercises: [cardio.id: [routineRow(cardio, bike, position: 1)]],
            catalog: catalog([bike]), healthNeedsConnecting: true,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.rightHandRead, "CONNECT HEALTH")
        XCTAssertEqual(progress.value, 1,
                       "the app's own completed session is real and stays counted")
    }

    func testDispatcherCarriesTheConnectHealthFlag() {
        let progress = WeeklyGoalProgressMath.progress(
            goal: distanceGoal("run", target: 15), logs: [], catalog: [:],
            sessions: [], effectiveWeeklyGoal: 3, unit: .lbs,
            healthNeedsConnecting: true, distanceMetres: 0,
            now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.rightHandRead, "CONNECT HEALTH")
    }

    func testDispatcherRoutesDistance() {
        let progress = WeeklyGoalProgressMath.progress(
            goal: distanceGoal("run", target: 15), logs: [], catalog: [:],
            sessions: [], effectiveWeeklyGoal: 3, unit: .lbs,
            distanceMetres: 15_000, now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.value, 9.3206, accuracy: 0.001)
        XCTAssertEqual(progress.unitLabel, "mi")
    }
}
