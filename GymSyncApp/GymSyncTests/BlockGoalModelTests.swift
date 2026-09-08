import XCTest
@testable import GymSync

/// The goal model's wire contract. `block_goals.target` is jsonb with
/// CAMELCASE keys and no `keyEncodingStrategy` (global constraint 11), and
/// absent fields must be ABSENT rather than null — the same round trip
/// `WeeklyGoalModelTests` proves for `weekly_goals.params`.
final class BlockGoalModelTests: XCTestCase {

    private func json(_ target: GoalTarget) throws -> [String: Any] {
        let data = try JSONEncoder().encode(target)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTargetEncodesOnlyTheFieldsAMetricUses() throws {
        let days = try json(GoalTarget(days: 4))
        XCTAssertEqual(days.keys.sorted(), ["days"])

        let lift = try json(GoalTarget(exerciseID: UUID(), targetWeightLbs: 225))
        XCTAssertEqual(lift.keys.sorted(), ["exerciseID", "targetWeightLbs"])

        let recovery = try json(GoalTarget(lissMinutes: 120, stretchingExercises: 6))
        XCTAssertEqual(recovery.keys.sorted(), ["lissMinutes", "stretchingExercises"])
    }

    func testTargetRoundTripsEveryField() throws {
        let full = GoalTarget(
            exerciseID: UUID(), targetWeightLbs: 225, targetReps: 10, loadLbs: 225,
            muscleTargets: ["chest": 12, "back": 12], activity: "run", distance: 15,
            days: 4, sessionType: "hiit", sessions: 3, lissMinutes: 120,
            stretchingExercises: 6, bodyWeightLbs: 180, bodyWeightRatePercent: -0.75,
            volumeLbs: 100_000, routineID: UUID(), targetSeconds: 2700)
        let data = try JSONEncoder().encode(full)
        XCTAssertEqual(try JSONDecoder().decode(GoalTarget.self, from: data), full)
    }

    func testEveryMetricKeyIsSnakeCaseAndUnique() {
        let keys = GoalMetric.allCases.map(\.rawValue)
        XCTAssertEqual(keys.count, Set(keys).count, "duplicate registry key")
        for key in keys {
            XCTAssertEqual(key, key.lowercased(), "registry keys are lowercase: \(key)")
            XCTAssertFalse(key.contains(" "), "registry keys have no spaces: \(key)")
        }
    }

    func testEveryPresetHasAMetricAndTenTilesAreOffered() {
        XCTAssertEqual(GoalPreset.allCases.count, 11)
        XCTAssertEqual(GoalPreset.tiles.count, 10)
        XCTAssertFalse(GoalPreset.tiles.contains(.repStrength),
                       "rep strength is Strength's second lever, not a tile (spec §2.3)")
        XCTAssertEqual(GoalPreset.strength.metric, .liftOneRepMax)
        XCTAssertEqual(GoalPreset.maintenance.metric, .weeklyMuscleSets)
        XCTAssertEqual(GoalPreset.recovery.metric, .stretchingExercisesPerWeek)
        XCTAssertFalse(GoalPreset.maintenance.asksForDate)
        XCTAssertFalse(GoalPreset.recovery.asksForDate)
        // The THIRD dateless preset (review finding 8): spec §2.3 gives
        // Consistency's milestone as "days per week, held for N weeks" — a
        // count held, not a date met. The code always excluded it and only
        // the comment disagreed, so nothing pinned it.
        XCTAssertFalse(GoalPreset.consistency.asksForDate)
        XCTAssertTrue(GoalPreset.strength.asksForDate)
        XCTAssertEqual(GoalPreset.allCases.filter { !$0.asksForDate }.count, 3,
                       "exactly three presets are held rather than dated")
    }

    func testDraftBecomesAGoalWithItsEnrollment() {
        let userID = UUID()
        let enrollmentID = UUID()
        let now = Date(timeIntervalSince1970: 1_788_696_000)
        let draft = BlockGoalDraft(metric: .liftOneRepMax,
                                   target: GoalTarget(targetWeightLbs: 225),
                                   byDate: now, preset: .strength)
        let goal = BlockGoal(draft: draft, userID: userID,
                             enrollmentID: enrollmentID, now: now)
        XCTAssertEqual(goal.enrollmentID, enrollmentID)
        XCTAssertEqual(goal.source, .user, "the door is the athlete choosing")
        XCTAssertEqual(goal.createdAt, now)
        XCTAssertEqual(goal.updatedAt, now)
        XCTAssertNil(goal.outcome)
    }

    // MARK: - The stub (task 0.4)

    func testTheStubIsHermeticAndConsistent() async {
        let repository = StubBlockGoalRepository()
        let goal = await repository.activeGoal()
        let ladder = await repository.ladder(goalID: StubBlockGoalRepository.fixtureGoalID)
        let page = await repository.page(goalID: StubBlockGoalRepository.fixtureGoalID)

        XCTAssertEqual(goal?.id, StubBlockGoalRepository.fixtureGoalID)
        XCTAssertEqual(ladder?.rungs.count, 8, "eight rungs for an eight-week block")
        XCTAssertEqual(page?.rows.count, ladder?.rungs.count,
                       "the page has one row per rung — the fixtures cannot describe two blocks")
        XCTAssertEqual(page?.weekCount, ladder?.rungs.count)
        XCTAssertEqual(ladder?.rungs.filter { $0.status == .current }.count, 1,
                       "exactly one current rung")
        XCTAssertEqual(page?.rows.filter(\.isDeload).count, 1,
                       "the wave's deload is a rung, not smoothed away")
    }

    /// THE FIXTURE'S DATES ARE PART OF ITS CONTRACT (controller ruling 3),
    /// and until this test existed nothing checked them: both were epoch
    /// literals, both were wrong — the created-at by two days, the milestone
    /// by one — and both had been restated as prose in the stub's own doc
    /// block. The page hard-codes `Sunday 18 October`, so the first stream to
    /// format `fixtureGoal.byDate` instead would have rendered "Monday 19
    /// October" beside a headline saying "Oct 18", and its formatter would
    /// have taken the blame.
    ///
    /// UTC, because that is the calendar the fixture is built in — reading it
    /// through a device-local calendar would make this test's answer depend
    /// on the simulator's timezone, which is the class of thing a fixture
    /// exists to remove.
    func testTheFixtureMilestoneIsTheSundayThePageSaysItIs() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let milestone = calendar.dateComponents([.year, .month, .day, .weekday],
                                                from: StubBlockGoalRepository.fixtureByDate)
        XCTAssertEqual(milestone.year, 2026)
        XCTAssertEqual(milestone.month, 10)
        XCTAssertEqual(milestone.day, 18)
        XCTAssertEqual(milestone.weekday, 1,
                       "18 October 2026 is a SUNDAY — the page's own date line says so")
        XCTAssertEqual(StubBlockGoalRepository.fixturePage.dateLine, "Sunday 18 October")

        // A device-local read must agree with the UTC one in the timezones the
        // simulator actually runs in: the fixture is anchored at noon UTC for
        // exactly this reason (re-review of Task 0, finding 1 reopened).
        for zone in ["America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Tokyo"] {
            var local = Calendar(identifier: .gregorian)
            local.timeZone = TimeZone(identifier: zone)!
            let day = local.dateComponents([.day, .weekday], from: StubBlockGoalRepository.fixtureByDate)
            XCTAssertEqual(day.day, 18, "\(zone) must still read the 18th")
            XCTAssertEqual(day.weekday, 1, "\(zone) must still read Sunday")
        }
        XCTAssertTrue(StubBlockGoalRepository.fixturePage.headline.contains("Oct 18"),
                      "the headline and the date line must name one day")
        XCTAssertEqual(StubBlockGoalRepository.fixtureGoal.byDate,
                       StubBlockGoalRepository.fixtureByDate)

        let start = calendar.dateComponents([.year, .month, .day, .weekday],
                                            from: StubBlockGoalRepository.fixtureCreatedAt)
        XCTAssertEqual(start.year, 2026)
        XCTAssertEqual(start.month, 8)
        XCTAssertEqual(start.day, 24)
        XCTAssertEqual(start.weekday, 2, "24 August 2026 is a Monday")
    }

    /// Review finding 7: the stub's ids were `…b1/…b2/…b3`, which is
    /// `WeeklyGoalFixtures`' bench/squat/deadlift — so the stub's USER and
    /// the catalog's BENCH PRESS were the same id, and the stub's bench goal
    /// pointed at `…b4`, a lift the fixture world does not have. Ruling 3
    /// says these two fixtures describe ONE world; this pins the part of
    /// that a screenshot cannot show.
    func testTheStubsBenchGoalIsTheFixtureWorldsBenchPress() {
        XCTAssertEqual(StubBlockGoalRepository.fixtureGoal.target.exerciseID,
                       WeeklyGoalFixtures.benchPressID,
                       "a bench milestone must point at the catalog's bench press")
        XCTAssertTrue(StubBlockGoalRepository.fixturePage.headline.contains("Bench"))

        let ids: Set<UUID> = [StubBlockGoalRepository.fixtureUserID,
                              StubBlockGoalRepository.fixtureGoalID,
                              StubBlockGoalRepository.fixtureEnrollmentID]
        XCTAssertEqual(ids.count, 3, "three distinct ids")
        XCTAssertTrue(ids.isDisjoint(with: [WeeklyGoalFixtures.benchPressID,
                                            WeeklyGoalFixtures.backSquatID,
                                            WeeklyGoalFixtures.deadliftID,
                                            WeeklyGoalFixtures.editorUserID]),
                      "and none of them is one of the fixture world's lifts or its athlete")
    }
}
