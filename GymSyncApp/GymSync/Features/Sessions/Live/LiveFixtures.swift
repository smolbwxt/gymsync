import Foundation

// MARK: - LiveFixtures
//
// The catalog's live-session worlds (plan tasks S6, S8, S9, S10), captured by
// S13 as `session-round-wait` (137), `session-round-skip` (138),
// `session-round-spotter` (139), `session-together-clock` (140) and
// `session-freestyle-rail` (141).
//
// GLOBAL CONSTRAINT 11: no live repository and no `Date.now` is reachable
// from a catalog builder. Every value below is a fixture integer, string or
// UUID — never `Date()`, never an epoch literal — and every id is fixed, so
// nothing in a screenshot diff moves between runs. This is `LobbyFixtures`'
// own contract, and this file follows it to the letter, including the reason
// its worlds are ALREADY WORDED: the live views are value-in, so a fixture
// that had to resolve an exercise name would need the 1,300-row catalog,
// which is exactly what constraint 11 forbids.
//
// THE CAST IS THE DESIGN ROUND'S — Alex, Dana, Sam, Lee, Mo, on Push Crew's
// leg day — so a production frame and the round frame it retires describe one
// crew rather than two that read alike. Where a value the design round pinned
// is one production CANNOT produce, the fixture prints what production would:
// the plan card's line is the ROUTINE'S NAME, not a per-lifter rung (the same
// honesty `LobbyFixtures.rungLine` records), and the Coach door carries the
// lobby's own two strings rather than a message count nothing fetches.

/// One catalog world for `RoundWaitView`.
struct RoundWaitWorld {
    let kicker: String
    let title: String
    let stations: [StationCard.Model]
    let rest: RestModel
    let planKicker: String
    let rungLine: String
    let plan: [SessionPlanRow]
    let coach: CoachDoorRow.Model
    let waitingOn: [String]
    let dockNames: [String]
    let reactionEmojis: [String]
}

enum LiveFixtures {

    // MARK: - Fixed ids

    static let alexID = UUID(uuidString: "00000000-0000-0000-0000-0000000001a1") ?? UUID()
    static let danaID = UUID(uuidString: "00000000-0000-0000-0000-0000000001a2") ?? UUID()
    static let samID  = UUID(uuidString: "00000000-0000-0000-0000-0000000001a3") ?? UUID()
    static let leeID  = UUID(uuidString: "00000000-0000-0000-0000-0000000001a4") ?? UUID()
    static let moID   = UUID(uuidString: "00000000-0000-0000-0000-0000000001a5") ?? UUID()

    /// Four plan-row ids, fixed for the same reason the lifters' are.
    private static let squatRowID  = UUID(uuidString: "00000000-0000-0000-0000-0000000001b1") ?? UUID()
    private static let rdlRowID    = UUID(uuidString: "00000000-0000-0000-0000-0000000001b2") ?? UUID()
    private static let pressRowID  = UUID(uuidString: "00000000-0000-0000-0000-0000000001b3") ?? UUID()
    private static let lungeRowID  = UUID(uuidString: "00000000-0000-0000-0000-0000000001b4") ?? UUID()

    // MARK: - The world's shared parts

    static let crewName = "Push Crew"

    /// The ROUTINE'S NAME, which is all production has for this line today —
    /// `LobbyView.planRungLine` is `routineInfo?.name` and nothing else, and
    /// the per-lifter rung is a later phase. An honest frame prints what
    /// production prints.
    static let rungLine = "Push Crew · leg day"

    static let planKicker = "THE SESSION · WHERE WE ARE"

    /// The whole session with the crew's progress on it. Back squat is
    /// current at two of four.
    static let plan: [SessionPlanRow] = [
        SessionPlanRow(id: squatRowID, name: "Back squat", prescription: "4 × 5 @ 225",
                       isCurrent: true, setsDone: 2, sets: 4),
        SessionPlanRow(id: rdlRowID, name: "Romanian deadlift", prescription: "3 × 8 @ 185",
                       setsDone: 0, sets: 3),
        SessionPlanRow(id: pressRowID, name: "Leg press", prescription: "3 × 10 @ 270",
                       setsDone: 0, sets: 3),
        SessionPlanRow(id: lungeRowID, name: "Walking lunge", prescription: "3 × 20 steps",
                       setsDone: 0, sets: 3),
    ]

    /// The lobby's own door, verbatim (spec §3.6 — one object in three
    /// places). No note: the crew's Pro standing is a server verdict that
    /// arrives ON TAP, and another member's `pro_until` is not readable at
    /// all, so a pre-tap "unlocked because Mo is Pro" line is a sentence
    /// production cannot write. Phase A ruled the identical question for the
    /// lobby's door.
    static let coach = CoachDoorRow.Model(title: SessionCopy.talkToCoach,
                                          detail: SessionCopy.talkToCoachDetail)

    static let dockNames = ["Sam Obi", "Dana Kord", "Lee Vance"]

    /// The live view's own four, in its own order — `reactionEmojis` in
    /// `SessionLiveView`. Content, not chrome (design rule 9's one exception).
    static let reactionEmojis = ["🔥", "💪", "😂", "👏"]

    // MARK: - The stations

    /// Rack A: you, Sam, Dana. Sam is lifting and carries spec §3.4 mode 2's
    /// quiet personal scale-down; you and Dana have logged this round.
    static let rackA = StationCard.Model(
        name: "RACK A",
        lifters: [
            StationCard.Lifter(id: alexID, name: "Alex Rue", isYou: true,
                               hasLogged: true, scaleDown: nil),
            StationCard.Lifter(id: samID, name: "Sam Obi", isYou: false,
                               hasLogged: false, scaleDown: "Goblet squat"),
            StationCard.Lifter(id: danaID, name: "Dana Kord", isYou: false,
                               hasLogged: true, scaleDown: nil),
        ],
        liftingID: samID)

    /// Rack B: Lee and Mo. Never deeper than three (owner decision 2), which
    /// is why a crew of five is two racks and not one queue.
    static let rackB = StationCard.Model(
        name: "RACK B",
        lifters: [
            StationCard.Lifter(id: leeID, name: "Lee Vance", isYou: false,
                               hasLogged: false, scaleDown: nil),
            StationCard.Lifter(id: moID, name: "Mo Adeyemi", isYou: false,
                               hasLogged: true, scaleDown: nil),
        ],
        liftingID: nil)

    // MARK: - The rest

    /// 128 falling to 96 across the rest, normalized the way
    /// `RecoveryBuffer.sparkline(barCount:)` normalizes: `(bpm − min) /
    /// (max − min)`, oldest first. Written out rather than computed so the
    /// frame is a literal, and so the shape is readable here.
    static let recoveryCurve: [Double] = [
        1.0, 0.90625, 0.78125, 0.625, 0.46875, 0.34375, 0.21875, 0.125, 0.0625, 0.0
    ]

    /// 96 bpm is Z1 against `HeartRateZone.defaultMaxBPM` — the endpoint dot
    /// and the number wear that zone's ink, and the caption carries the word.
    static let rest = RestModel(
        elapsed: "1:42",
        curve: recoveryCurve,
        bpm: 96,
        zone: HeartRateZone.zone(bpm: 96),
        nextPrescription: RoundCopy.nextPrescription(setNumber: 3,
                                                     targetSets: 4,
                                                     exercise: "Back squat",
                                                     prescription: "225 × 5"),
        achievability: RoundCopy.achievability(lastMoved: "225",
                                               target: "225",
                                               isUnderTarget: false))

    // MARK: - The worlds

    /// `session-round-wait` (frame 137): RACK A of three with Sam ringed,
    /// RACK B of two, the rest card, the plan, Coach's door, and the foot's
    /// gate on the two who have not logged.
    static let roundWait = RoundWaitWorld(
        kicker: RoundCopy.kicker(crew: crewName, round: 3),
        title: "The round",
        stations: [rackA, rackB],
        rest: rest,
        planKicker: planKicker,
        rungLine: rungLine,
        plan: plan,
        coach: coach,
        waitingOn: ["Sam", "Lee"],
        dockNames: dockNames,
        reactionEmojis: reactionEmojis)
}
