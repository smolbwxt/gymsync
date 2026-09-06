import XCTest
@testable import GymSync

/// The weekly goal's data contract (plan task 0.2). Three things here can
/// break silently and each has a test:
///
/// 1. `WeeklyGoalParams` is ONE payload for five kinds, persisted as a
///    single `params jsonb`. A kind's keys leaking into another kind's row
///    (as nulls, or worse as stale values) would make the column lie about
///    what the goal is.
/// 2. `WeekMath` is the ONE definition of "this week" on Home — the design's
///    agreement law. If it and `HomeView.daysThisWeek`'s
///    `isDate(_:equalTo:toGranularity: .weekOfYear)` ever classify a date
///    differently, the goal strip and the streak tile tell two stories about
///    one week.
/// 3. The stub is what four streams build and capture against, so its
///    numbers are a fixture with a test, not an implementation detail.
final class WeeklyGoalModelTests: XCTestCase {

    // MARK: - Params round-trip, per kind

    /// Encodes `params` and returns the raw JSON object, so the assertions
    /// can talk about KEYS rather than about a decoded struct — "absent, not
    /// null" is invisible after decoding.
    private func jsonObject(_ params: WeeklyGoalParams) throws -> [String: Any] {
        let data = try JSONEncoder().encode(params)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func assertRoundTrips(_ params: WeeklyGoalParams,
                                  keys expected: Set<String>,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) throws {
        let object = try jsonObject(params)
        XCTAssertEqual(Set(object.keys), expected,
                       "params carried keys it should not have", file: file, line: line)

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(WeeklyGoalParams.self, from: data)
        XCTAssertEqual(decoded, params, file: file, line: line)
    }

    func testMuscleSetsParamsCarryOnlyTheirOwnKeys() throws {
        try assertRoundTrips(
            WeeklyGoalParams(muscleTargets: ["chest": 12, "back": 12], targetSource: "routines"),
            keys: ["muscleTargets", "targetSource"])
    }

    func testDistanceParamsCarryOnlyTheirOwnKeys() throws {
        try assertRoundTrips(
            WeeklyGoalParams(activity: "run", distanceTarget: 15),
            keys: ["activity", "distanceTarget"])
    }

    func testSessionsOfTypeParamsCarryOnlyTheirOwnKeys() throws {
        try assertRoundTrips(
            WeeklyGoalParams(sessionType: "hiit", count: 3),
            keys: ["sessionType", "count"])
    }

    func testDaysParamsCarryOnlyTheirOwnKeys() throws {
        try assertRoundTrips(WeeklyGoalParams(count: 4), keys: ["count"])
    }

    func testLiftParamsCarryOnlyTheirOwnKeys() throws {
        let params = WeeklyGoalParams(exerciseID: UUID(),
                                      targetWeightLbs: Decimal(225),
                                      byDate: Date(timeIntervalSince1970: 1_788_696_000))
        try assertRoundTrips(params, keys: ["exerciseID", "targetWeightLbs", "byDate"])
    }

    func testEmptyParamsEncodeToAnEmptyObject() throws {
        let object = try jsonObject(WeeklyGoalParams())
        XCTAssertTrue(object.isEmpty, "an unset field must be ABSENT, never null")
    }

    /// The `kind` column's CHECK constraint (`weekly_goals`, Stream A task
    /// A1) is written against these exact strings.
    func testKindRawValuesMatchTheColumnsCheckConstraint() {
        XCTAssertEqual(Set(WeeklyGoalKind.allCases.map(\.rawValue)),
                       ["muscle_sets", "distance", "sessions_of_type", "days", "lift"])
        XCTAssertEqual(WeeklyGoalSource.coach.rawValue, "coach")
        XCTAssertEqual(WeeklyGoalSource.user.rawValue, "user")
    }

    func testGoalIDIsUserPlusWeek() {
        let user = UUID()
        let goal = WeeklyGoal(userID: user,
                              weekStartString: "2026-09-07",
                              kind: .days,
                              params: WeeklyGoalParams(count: 4),
                              source: .coach,
                              setAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(goal.id, "\(user.uuidString)-2026-09-07")
    }

    // MARK: - WeekMath

    private func calendar(firstWeekday: Int, timeZone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZone))
        return calendar
    }

    /// US DST starts 2026-03-08 (a Sunday). Every day of the week
    /// containing it must produce the SAME week-start string — a formatter
    /// that drifted an hour would move the day across the boundary.
    func testWeekStartStringIsStableAcrossADSTBoundary() throws {
        let calendar = try self.calendar(firstWeekday: 1, timeZone: "America/New_York")
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))

        var strings: Set<String> = []
        for offset in 0..<7 {
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: sunday))
            strings.insert(WeekMath.weekStartString(day, calendar: calendar))
        }
        XCTAssertEqual(strings, ["2026-03-08"])
    }

    /// Southern-hemisphere DST too, in the other direction, with a Monday
    /// week: Sydney's clocks go BACK on Sunday 2026-04-05, which is the last
    /// day of the week starting Monday 2026-03-30.
    func testWeekStartStringIsStableAcrossASouthernDSTBoundary() throws {
        let calendar = try self.calendar(firstWeekday: 2, timeZone: "Australia/Sydney")
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 30)))

        var strings: Set<String> = []
        for offset in 0..<7 {
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: monday))
            strings.insert(WeekMath.weekStartString(day, calendar: calendar))
        }
        XCTAssertEqual(strings, ["2026-03-30"])
    }

    /// THE AGREEMENT LAW. `WeekMath`'s week and the week
    /// `HomeView.daysThisWeek` counts must classify the same dates
    /// identically, under both of the `firstWeekday` values that actually
    /// ship (1 = Sunday, US default; 2 = Monday, most of the rest). Tested
    /// on consecutive day pairs across a full year, which is where a
    /// disagreement could only ever appear: the week boundary.
    func testWeekAgreesWithHomeViewsWeekOfYearGranularity() throws {
        for firstWeekday in [1, 2] {
            let calendar = try self.calendar(firstWeekday: firstWeekday, timeZone: "America/New_York")
            var day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

            for _ in 0..<365 {
                let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
                let byGranularity = calendar.isDate(day, equalTo: next, toGranularity: .weekOfYear)
                let byWeekMath = WeekMath.startOfWeek(day, calendar: calendar)
                    == WeekMath.startOfWeek(next, calendar: calendar)
                XCTAssertEqual(byGranularity, byWeekMath,
                               "firstWeekday \(firstWeekday): disagreement at \(day) -> \(next)")
                day = next
            }
        }
    }

    func testDaysRemainingCountsTodayAndStopsAtTheWeeksEnd() throws {
        let calendar = try self.calendar(firstWeekday: 1, timeZone: "America/New_York")
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))

        for offset in 0..<7 {
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: sunday))
            XCTAssertEqual(WeekMath.daysRemaining(in: sunday, from: day, calendar: calendar),
                           7 - offset)
        }
    }

    func testDaysRemainingNeverGoesNegative() throws {
        let calendar = try self.calendar(firstWeekday: 1, timeZone: "America/New_York")
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6)))
        let nextMonth = try XCTUnwrap(calendar.date(byAdding: .day, value: 30, to: sunday))
        XCTAssertEqual(WeekMath.daysRemaining(in: sunday, from: nextMonth, calendar: calendar), 0)
    }

    // MARK: - The stub

    /// The stub is a fixture four streams capture against; its numbers are
    /// the contract, not an implementation detail.
    func testStubReturnsTheDesignsFixtureGoal() async throws {
        let repository = StubWeeklyGoalRepository()
        // `XCTUnwrap` takes an autoclosure, and Swift forbids `await` inside
        // one ('async call in an autoclosure that does not support
        // concurrency'), so the fetch is bound first and unwrapped second.
        let fetched = await repository.goal(weekStart: "2026-09-06")
        let goal = try XCTUnwrap(fetched)

        XCTAssertEqual(goal.kind, .muscleSets)
        XCTAssertEqual(goal.source, .coach)
        XCTAssertEqual(goal.weekStartString, "2026-09-06")
        XCTAssertEqual(goal.params.muscleTargets,
                       ["chest": 12, "back": 12, "legs": 12, "arms": 8])

        let progress = await repository.progress(for: goal)
        XCTAssertEqual(progress.chips.map(\.name), ["CHEST", "BACK", "LEGS", "ARMS"])
        XCTAssertEqual(progress.chips.map(\.done), [8, 10, 6, 8])
        XCTAssertEqual(progress.chips.map(\.target), [12, 12, 12, 8])
        XCTAssertEqual(progress.chips.map(\.isNext), [false, false, true, false])
        XCTAssertEqual(progress.rightHandRead, "1 SESSION LEFT")
        XCTAssertEqual(progress.kicker, "THIS WEEK · COACH'S GOAL")
        XCTAssertFalse(progress.met)
    }

    /// Exactly one chip may be `isNext` — the accent ring is an invitation
    /// to ONE thing, and two of them says nothing.
    func testStubHasExactlyOneNextChip() {
        XCTAssertEqual(StubWeeklyGoalRepository.fixtureChips.filter(\.isNext).count, 1)
    }

    func testStubIsDeterministic() async {
        let repository = StubWeeklyGoalRepository()
        let first = await repository.goal(weekStart: "2026-09-06")
        let second = await repository.goal(weekStart: "2026-09-06")
        XCTAssertEqual(first, second)
    }

    /// A user-set goal reads as the user's on the strip. The stub never
    /// stores one, but the kicker branch is the copy contract Stream C's
    /// editor lands against.
    func testUserSourcedGoalGetsTheUsersKicker() async {
        let repository = StubWeeklyGoalRepository()
        let goal = WeeklyGoal(userID: StubWeeklyGoalRepository.fixtureUserID,
                              weekStartString: "2026-09-06",
                              kind: .muscleSets,
                              params: WeeklyGoalParams(),
                              source: .user,
                              setAt: StubWeeklyGoalRepository.fixtureSetAt)
        let progress = await repository.progress(for: goal)
        XCTAssertEqual(progress.kicker, "THIS WEEK · YOUR GOAL")
    }
}
