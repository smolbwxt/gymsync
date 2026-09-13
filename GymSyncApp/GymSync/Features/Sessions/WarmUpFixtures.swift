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
    let coachLine: String?
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
        // Coach's readiness suggestion is Phase B: production always passes
        // nil (`SessionRunnerView.swift`), so the frame shows none either —
        // `SessionPlanCardWithSuggestion` renders with no suggestion and no
        // rule when `suggestion` is nil.
        coachLine: nil,
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
        // Coach's per-lifter warm-up line is Phase B: production always
        // passes nil (review push-5 R-17), so `CoachSuggestionBlock` does
        // not render on this frame either.
        coachLine: nil,
        blockWeek: 3,
        blockWeeks: 8,
        blockMilestone: "",
        elapsed: "6:38")
}
