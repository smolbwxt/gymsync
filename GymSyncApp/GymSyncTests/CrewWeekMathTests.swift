import XCTest
@testable import GymSync

/// THE CREW'S WEEK's arithmetic — owner addition of 2026-09-12, on trial in
/// the Phase A lobby.
///
/// PURE: no clock (`todayIndex` is a value), no database, no view. The four
/// cases the ruling names — ahead, on pace, behind, and the lifter with no
/// goal — plus the two series the chart draws.
final class CrewWeekMathTests: XCTestCase {

    private func lifter(_ name: String, goal: Int?, done: Int,
                        byDay: [Int]? = nil) -> CrewWeekLifter {
        CrewWeekLifter(id: UUID(), name: name, goal: goal, done: done,
                       doneByDay: byDay)
    }

    /// Plan 14, so the pace lands on whole sessions: 14 × (d+1)/7 = 2(d+1).
    /// Wednesday (index 2) puts the pace at exactly 6.
    private func wednesdayCrew(done: [Int]) -> CrewWeek {
        CrewWeek(lifters: [
            lifter("Alex Rue", goal: 4, done: done[0]),
            lifter("Dana Kord", goal: 4, done: done[1]),
            lifter("Sam Obi", goal: 3, done: done[2]),
            lifter("Lee Vance", goal: 3, done: done[3]),
        ], todayIndex: 2)
    }

    // MARK: - The three verdicts

    func testOnPaceSaysSoAndCarriesTheNoun() {
        let week = wednesdayCrew(done: [2, 2, 1, 1])   // 6 done, pace 6
        XCTAssertEqual(CrewWeekMath.planTotal(week), 14)
        XCTAssertEqual(CrewWeekMath.paceAtToday(week), 6)
        XCTAssertEqual(CrewWeekMath.delta(week), 0)
        XCTAssertEqual(CrewWeekMath.caption(week), "ON PACE · 6 OF 14 SESSIONS")
    }

    func testAheadNamesHowFar() {
        let week = wednesdayCrew(done: [3, 2, 2, 1])   // 8 done, pace 6
        XCTAssertEqual(CrewWeekMath.delta(week), 2)
        XCTAssertEqual(CrewWeekMath.caption(week), "2 AHEAD · 8 OF 14")
    }

    func testBehindNamesHowFar() {
        let week = wednesdayCrew(done: [2, 1, 1, 1])   // 5 done, pace 6
        XCTAssertEqual(CrewWeekMath.delta(week), -1)
        XCTAssertEqual(CrewWeekMath.caption(week), "1 BEHIND · 5 OF 14")
    }

    // MARK: - The lifter who set no goal

    /// They are counted in what the crew DID and excluded from what the crew
    /// PLANNED — a planned pace must not count a target nobody set — and their
    /// chip shows an en dash rather than a zero, because a lifter who set no
    /// target has not set a target of none.
    func testALifterWithNoGoalIsOutOfThePlanButInTheCount() {
        let week = CrewWeek(lifters: [
            lifter("Alex Rue", goal: 4, done: 2),
            lifter("Dana Kord", goal: 4, done: 2),
            lifter("Sam Obi", goal: 3, done: 1),
            lifter("Lee Vance", goal: 3, done: 1),
            lifter("Mo Farrow", goal: nil, done: 2),
        ], todayIndex: 2)

        XCTAssertEqual(CrewWeekMath.planTotal(week), 14, "the goal-less lifter adds no plan")
        XCTAssertEqual(CrewWeekMath.doneTotal(week), 8, "but their sessions still happened")
        XCTAssertEqual(CrewWeekMath.caption(week), "2 AHEAD · 8 OF 14")
        XCTAssertEqual(CrewWeekMath.chip(week.lifters[4]), "Mo 2/–")
        XCTAssertEqual(CrewWeekMath.chip(week.lifters[0]), "Alex 2/4")
    }

    // MARK: - The two series

    /// Eight points, Monday morning's nothing to Sunday night's whole plan.
    func testThePlannedLineRunsZeroToThePlanAcrossSevenDays() {
        let week = wednesdayCrew(done: [2, 2, 1, 1])
        let planned = CrewWeekMath.plannedSeries(week)
        XCTAssertEqual(planned.count, 8)
        XCTAssertEqual(planned.first, 0)
        XCTAssertEqual(planned.last, 14)
        XCTAssertEqual(planned[1], 2, accuracy: 0.001)
    }

    /// Per-day counts give the real shape, cumulative and stopping on today.
    func testTheActualLineIsCumulativeAndStopsOnToday() {
        let week = CrewWeek(lifters: [
            lifter("Alex Rue", goal: 4, done: 3, byDay: [1, 0, 2, 0, 0, 0, 0]),
            lifter("Dana Kord", goal: 4, done: 2, byDay: [0, 1, 1, 0, 0, 0, 0]),
        ], todayIndex: 2)
        // Monday 1, Tuesday +1 = 2, Wednesday +3 = 5, and no Thursday.
        XCTAssertEqual(CrewWeekMath.actualSeries(week), [0, 1, 2, 5])
    }

    /// With only totals it is two points — a straight line is what a total
    /// honestly is, and inventing a shape for it would be a chart that lies.
    func testWithoutPerDayCountsTheActualLineIsStraight() {
        let week = wednesdayCrew(done: [2, 2, 1, 1])
        XCTAssertEqual(CrewWeekMath.actualSeries(week), [0, 6])
    }

    // MARK: - Guards

    /// A malformed `todayIndex` must not index off the week.
    func testTodayIsClamped() {
        let high = wednesdayCrew(done: [0, 0, 0, 0])
        XCTAssertEqual(CrewWeekMath.today(CrewWeek(lifters: high.lifters,
                                                   todayIndex: 99)), 6)
        XCTAssertEqual(CrewWeekMath.today(CrewWeek(lifters: high.lifters,
                                                   todayIndex: -3)), 0)
    }

    /// A crew where nobody set a goal has no plan to be behind — and says
    /// nothing worse than "on pace", which for a crew with no target is the
    /// only honest verdict.
    func testACrewWithNoGoalsAtAllIsOnPace() {
        let week = CrewWeek(lifters: [lifter("Mo Farrow", goal: nil, done: 0)],
                            todayIndex: 3)
        XCTAssertEqual(CrewWeekMath.planTotal(week), 0)
        XCTAssertEqual(CrewWeekMath.caption(week), "ON PACE · 0 OF 0 SESSIONS")
    }

    // MARK: - The catalog's world

    /// `session-lobby-waiting` / `session-lobby-ready` (plan task S11) render
    /// this. The chips are the owner's own numbers; the caption is whatever
    /// those numbers honestly produce on the fixture's Thursday.
    func testTheLobbyFixturesCrewWeek() throws {
        let week = try XCTUnwrap(LobbyFixtures.waiting.crewWeek)
        XCTAssertEqual(week.lifters.map(CrewWeekMath.chip),
                       ["Alex 2/3", "Sam 3/3", "Dana 1/4", "Lee 2/3"])
        XCTAssertEqual(CrewWeekMath.planTotal(week), 13)
        XCTAssertEqual(CrewWeekMath.doneTotal(week), 8)
        XCTAssertEqual(CrewWeekMath.caption(week), "1 AHEAD · 8 OF 13")
        XCTAssertEqual(LobbyFixtures.ready.crewWeek, week,
                       "one crew, one week — the two frames must not disagree")
    }
}
