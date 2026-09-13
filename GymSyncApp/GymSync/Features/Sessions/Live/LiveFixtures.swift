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
    /// Nil in the ordinary round wait; frame 138 is the same world with it
    /// present (plan task S7).
    var skip: SkipOffer? = nil
}

/// One catalog world for `SpotterView` (plan task S8).
struct SpotterWorld {
    let kicker: String
    let title: String
    let turn: [TurnStrip.Tile]
    let stillToGo: String
    let crew: [CrewHeartRatesCard.Row]
    let coach: CoachDoorRow.Model
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

    /// Rack B in the HOLD world (frame 138): Lee has logged too, so Sam is
    /// the ONE lifter still out. `RoundHold.holdStartedAt` returns nil while
    /// two are outstanding, so a frame that showed the offer over an unticked
    /// Lee would contradict the law it is meant to illustrate.
    static let rackBHold = StationCard.Model(
        name: "RACK B",
        lifters: [
            StationCard.Lifter(id: leeID, name: "Lee Vance", isYou: false,
                               hasLogged: true, scaleDown: nil),
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

    /// `session-round-skip` (frame 138): THE SAME SCREEN with the quiet line
    /// present, and one lifter out instead of two — a crew waiting on two
    /// people is not being held by one, so a world that showed the offer over
    /// a two-name gate would contradict `RoundHold.holdStartedAt`.
    ///
    /// Sam is the one still resting. 151 s waited against a 144 s threshold:
    /// `RoundHold.threshold(medianRestSeconds: 96)` is `1.5 × 96 = 144`,
    /// between the 90 s floor and the 180 s cap, so the frame shows the
    /// multiplier doing the work rather than a clamp. `2:31` past `2:24`,
    /// which is the reference frame's own pair.
    ///
    /// `isActionable: true` — the frame is the organizer's, the one lifter
    /// the server lets move the crew on. See `SkipOfferLine`.
    static let skipOffer = SkipOffer(
        name: "Sam",
        waited: 151,
        threshold: RoundHold.threshold(medianRestSeconds: 96),
        isActionable: true)

    // MARK: - Spotter mode (frame 139)

    /// `session-round-spotter`: round 4, Dana lifting, Lee next, and the
    /// crew's live readings across all four zones — a frame that showed one
    /// zone would prove nothing about the ramp.
    ///
    /// The bpm values are the design round's own (`SVFixturesV2
    /// .spotterHeartRates`); the ZONES come from `HeartRateZone.zone(bpm:)`
    /// rather than being written down, so the frame cannot disagree with the
    /// app about what 158 is.
    static let spotter = SpotterWorld(
        kicker: RoundCopy.kicker(crew: crewName, round: 4),
        title: "You're spotting",
        turn: [
            TurnStrip.Tile(id: danaID, label: "NOW", name: "Dana", isNow: true),
            TurnStrip.Tile(id: leeID, label: "NEXT", name: "Lee", isNow: false),
            TurnStrip.Tile(id: samID, label: "3RD", name: "Sam", isNow: false),
            TurnStrip.Tile(id: alexID, label: "4TH", name: "You", isNow: false),
        ],
        stillToGo: RoundCopy.stillToGo(2),
        crew: [
            crewRow(danaID, "Dana Kord", isLifting: true, bpm: 158),
            crewRow(leeID, "Lee Vance", isLifting: false, bpm: 121),
            crewRow(samID, "Sam Obi", isLifting: false, bpm: 143),
            // Mo's watch stopped reporting: the freshness gate turns a stale
            // reading into nothing, and the card prints an em dash. The frame
            // carries the case on purpose — it is the one a screenshot proves
            // and a unit test cannot.
            crewRow(moID, "Mo Adeyemi", isLifting: false, bpm: nil),
        ],
        coach: coach,
        dockNames: dockNames,
        reactionEmojis: reactionEmojis)

    private static func crewRow(_ id: UUID, _ name: String,
                                isLifting: Bool, bpm: Int?) -> CrewHeartRatesCard.Row {
        CrewHeartRatesCard.Row(id: id, name: name, isLifting: isLifting,
                               bpm: bpm, zone: bpm.map { HeartRateZone.zone(bpm: $0) })
    }

    static let roundHold = RoundWaitWorld(
        kicker: RoundCopy.kicker(crew: crewName, round: 3),
        title: "The round",
        stations: [rackA, rackBHold],
        rest: rest,
        planKicker: planKicker,
        rungLine: rungLine,
        plan: plan,
        coach: coach,
        waitingOn: ["Sam"],
        dockNames: dockNames,
        reactionEmojis: reactionEmojis,
        skip: skipOffer)
}
