import XCTest
@testable import GymSync

/// Spec §1's lines 2 and 3, as values.
final class PostTrajectoryMathTests: XCTestCase {

    private func goal(outcome: GoalOutcome? = nil) -> BlockGoal {
        BlockGoal(id: UUID(), userID: UUID(), enrollmentID: UUID(),
                  metric: .liftOneRepMax,
                  target: GoalTarget(targetWeightLbs: 225),
                  byDate: nil, preset: .strength, source: .user,
                  outcome: outcome, outcomeValue: nil,
                  createdAt: Date(timeIntervalSince1970: 0),
                  updatedAt: Date(timeIntervalSince1970: 0))
    }

    private func row(_ week: Int, _ status: RungStatus) -> LadderRow {
        LadderRow(weekNumber: week, weekStartString: "2026-09-0\(week)",
                  targetText: "3 × 5 at 200", implication: nil,
                  status: status, isDeload: false, note: nil)
    }

    private func page(_ statuses: [RungStatus], reaches: Bool = true) -> LadderPageModel {
        LadderPageModel(headline: "Bench 225 by Oct 18", dateLine: "Sunday 18 October",
                        coachLine: "On track",
                        rows: statuses.enumerated().map { row($0.offset + 1, $0.element) },
                        reachesMilestone: reaches, weekNumber: 3, weekCount: 8,
                        source: .user)
    }

    // MARK: - standing

    func testAClimbingLadderIsOnTrack() {
        XCTAssertEqual(
            PostTrajectoryMath.standing(goal: goal(), page: page([.met, .met, .current, .ahead])),
            .onTrack)
    }

    func testALadderThatCannotReachTheDateIsBehind() {
        XCTAssertEqual(
            PostTrajectoryMath.standing(goal: goal(),
                                        page: page([.met, .current, .ahead], reaches: false)),
            .behind)
    }

    /// THE CARD MUST SAY WHAT THE LADDER PAGE SAYS. `coachLine` reads "On
    /// track" whenever the ladder still `reachesMilestone`, so a week that was
    /// missed and then absorbed by a re-derived ladder is history, not
    /// standing — otherwise the page tells the athlete they are on track while
    /// their own post tells their crew they are behind.
    func testStandingFollowsTheLadderPagesCoachLine() {
        XCTAssertEqual(
            PostTrajectoryMath.standing(goal: goal(), page: page([.met, .missed, .current])),
            .onTrack,
            "a missed week the ladder still reaches past is not a standing")
    }

    func testARecordedOutcomeWins() {
        XCTAssertEqual(
            PostTrajectoryMath.standing(goal: goal(outcome: .met),
                                        page: page([.missed, .missed], reaches: false)),
            .met)
    }

    func testTheLastRungMetIsMet() {
        XCTAssertEqual(
            PostTrajectoryMath.standing(goal: goal(), page: page([.met, .met, .met])),
            .met)
    }

    func testAMetLastRungOnALadderThatFallsShortIsBehind() {
        XCTAssertEqual(
            PostTrajectoryMath.standing(goal: goal(),
                                        page: page([.met, .met, .met], reaches: false)),
            .behind)
    }

    // MARK: - chips

    func testMuscleSetsChipsPassThroughUnchanged() {
        let progress = WeeklyGoalProgress(
            chips: [.init(name: "CHEST", done: 8, target: 12, isNext: false),
                    .init(name: "BACK", done: 10, target: 12, isNext: false),
                    .init(name: "LEGS", done: 6, target: 12, isNext: true),
                    .init(name: "ARMS", done: 8, target: 8, isNext: false)])
        let chips = PostTrajectoryMath.chips(kind: .muscleSets, progress: progress)
        XCTAssertEqual(chips.map(\.name), ["CHEST", "BACK", "LEGS", "ARMS"])
        XCTAssertEqual(chips[2].done, 6)
        XCTAssertNil(chips[0].fill, "a muscle-sets chip's meter IS its fraction")
    }

    func testNoMoreThanFourChips() {
        let progress = WeeklyGoalProgress(
            chips: (0..<7).map { .init(name: "G\($0)", done: 1, target: 1, isNext: false) })
        XCTAssertEqual(PostTrajectoryMath.chips(kind: .muscleSets, progress: progress).count, 4)
    }

    /// A `days` rung is SEVEN weekday chips on the strip, and `prefix(4)` of
    /// them is Monday-to-Thursday — so a Thursday-to-Saturday lifter posted
    /// `0/0 · 0/0 · 0/0 · 0/0` under a line claiming a rung. One chip, the
    /// strip's own reading.
    func testADaysRungIsOneChipNotFourEmptyWeekdays() {
        let week = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        let trained: Set<String> = ["THU", "FRI", "SAT"]
        let progress = WeeklyGoalProgress(
            chips: week.map { .init(name: $0,
                                    done: trained.contains($0) ? 1 : 0,
                                    target: trained.contains($0) ? 1 : 0,
                                    isNext: false) },
            value: 3, target: 4)
        let chips = PostTrajectoryMath.chips(kind: .days, progress: progress)
        XCTAssertEqual(chips.count, 1)
        XCTAssertEqual(chips[0].name, "DAYS")
        XCTAssertEqual(chips[0].done, 3)
        XCTAssertEqual(chips[0].target, 4)
        XCTAssertNil(chips[0].fill, "days done over days asked for IS the meter")
    }

    /// The span kinds: the numbers the strip PRINTS, the meter the strip DRAWS.
    func testALiftChipPrintsTheLoadAndDrawsTheBlocksSpan() throws {
        let progress = WeeklyGoalProgress(
            chips: [.init(name: "BENCH PRESS", done: 5, target: 20, isNext: false)],
            value: 210, target: 225, unitLabel: "lb")
        let chips = PostTrajectoryMath.chips(kind: .lift, progress: progress)
        XCTAssertEqual(chips.count, 1)
        XCTAssertEqual(chips[0].done, 210)
        XCTAssertEqual(chips[0].target, 225)
        XCTAssertEqual(try XCTUnwrap(chips[0].fill), 0.25, accuracy: 0.0001)
    }

    func testRecoveryKeepsBothOfItsChips() {
        let progress = WeeklyGoalProgress(
            chips: [.init(name: "STRETCHES", done: 4, target: 6, isNext: false),
                    .init(name: "LISS MIN", done: 90, target: 120, isNext: false)],
            value: 4, target: 6)
        XCTAssertEqual(PostTrajectoryMath.chips(kind: .recovery, progress: progress).count, 2)
    }

    func testAKindWithNoChipYieldsNoLineRatherThanAGuess() {
        XCTAssertTrue(PostTrajectoryMath.chips(kind: .lift,
                                               progress: WeeklyGoalProgress()).isEmpty)
    }

    // MARK: - snapshot

    func testTheSnapshotIsTheSpecsLine() {
        let snapshot = PostTrajectoryMath.snapshot(
            goal: goal(), page: page([.met, .met, .current]),
            weeklyKind: nil, weeklyProgress: nil)
        XCTAssertEqual(snapshot.line, "Bench 225 by Oct 18 · week 3 of 8 · on track")
        XCTAssertTrue(snapshot.chips.isEmpty, "no materialised rung is no line 3")
    }
}
