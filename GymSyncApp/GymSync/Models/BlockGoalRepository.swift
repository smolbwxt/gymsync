import Foundation

// MARK: - The block goal's repository surface
//
// Plan task 0.4. THIS IS THE INTERFACE STREAMS C AND D FORK AGAINST. Stream
// A ships `LiveBlockGoalRepository` behind the same protocol and integration
// task I1 swaps the binding; until then `StubBlockGoalRepository` is what
// everything sees — deterministic, no network, no clock — so the door and the
// ladder page are correct and capturable at every point in the build rather
// than only at the end.

/// Reads and writes the block's goal and its ladder.
///
/// `async` with no `throws`, matching `WeeklyGoalRepository`: every read on
/// these surfaces is best-effort, and a network blip must render the page's
/// empty state rather than an error dialog.
protocol BlockGoalRepository: Sendable {
    /// The goal driving the active enrollment, or nil when there is no block
    /// or the block predates goals.
    func activeGoal() async -> BlockGoal?
    /// The persisted rungs for a goal.
    func ladder(goalID: UUID) async -> Ladder?
    /// Everything the ladder page renders, already worded (task A12).
    func page(goalID: UUID) async -> LadderPageModel?
    /// The athlete editing their own milestone or date. Always stamps
    /// `source = .user`, for the same reason `WeeklyGoalRepository.save`
    /// does: the milestone and its date belong to the athlete (owner
    /// decision 8), and Coach may only propose against a `user` row.
    @discardableResult func save(_ goal: BlockGoal) async -> Bool
    /// LET COACH RE-LADDER: re-derive the remaining rungs from actuals and
    /// persist them. Rewrites only rungs whose status is `ahead` or
    /// `current` (spec §8), so a missed or overridden week stays visible.
    func reLadder(goalID: UUID) async -> Ladder?
    /// Write this week's rung into `weekly_goals` as the current weekly goal
    /// (spec §4). Returns the row now in effect — which may be the athlete's
    /// own, because this consults `WeeklyGoalWriteRule` exactly as every
    /// other Coach write does.
    @discardableResult
    func materialiseRung(goalID: UUID, weekStart: String) async -> WeeklyGoal?
}

// MARK: - The stub

/// The shipping default until Stream A's `LiveBlockGoalRepository` lands
/// (integration task I1).
///
/// HERMETIC: no `AppState`, no repository, no `Date.now`. The fixture is the
/// spec's own worked example — bench 225 by Oct 18, an eight-week block,
/// currently week 3 — so the ladder page's captures, the door's captures and
/// the design's prose all describe one block.
///
/// **THESE VALUES ARE THE CATALOG'S WORLD** (controller ruling 3): three
/// streams capture against them, so they are a contract rather than an
/// implementation detail, and they are written out here so a reviewer can
/// check a frame without reading the code under it.
///
///   * **the goal** — metric `liftOneRepMax`, target 225 lb on exercise
///     `…b4`, by date **2026-10-18**, preset `strength`, source `user`
///     (the athlete set it at the door), no outcome. Ids `…b1` user,
///     `…b2` goal, `…b3` enrollment, `…b4` exercise. Created
///     **2026-08-24**.
///   * **the ladder** — eight rungs, week-starts `2026-08-23` through
///     `2026-10-11`, targets **190, 195, 200, 205, 210, 175, 220, 225** lb.
///     Statuses: weeks 1–2 `met`, week 3 `current`, weeks 4–8 `ahead` —
///     exactly one `current`, which is what makes "week 3" true on every
///     surface at once. Week 6's 175 is the WAVE'S DELOAD, shown as what it
///     is (spec §3.2) rather than smoothed away.
///   * **the page** — headline `Bench 225 by Oct 18`, date line
///     `Sunday 18 October`, Coach's line `On track`, `reachesMilestone`
///     true, week 3 of 8, source `user`. Eight rows, one per rung, worded
///     `3 × 5 at 190` … `2 × 1 at 225` with their e1RM implications; the
///     deload row carries no implication and the note
///     `Deload — move fast, leave fresh.`
///
/// The page and the ladder are asserted to agree in `BlockGoalModelTests
/// .testTheStubIsHermeticAndConsistent`, so the two fixtures cannot drift
/// into describing two different blocks.
struct StubBlockGoalRepository: BlockGoalRepository {

    /// Fixed ids, so nothing in a screenshot diff moves between runs.
    static let fixtureUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b1") ?? UUID()
    static let fixtureGoalID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b2") ?? UUID()
    static let fixtureEnrollmentID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b3") ?? UUID()
    static let fixtureExerciseID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b4") ?? UUID()

    /// 2026-08-24T12:00:00Z — the block's start. A fixture, not a clock.
    static let fixtureCreatedAt = Date(timeIntervalSince1970: 1_787_745_600)
    /// 2026-10-18T12:00:00Z — the milestone date the spec names.
    static let fixtureByDate = Date(timeIntervalSince1970: 1_792_411_200)

    static let fixtureGoal = BlockGoal(
        id: fixtureGoalID, userID: fixtureUserID, enrollmentID: fixtureEnrollmentID,
        metric: .liftOneRepMax,
        target: GoalTarget(exerciseID: fixtureExerciseID, targetWeightLbs: 225),
        byDate: fixtureByDate, preset: .strength, source: .user,
        outcome: nil, outcomeValue: nil,
        createdAt: fixtureCreatedAt, updatedAt: fixtureCreatedAt)

    /// Eight rungs off the block's own prescribed loading, with the wave's
    /// deload at week 6 (`ProgramGenerator`'s ¾-mark rule for an 8-week
    /// block) — the ladder shows the deload as what it is (spec §3.2), it
    /// does not smooth it away.
    static let fixtureLadder = Ladder(
        goalID: fixtureGoalID,
        rungs: [
            .init(weekIndex: 0, weekStartString: "2026-08-23",
                  target: GoalTarget(targetWeightLbs: 190), status: .met),
            .init(weekIndex: 1, weekStartString: "2026-08-30",
                  target: GoalTarget(targetWeightLbs: 195), status: .met),
            .init(weekIndex: 2, weekStartString: "2026-09-06",
                  target: GoalTarget(targetWeightLbs: 200), status: .current),
            .init(weekIndex: 3, weekStartString: "2026-09-13",
                  target: GoalTarget(targetWeightLbs: 205), status: .ahead),
            .init(weekIndex: 4, weekStartString: "2026-09-20",
                  target: GoalTarget(targetWeightLbs: 210), status: .ahead),
            .init(weekIndex: 5, weekStartString: "2026-09-27",
                  target: GoalTarget(targetWeightLbs: 175), status: .ahead),
            .init(weekIndex: 6, weekStartString: "2026-10-04",
                  target: GoalTarget(targetWeightLbs: 220), status: .ahead),
            .init(weekIndex: 7, weekStartString: "2026-10-11",
                  target: GoalTarget(targetWeightLbs: 225), status: .ahead),
        ],
        derivedAt: fixtureCreatedAt)

    /// The page as the spec words it (§6): the milestone as the headline,
    /// the date, Coach's one line on standing.
    static let fixturePage = LadderPageModel(
        headline: "Bench 225 by Oct 18",
        dateLine: "Sunday 18 October",
        coachLine: "On track",
        rows: [
            .init(weekNumber: 1, weekStartString: "2026-08-23", targetText: "3 × 5 at 190",
                  implication: "≈ 214 e1RM", status: .met, isDeload: false, note: nil),
            .init(weekNumber: 2, weekStartString: "2026-08-30", targetText: "3 × 5 at 195",
                  implication: "≈ 219 e1RM", status: .met, isDeload: false, note: nil),
            .init(weekNumber: 3, weekStartString: "2026-09-06", targetText: "3 × 5 at 200",
                  implication: "≈ 225 e1RM", status: .current, isDeload: false, note: nil),
            .init(weekNumber: 4, weekStartString: "2026-09-13", targetText: "4 × 3 at 205",
                  implication: "≈ 223 e1RM", status: .ahead, isDeload: false, note: nil),
            .init(weekNumber: 5, weekStartString: "2026-09-20", targetText: "4 × 3 at 210",
                  implication: "≈ 228 e1RM", status: .ahead, isDeload: false, note: nil),
            .init(weekNumber: 6, weekStartString: "2026-09-27", targetText: "2 × 5 at 175",
                  implication: nil, status: .ahead, isDeload: true,
                  note: "Deload — move fast, leave fresh."),
            .init(weekNumber: 7, weekStartString: "2026-10-04", targetText: "3 × 2 at 220",
                  implication: "≈ 232 e1RM", status: .ahead, isDeload: false, note: nil),
            .init(weekNumber: 8, weekStartString: "2026-10-11", targetText: "2 × 1 at 225",
                  implication: "≈ 232 e1RM", status: .ahead, isDeload: false, note: nil),
        ],
        reachesMilestone: true, weekNumber: 3, weekCount: 8, source: .user)

    func activeGoal() async -> BlockGoal? { Self.fixtureGoal }
    func ladder(goalID: UUID) async -> Ladder? { Self.fixtureLadder }
    func page(goalID: UUID) async -> LadderPageModel? { Self.fixturePage }

    /// The stub stores nothing — a save "succeeds" so the page's happy path
    /// is walkable and the next read still returns the fixture.
    @discardableResult func save(_ goal: BlockGoal) async -> Bool { true }
    func reLadder(goalID: UUID) async -> Ladder? { Self.fixtureLadder }
    @discardableResult
    func materialiseRung(goalID: UUID, weekStart: String) async -> WeeklyGoal? { nil }
}
