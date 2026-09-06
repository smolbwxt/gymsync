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

    /// A calendar with a fixed timezone and `firstWeekday`, so "this week"
    /// is the same week on every machine that runs these.
    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
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

    func testZeroTargetGroupIsNeverNext() {
        let progress = WeeklyGoalProgressMath.muscleSetsProgress(
            goal: goal(.muscleSets, params: .init(muscleTargets: ["chest": 0, "back": 0])),
            logs: [], catalog: [:], now: wednesday, calendar: testCalendar)

        XCTAssertEqual(progress.chips.count, 2)
        XCTAssertTrue(progress.chips.allSatisfy { !$0.isNext },
                      "a 0/0 chip draws an empty meter and prompts nothing")
        XCTAssertTrue(progress.met, "0 of 0 is met, vacuously")
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

    func testDispatcherReturnsChromeForKindsNotYetImplemented() {
        for kind in [WeeklyGoalKind.distance, .sessionsOfType, .lift] {
            let progress = WeeklyGoalProgressMath.progress(
                goal: goal(kind), logs: [], catalog: [:], sessions: [],
                effectiveWeeklyGoal: 3, now: wednesday, calendar: testCalendar)

            XCTAssertEqual(progress.kicker, "THIS WEEK · COACH'S GOAL", "\(kind)")
            XCTAssertEqual(progress.rightHandRead, "4 DAYS LEFT", "\(kind)")
            XCTAssertFalse(progress.met, "\(kind) must not read as met before its math lands")
        }
    }
}
