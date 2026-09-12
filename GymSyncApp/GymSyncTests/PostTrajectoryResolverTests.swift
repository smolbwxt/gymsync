import XCTest
@testable import GymSync

/// The one place that reads the author's own goal at post time (task S2.6).
///
/// It has an injection seam — `blockGoals:` and `weeklyGoals:` — and until
/// this file that seam had no test, so nothing proved the resolver actually
/// asked the repositories anything or handed back what they said (review fix
/// 7). The fixtures are the app's own `StubBlockGoalRepository` and
/// `StubWeeklyGoalRepository`; the two absence cases need repositories that
/// answer nil, which is the repo's private-marker-stub idiom
/// (`LadderRepositoryWiringTests.swift:27`, `LadderLeverTests.swift:21`).
final class PostTrajectoryResolverTests: XCTestCase {

    /// A block that has not started: no goal, therefore no trajectory.
    private struct BlocklessBlockGoalRepository: BlockGoalRepository {
        func activeGoal() async -> BlockGoal? { nil }
        func ladder(goalID: UUID) async -> Ladder? { nil }
        func page(goalID: UUID) async -> LadderPageModel? { nil }
        @discardableResult func save(_ goal: BlockGoal) async -> Bool { false }
        func reLadder(goalID: UUID) async -> Ladder? { nil }
        @discardableResult
        func materialiseRung(goalID: UUID, weekStart: String) async -> WeeklyGoal? { nil }
    }

    /// A block whose current week has not been materialised into a rung yet.
    private struct NoRungWeeklyGoalRepository: WeeklyGoalRepository {
        func goal(weekStart: String) async -> WeeklyGoal? { nil }
        func progress(for goal: WeeklyGoal) async -> WeeklyGoalProgress { WeeklyGoalProgress() }
        @discardableResult func save(_ goal: WeeklyGoal) async -> Bool { false }
        func clearToCoach(weekStart: String) async -> WeeklyGoal? { nil }
    }

    /// A FIXED calendar, so the week key is a fact rather than a reading of
    /// the machine the test runs on: gregorian, UTC, weeks starting Sunday.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 1
        return calendar
    }

    /// Wednesday 9 September 2026, noon UTC — inside the week that starts
    /// Sunday 6 September, which is the week the catalog's own fixtures name.
    private var wednesday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: - an athlete inside a block, with this week's rung

    func testAnActiveBlockWithARungResolvesBothLines() async throws {
        let resolved = await PostTrajectoryResolver.resolve(
            now: wednesday, calendar: calendar,
            blockGoals: StubBlockGoalRepository(),
            weeklyGoals: StubWeeklyGoalRepository())
        let snapshot = try XCTUnwrap(resolved)   // bind, THEN unwrap

        XCTAssertEqual(snapshot.goalID, StubBlockGoalRepository.fixtureGoalID,
                       "provenance is the goal the repository answered with")
        XCTAssertEqual(snapshot.weekStartString, "2026-09-06",
                       "the week key is WeekMath's, on the calendar handed in")
        XCTAssertEqual(snapshot.trajectory.line,
                       "Bench 225 by Oct 18 · week 3 of 8 · on track",
                       "line 2 is the ladder page's own headline and standing")
        XCTAssertEqual(snapshot.trajectory.chips.map(\.name),
                       ["CHEST", "BACK", "LEGS", "ARMS"],
                       "line 3 is this week's rung, from the weekly repository")
    }

    /// The week key the resolver computes is the key it ASKS THE WEEKLY
    /// REPOSITORY FOR — a second definition of "this week" here would put the
    /// card's rung and the Home strip's rung in different weeks for every
    /// user whose week does not start on Monday.
    func testTheWeekKeyIsTheOneHandedToTheWeeklyRepository() async throws {
        let resolved = await PostTrajectoryResolver.resolve(
            now: wednesday, calendar: calendar,
            blockGoals: StubBlockGoalRepository(),
            weeklyGoals: StubWeeklyGoalRepository())
        let snapshot = try XCTUnwrap(resolved)
        XCTAssertEqual(snapshot.weekStartString,
                       WeekMath.weekStartString(wednesday, calendar: calendar))
    }

    // MARK: - the two absences

    /// Spec §1: "An athlete with no active block has no line 2 and no line 3".
    /// The resolver returns nil, and the card branches on that.
    func testNoActiveBlockResolvesToNothingAtAll() async {
        let resolved = await PostTrajectoryResolver.resolve(
            now: wednesday, calendar: calendar,
            blockGoals: BlocklessBlockGoalRepository(),
            weeklyGoals: StubWeeklyGoalRepository())
        XCTAssertNil(resolved, "no block is no trajectory, not an empty one")
    }

    /// A DIFFERENT ABSENCE, and spec §1 treats it differently: the athlete is
    /// inside a block, so line 2 exists; this week simply has no materialised
    /// rung yet, so line 3 does not. A legible state, and the reason
    /// `PostTrajectoryMath.snapshot` takes its weekly pair as optional.
    func testABlockWhoseWeekHasNoRungKeepsLineTwoAndDropsLineThree() async throws {
        let resolved = await PostTrajectoryResolver.resolve(
            now: wednesday, calendar: calendar,
            blockGoals: StubBlockGoalRepository(),
            weeklyGoals: NoRungWeeklyGoalRepository())
        let snapshot = try XCTUnwrap(resolved)

        XCTAssertEqual(snapshot.trajectory.line,
                       "Bench 225 by Oct 18 · week 3 of 8 · on track")
        XCTAssertTrue(snapshot.trajectory.chips.isEmpty,
                      "no materialised rung is no line 3 — not a row of zeros")
        XCTAssertEqual(snapshot.goalID, StubBlockGoalRepository.fixtureGoalID)
    }
}
