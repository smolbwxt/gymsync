import Foundation

// MARK: - The block goal's repository surface
//
// Plan task 0.4. THIS IS THE INTERFACE STREAMS C AND D FORKED AGAINST.
// `LiveBlockGoalRepository` ships behind it and I1 swapped every production
// binding to it. `StubBlockGoalRepository` below is now the CATALOG'S
// repository — deterministic, no network, no clock — which is what keeps the
// door's and the ladder page's frames values rather than fetches.

/// Reads and writes the block's goal and its ladder.
///
/// `async` with no `throws`, matching `WeeklyGoalRepository`: every read on
/// these surfaces is best-effort, and a network blip must render the page's
/// empty state rather than an error dialog.
protocol BlockGoalRepository: Sendable {
    /// The goal driving the active enrollment, or nil when there is no block
    /// or the block predates goals.
    func activeGoal() async -> BlockGoal?
    /// The goals driving a SET of blocks, keyed by enrollment.
    ///
    /// **A LEDGER ROW IS A BLOCK THAT HAS ENDED** (final review F3), and
    /// `activeGoal()` answers only for the one that has not — it resolves
    /// through `ProgramRepository.active()`, which is `ended_at IS NULL` by
    /// definition. `ProgramLedgerView.pastRow` is driven by
    /// `enrollments.filter { $0.endedAt != nil }`, so the intersection of the
    /// two was empty BY CONSTRUCTION and D5's "the ledger says what each block
    /// was for" rendered for no row, ever.
    ///
    /// A REQUIREMENT WITH A DEFAULT, not an extension-only method, for the
    /// reason `saveDerivedLadder` states below: an extension-only member
    /// dispatches statically through `any BlockGoalRepository` and the live
    /// type's version would never run. The default is the old narrowing —
    /// whatever `activeGoal()` can answer — so every existing conformer keeps
    /// compiling and keeps behaving exactly as it did.
    func goals(enrollmentIDs: [UUID]) async -> [UUID: BlockGoal]
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
    /// Derive this goal's whole ladder from the block that was just generated
    /// and persist it — `ProgramBuilder.build`'s step 7b (task B4).
    ///
    /// THE LADDER IS A READ-OUT OF THE BLOCK (spec §3.1), so this takes the
    /// `program` and not a target curve: it calls `LadderReadout` for the three
    /// metrics the generator PRESCRIBES (`liftOneRepMax`, `liftRepsAtLoad`,
    /// `weeklyMuscleSets`) and `LadderRules.rule(for:)` for the eight it ramps,
    /// then writes `enrollment.weeks` rungs whose week keys walk forward from
    /// the block's start (`LadderMath.weekStartStrings(from:count:)`).
    ///
    /// **DECLARED IN TASK B4, IMPLEMENTED IN TASK A11.** It is a requirement
    /// rather than an extension method so that A11's `LiveBlockGoalRepository`
    /// genuinely OVERRIDES it: an extension-only method would dispatch
    /// statically through `any BlockGoalRepository` and the live type's version
    /// would never run. The default below returns nil — every conformer that
    /// exists today keeps compiling untouched, and a repository that cannot
    /// derive a ladder says so by returning nothing rather than by not having
    /// the method.
    @discardableResult
    func saveDerivedLadder(goal: BlockGoal,
                           program: ProgramGenerator.Program,
                           catalog: [Exercise],
                           startedOn: Date,
                           unit: WeightUnit) async -> Ladder?
}

extension BlockGoalRepository {
    /// The narrowest honest answer a repository with one goal read can give:
    /// the active block's goal, and only when that block is one of the rows
    /// asked about. `LiveBlockGoalRepository` overrides it with the batch read
    /// the plan describes (`.in("enrollment_id", …)`).
    func goals(enrollmentIDs: [UUID]) async -> [UUID: BlockGoal] {
        guard let goal = await activeGoal(),
              enrollmentIDs.contains(goal.enrollmentID) else { return [:] }
        return [goal.enrollmentID: goal]
    }

    /// NO LADDER, and that is a legible state rather than a crash: the stub
    /// stores nothing, and a block whose ladder could not be derived is exactly
    /// the state task A13's detection fills on the next Home load — the same
    /// recovery path a migrated block takes.
    @discardableResult
    func saveDerivedLadder(goal: BlockGoal,
                           program: ProgramGenerator.Program,
                           catalog: [Exercise],
                           startedOn: Date,
                           unit: WeightUnit) async -> Ladder? { nil }
}

// MARK: - The stub

/// The CATALOG'S repository since I1 swapped the shipping default to
/// `LiveBlockGoalRepository`.
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
///   * **the goal** — metric `liftOneRepMax`, target 225 lb on
///     `WeeklyGoalFixtures.benchPressID`, by date **Sunday 2026-10-18**,
///     preset `strength`, source `user` (the athlete set it at the door), no
///     outcome. Ids `…c1` user, `…c2` goal, `…c3` enrollment; the exercise is
///     the FIXTURE WORLD'S OWN BENCH PRESS by reference, so the stub's bench
///     goal and the catalog's bench press are one lift rather than two that
///     read alike. Created **Monday 2026-08-24**. Both dates are built from
///     components at noon UTC (see `utcDate`), never from an epoch
///     literal.
///   * **the ladder** — eight rungs, week-starts `2026-08-23` through
///     `2026-10-11`, targets **190, 195, 200, 205, 210, 175, 220, 225** lb.
///     Statuses: weeks 1–2 `met`, week 3 `current`, weeks 4–8 `ahead` —
///     exactly one `current`, which is what makes "week 3" true on every
///     surface at once. Week 6's 175 is the WAVE'S DELOAD, shown as what it
///     is (spec §3.2) rather than smoothed away.
///
///     **THE MILESTONE FALLS THE DAY AFTER THE LAST RUNG'S WEEK, and that
///     is not an off-by-one.** The eight training weeks run Sunday
///     2026-08-23 through Saturday 2026-10-17; the milestone is Sunday
///     2026-10-18, the morning the block closes over into. A date-carrying
///     milestone means "by the end of the block", so the last week is a week
///     the athlete still has, not one already spent.
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
    ///
    /// **THE `…c` RANGE, NOT `…b`** (review finding 7). These three were
    /// `…b1/…b2/…b3`, which is `WeeklyGoalFixtures`' bench/squat/deadlift —
    /// so the stub's *user* and the catalog's *bench press* were the same
    /// id, and a Stream D builder resolving `goal.target.exerciseID` against
    /// the fixture world would have got the fixture athlete or nothing at
    /// all. `…c4` is already `WeeklyGoalFixtures.editorUserID`; `c1`–`c3`
    /// were free.
    static let fixtureUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000c1") ?? UUID()
    static let fixtureGoalID = UUID(uuidString: "00000000-0000-0000-0000-0000000000c2") ?? UUID()
    static let fixtureEnrollmentID = UUID(uuidString: "00000000-0000-0000-0000-0000000000c3") ?? UUID()

    /// **THE FIXTURE WORLD'S OWN BENCH PRESS**, by reference rather than by
    /// a literal that happens to match.
    ///
    /// The stub's goal is a bench goal ("Bench 225 by Oct 18") and the
    /// catalog's bench press is `WeeklyGoalFixtures.benchPressID`. They used
    /// to be different lifts, which is the whole of what ruling 3's "one
    /// world" is against: a frame could show a bench milestone above a lift
    /// picker with the bench unselected and nothing would look wrong.
    /// Pointing at the constant rather than copying its digits means
    /// renumbering that world moves this with it.
    static let fixtureExerciseID = WeeklyGoalFixtures.benchPressID

    /// **2026-08-24, a Monday** — the block's start. A fixture, not a clock.
    static let fixtureCreatedAt = utcDate(year: 2026, month: 8, day: 24)
    /// **2026-10-18, a SUNDAY** — the milestone date the spec names, and the
    /// date `fixturePage.dateLine` spells out as `Sunday 18 October`.
    static let fixtureByDate = utcDate(year: 2026, month: 10, day: 18)

    /// A calendar date at midnight UTC, built from its COMPONENTS rather
    /// than from an epoch literal.
    ///
    /// The two literals this replaced were wrong, silently, and had been
    /// restated as the fixture's contract in the doc block above without
    /// anyone converting them back: `1_787_745_600` is 2026-08-**26** (a
    /// Wednesday) where the comment claimed the 24th, and `1_792_411_200` is
    /// 2026-10-**19** (a Monday) where both the comment and the page's own
    /// `dateLine` say Sunday the 18th. Nothing in the app would have caught
    /// it until a stream stopped hard-coding the date line and formatted
    /// `fixtureGoal.byDate` instead — at which point the frame would have
    /// read "Monday 19 October" beside a headline saying "Oct 18", and the
    /// formatter would have been blamed.
    ///
    /// An epoch is unreadable and therefore unreviewable. Components are
    /// both, and `BlockGoalModelTests` now pins the weekday as well.
    private static func utcDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        // NOON UTC, not midnight: a device-local formatter in any timezone from
        // UTC-11 to UTC+11 then still prints the same calendar day, so the
        // fixture's "Sunday 18 October" survives a simulator in Los Angeles.
        // (Only UTC+12/+13 — Auckland in October — would roll it to the 19th.)
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }

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
