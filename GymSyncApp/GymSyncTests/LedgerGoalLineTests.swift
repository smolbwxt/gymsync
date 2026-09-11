import XCTest
@testable import GymSync

/// Plan: docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md,
/// task D5. Spec §6: "The ledger records the goal's outcome with each
/// finished block: met, missed, or partial, with the milestone and the final
/// measured value."
final class LedgerGoalLineTests: XCTestCase {

    /// **NOON UTC, FROM COMPONENTS** — not the epoch literal the plan wrote.
    ///
    /// The plan's own `1_792_411_200 // 2026-10-18` is the same wrong literal
    /// Task 0's review already caught in `StubBlockGoalRepository`: it is
    /// 2026-10-**19** at midnight UTC, so the assertions below would have
    /// read "BY OCT 19" and the formatter would have been blamed. Components
    /// are readable and therefore reviewable, and NOON is the anchor commit
    /// c114baf established for exactly this: a device-local formatter in any
    /// zone from UTC-11 to UTC+11 still prints the same calendar day.
    private static let byDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }()

    /// Gregorian in the DEVICE's timezone, exactly as `goalLine`'s caller
    /// leaves it. Paired with the noon anchor above, the day is the same
    /// everywhere CI or a device runs.
    private let calendar = Calendar(identifier: .gregorian)

    private func goal(_ outcome: GoalOutcome?) -> BlockGoal {
        BlockGoal(id: UUID(), userID: UUID(), enrollmentID: UUID(),
                  metric: .liftOneRepMax,
                  target: GoalTarget(exerciseID: UUID(), targetWeightLbs: 225),
                  byDate: Self.byDate,
                  preset: .strength, source: .user, outcome: outcome,
                  outcomeValue: outcome == nil ? nil : GoalTarget(targetWeightLbs: 227),
                  createdAt: Date(timeIntervalSince1970: 0),
                  updatedAt: Date(timeIntervalSince1970: 0))
    }

    func testAFinishedBlockSaysWhatItWasForAndHowItCameOut() {
        XCTAssertEqual(
            ProgramLedgerView.goalLine(goal(.met), liftName: "Bench", unit: .lbs,
                                       calendar: calendar),
            "MET — BENCH 225 BY OCT 18")
        XCTAssertEqual(
            ProgramLedgerView.goalLine(goal(.missed), liftName: "Bench", unit: .lbs,
                                       calendar: calendar),
            "MISSED — BENCH 225 BY OCT 18")
    }

    func testAnOutcomelessGoalStillNamesTheMilestone() {
        XCTAssertEqual(
            ProgramLedgerView.goalLine(goal(nil), liftName: "Bench", unit: .lbs,
                                       calendar: calendar),
            "BENCH 225 BY OCT 18",
            "phase 1 renders; phase 3 writes the outcome")
    }

    func testABlockWithNoGoalRendersNothingAtAll() {
        XCTAssertNil(ProgramLedgerView.goalLine(nil, liftName: "", unit: .lbs,
                                                calendar: calendar),
                     "a record does not editorialise about its own gaps")
    }

    /// A lift goal whose exercise this build could not name has nothing true
    /// to print — "225 BY OCT 18" would claim a lift it does not know.
    func testALiftGoalWithNoResolvableNameRendersNothing() {
        XCTAssertNil(ProgramLedgerView.goalLine(goal(.met), liftName: "", unit: .lbs,
                                                calendar: calendar))
    }

    /// Maintenance, Recovery and Consistency are held for the block and carry
    /// no date (spec §2.1), so the line stops at the subject rather than
    /// trailing an empty "BY".
    func testAGoalHeldForTheBlockNamesNoDate() {
        let held = BlockGoal(id: UUID(), userID: UUID(), enrollmentID: UUID(),
                             metric: .trainingDaysPerWeek,
                             target: GoalTarget(days: 4),
                             byDate: nil, preset: .consistency, source: .user,
                             outcome: .partial, outcomeValue: nil,
                             createdAt: Date(timeIntervalSince1970: 0),
                             updatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(
            ProgramLedgerView.goalLine(held, liftName: "", unit: .lbs, calendar: calendar),
            "PARTIAL — 4 DAYS A WEEK")
    }

    /// The canonical-pounds rule holds all the way to the ledger: a kg
    /// athlete reads their own number, not 225.
    func testTheMilestoneIsReadInTheAthletesOwnUnit() {
        XCTAssertEqual(
            ProgramLedgerView.goalLine(goal(nil), liftName: "Bench", unit: .kg,
                                       calendar: calendar),
            "BENCH 102 BY OCT 18")
    }

    /// Red is for errors only (design rule 2), and a missed block is a fact.
    /// The word is the whole of the signal.
    func testAMissedBlockIsStillNamedPlainly() {
        let line = ProgramLedgerView.goalLine(goal(.missed), liftName: "Bench",
                                              unit: .lbs, calendar: calendar)
        XCTAssertEqual(line?.hasPrefix("MISSED"), true)
    }

    // MARK: - The read is wired, not a placeholder (review finding 3)

    /// A repository that knows one finished block's goal — the shape Stream
    /// A's live one will have at I1, standing in for it here.
    private struct LedgerBlockGoalRepository: BlockGoalRepository {
        let goal: BlockGoal
        func activeGoal() async -> BlockGoal? { goal }
        func ladder(goalID: UUID) async -> Ladder? { nil }
        func page(goalID: UUID) async -> LadderPageModel? { nil }
        @discardableResult func save(_ goal: BlockGoal) async -> Bool { false }
        func reLadder(goalID: UUID) async -> Ladder? { nil }
        @discardableResult
        func materialiseRung(goalID: UUID, weekStart: String) async -> WeeklyGoal? { nil }
    }

    /// THE WHOLE CHAIN, on a finished block: the injected repository answers,
    /// `goals(for:repository:)` keys it by enrollment, and `goalLine` words
    /// it. This is what makes D5 a wired read rather than a seam that always
    /// answered `[:]` — hand the ledger a repository that knows the block and
    /// the row says what the block was for.
    func testTheLedgerReadsItsGoalThroughTheInjectedRepository() async {
        let finished = goal(.met)
        let repository = LedgerBlockGoalRepository(goal: finished)

        let goals = await ProgramLedgerView.goals(for: [finished.enrollmentID],
                                                  repository: repository)
        XCTAssertEqual(goals.count, 1)
        let found = goals[finished.enrollmentID]
        XCTAssertNotNil(found)
        XCTAssertEqual(
            ProgramLedgerView.goalLine(found, liftName: "Bench", unit: .lbs,
                                       calendar: calendar),
            "MET — BENCH 225 BY OCT 18",
            "a finished block on screen says what it was for and how it came out")
    }

    /// A block the repository does not know about contributes nothing — the
    /// ledger does not attach one block's goal to another block's row.
    func testAGoalForSomeOtherBlockNeverLandsOnThisRow() async {
        let elsewhere = goal(.met)
        let goals = await ProgramLedgerView.goals(
            for: [UUID()], repository: LedgerBlockGoalRepository(goal: elsewhere))
        XCTAssertTrue(goals.isEmpty)
    }

    /// The stub's fixture enrollment no real block has — so a catalog capture
    /// that constructs one explicitly sees no goal line rather than the
    /// fixture's bench milestone, exactly as the schedule page's card does.
    func testTheStubNeverAttachesItsFixtureGoalToARealBlock() async {
        let goals = await ProgramLedgerView.goals(for: [UUID(), UUID()],
                                                  repository: StubBlockGoalRepository())
        XCTAssertTrue(goals.isEmpty)
    }

    /// The shipping default is `LiveBlockGoalRepository` (integration task
    /// I1's swap) — `StubBlockGoalRepository` stays in the codebase only for
    /// the catalog captures, which construct it explicitly.
    func testTheShippingDefaultIsLive() {
        XCTAssertTrue(ProgramLedgerView().goalRepository is LiveBlockGoalRepository)
        XCTAssertNil(ProgramLedgerView().goalsForEnrollments,
                     "the closure is the previewless fallback, not the shipping path")
    }
}
