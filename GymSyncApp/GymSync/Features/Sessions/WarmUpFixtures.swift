import Foundation

// MARK: - WarmUpFixtures
//
// The catalog's two warm-up worlds (plan task S9, captured by S11's
// `session-warmup-solo` and `session-warmup-crew`).
//
// GLOBAL CONSTRAINT 11, as in `LobbyFixtures`: no repository and no
// `Date.now`. The elapsed clock is a STRING, not a computed interval, so the
// two frames read `4:12` on every run.
//
// The crew is `LobbyFixtures`' crew and the solo block is
// `StubBlockGoalRepository`'s block — one world across the round, so a
// reviewer reading the lobby frame and the warm-up frame is reading one
// gym.

/// One catalog world for `WarmUpScreen`.
struct WarmUpWorld {
    let session: WorkoutSession
    let warmthRows: [SessionWarmthRow]
    let isSolo: Bool
    let isOrganizer: Bool
    let planRows: [SessionPlanRow]
    let rungHeadline: String
    let rungDetail: String
    /// Coach's readiness suggestion (plan task S8). Nil on the two shipped
    /// frames, so neither moves; `suggestion` below is the one world that has
    /// one.
    let coachSuggestion: WarmUpReadiness.Suggestion?
    let blockWeek: Int
    let blockWeeks: Int
    let blockMilestone: String
    let elapsed: String
}

enum WarmUpFixtures {

    private static func utcDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month,
                                                  day: day, hour: hour))
            ?? Date(timeIntervalSince1970: 0)
    }

    static let startedAt = utcDate(year: 2026, month: 9, day: 14, hour: 18)

    private static func session(id: UUID, group: UUID?) -> WorkoutSession {
        WorkoutSession(
            id: id,
            routineID: nil,
            organizerID: LobbyFixtures.alexID,
            // `in_progress` with no `liftingStartedAt` — the one state
            // `WarmUpGate.isWarmingUp` answers true for.
            state: "in_progress",
            startedAt: startedAt,
            completedAt: nil,
            createdAt: LobbyFixtures.createdAt,
            groupID: group,
            roomCode: nil,
            scheduledFor: startedAt,
            seriesID: nil,
            currentTurnUserID: nil,
            currentTurnStartedAt: nil)
    }

    // MARK: - Solo (`session-warmup-solo`, frame 132)

    static let soloSessionID =
        UUID(uuidString: "00000000-0000-0000-0000-00000000f003") ?? UUID()

    /// `StubBlockGoalRepository`'s bench block, so the ladder page's frames
    /// and this one describe one block: bench 225 by Oct 18, week 3 of 8.
    static let soloPlanRows: [SessionPlanRow] = [
        SessionPlanRow(id: UUID(uuidString: "00000000-0000-0000-0000-00000000f031") ?? UUID(),
                       name: "Bench press", prescription: "4 × 5 @ 225", isCurrent: true),
        SessionPlanRow(id: UUID(uuidString: "00000000-0000-0000-0000-00000000f032") ?? UUID(),
                       name: "Incline dumbbell press", prescription: "3 × 10 @ 60"),
        SessionPlanRow(id: UUID(uuidString: "00000000-0000-0000-0000-00000000f033") ?? UUID(),
                       name: "Cable fly", prescription: "3 × 12 @ 40"),
        SessionPlanRow(id: UUID(uuidString: "00000000-0000-0000-0000-00000000f034") ?? UUID(),
                       name: "Overhead triceps", prescription: "3 × 12 @ 50"),
    ]

    /// **THE CHECKED-IN STATE**, matching the reference frame: no Check In
    /// control in the foot. The pre-check-in state is proven by
    /// `WarmUpScreenGateTests` rather than by a second capture — named as a
    /// deviation in the plan and in I1.
    static let solo = WarmUpWorld(
        session: session(id: soloSessionID, group: nil),
        warmthRows: [],
        isSolo: true,
        isOrganizer: true,
        planRows: soloPlanRows,
        // HONEST FRAMES (review push-5 R-17, the R-6 class): production's
        // rung headline is the routine's own name and nothing else
        // (`SessionRunnerView.swift`'s `routineName`) — a plausible title,
        // not a computed prescription sentence, matching
        // `LobbyFixtures.rungLine`'s "Leg Day A". `rungDetail` is always ""
        // in production; this fixture now says so too.
        rungHeadline: "Push Day A",
        rungDetail: "",
        // NIL IS THE NORMAL CASE (plan decision 4), and a warm-up with no
        // suggestion is the shipped screen — `SessionPlanCardWithSuggestion`
        // renders with no suggestion and no rule, so frame 132 does not move.
        coachSuggestion: nil,
        // NOT dishonest: `SessionRunnerView` now wires this from the
        // athlete's own active block goal (`BlockGoalRepository.activeGoal()`
        // → `.page(goalID:)`), so a lifter mid-block genuinely sees this —
        // matching `StubBlockGoalRepository`'s bench block the ladder page's
        // own frames describe (week 3 of 8, bench 225 by Oct 18).
        blockWeek: 3,
        blockWeeks: 8,
        blockMilestone: "Bench 225 by Oct 18",
        elapsed: "4:12")

    // MARK: - Crew (`session-warmup-crew`, frame 133)

    static let crewSessionID =
        UUID(uuidString: "00000000-0000-0000-0000-00000000f004") ?? UUID()

    private static func warmth(_ id: UUID, _ name: String, isWarm: Bool,
                               isYou: Bool = false) -> SessionWarmthRow {
        SessionWarmthRow(id: id, name: name, avatarURL: nil,
                         isYou: isYou, isWarm: isWarm)
    }

    /// Two of four warm, so the readiness row shows both marks — and the
    /// leader's note under `START LIFTING` names who is still going, which is
    /// the whole of spec §3.2's "the leader may move on, and it costs
    /// something".
    static let crew = WarmUpWorld(
        session: session(id: crewSessionID, group: LobbyFixtures.groupID),
        warmthRows: [
            warmth(LobbyFixtures.alexID, "Alex Rue", isWarm: true, isYou: true),
            warmth(LobbyFixtures.danaID, "Dana Kord", isWarm: true),
            warmth(LobbyFixtures.samID, "Sam Obi", isWarm: false),
            warmth(LobbyFixtures.leeID, "Lee Vance", isWarm: false),
        ],
        isSolo: false,
        isOrganizer: true,
        planRows: LobbyFixtures.planRows,
        rungHeadline: LobbyFixtures.rungLine,
        rungDetail: "",
        // None here either, so `crewBody` draws the plain `SessionPlanCard`
        // and frame 133 is byte-identical to the one B1 shipped. The crew
        // frame WITH a suggestion is `suggestion` below, its own world.
        coachSuggestion: nil,
        blockWeek: 3,
        blockWeeks: 8,
        blockMilestone: "",
        elapsed: "6:38")
}

// MARK: - Crew, with Coach's suggestion (`session-warmup-suggestion`)

extension WarmUpFixtures {

    /// `LobbyFixtures.planRows[0].id` — that row's own identity
    /// (`SessionPlanRow.id`, what production would call a
    /// `RoutineExercise.id`), not a `RoutineExercise.exerciseID` (the
    /// catalog exercise id `RoutineLayering.apply` actually matches a
    /// `TodaysScale.exerciseID` against). This catalog fixture has no
    /// separate `RoutineExercise` to carry that second id, so
    /// `suggestionForCrew` below deliberately stands in with the plan row's
    /// own id — referenced here, not re-typed, so the two cannot drift
    /// apart again the way the docket found them (docket: the fixture's raw
    /// UUID literal duplicated `f021` and only matched by coincidence).
    private static let backSquatPlanRowID = LobbyFixtures.planRows[0].id

    /// THE THIRD WARM-UP WORLD (plan task S8), for the id S10 mints.
    ///
    /// Its own frame rather than a switch inside frame 133: constraint 14
    /// freezes what 133 renders, and a suggestion is a state the crew frame
    /// does not otherwise have. The CREW frame carries it, because the crew is
    /// where `isPrivate` means something — spec §3.2's "the Coach line for each
    /// lifter privately" — and the solo card already photographs the same
    /// block's composition without the line.
    ///
    /// THE VALUES ARE THE RULE'S OWN OUTPUT, not free text: decision 4's one
    /// suggesting branch is an open probe on a muscle today trains, plus a mean
    /// RPE of 9 a day ago, against `LobbyFixtures.planRows`' four-set opener —
    /// which is a LEG day, so the sore muscle is quads and the row a set comes
    /// off is Back squat. Written as a literal because a fixture may not read a
    /// repository (constraint 11); `WarmUpReadinessTests` is what proves the
    /// rule produces exactly this shape.
    static let suggestionForCrew = WarmUpReadiness.Suggestion(
        exerciseID: backSquatPlanRowID,
        setsInstead: 3,
        read: "Your last session averaged RPE 9 yesterday, and you haven't marked quads recovered yet.",
        proposal: "Today is 4 × 5 on Back squat — want 3 × 5?")

    static let suggestion = WarmUpWorld(
        session: crew.session,
        warmthRows: crew.warmthRows,
        isSolo: false,
        isOrganizer: crew.isOrganizer,
        planRows: crew.planRows,
        rungHeadline: crew.rungHeadline,
        rungDetail: crew.rungDetail,
        coachSuggestion: suggestionForCrew,
        blockWeek: crew.blockWeek,
        blockWeeks: crew.blockWeeks,
        blockMilestone: crew.blockMilestone,
        elapsed: crew.elapsed)
}
