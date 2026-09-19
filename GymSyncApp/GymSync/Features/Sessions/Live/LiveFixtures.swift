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

/// One catalog world for `TogetherClockView` (plan task S9).
struct TogetherWorld {
    let kicker: String
    let title: String
    let intervalKicker: String
    let phase: String
    let phaseDetail: String
    let readout: String
    let progress: Double
    let nextLine: String
    let lanes: [TogetherLane]
    let axisStart: String
    let axisEnd: String
    let dockNames: [String]
    /// The pills ride with the dock (final review, finding 6), so the frame
    /// that proves Together's foot has to carry them too.
    let reactionEmojis: [String]
}

/// One catalog world for `FreestyleRailView` (plan task S10).
struct FreestyleWorld {
    let kicker: String
    let title: String
    let rail: FreestyleRailModel
    let restElapsed: String
    let standing: FreestylePace.Standing
    var stretchSuggestion: FreestyleSuggestion? = nil
    var accessorySuggestion: FreestyleSuggestion? = nil
    var behindLine: String? = nil
}

/// One catalog world for the LIVE BODY ITSELF (plan task S4) — the only
/// world here that drives `SessionLiveView` rather than one of the value-in
/// pages beneath it.
///
/// IT CARRIES NO ROSTER, DELIBERATELY. `SessionLiveView.participants` is
/// `[(SessionParticipant, Profile)]` and both of those replace their
/// synthesized memberwise init with `init(from:)` — they are decode-only
/// types, which is the same fact `LobbyFixtures`' own header records about
/// `LobbyWorld`. So the world names the COUNT the header rail prints
/// (`rosterCount`) and leaves the array empty, which is also what keeps the
/// my-turn page on screen: `showsCrewPage` requires a non-empty roster.
///
/// NO CLOCK IS REACHABLE FROM IT (constraint 11). `startedAt` and
/// `currentTurnStartedAt` are deliberately nil — see `LiveFixtures.yourTurn`.
struct LiveWorld {
    /// Carries the style too, so `SessionLiveView.init(catalog:)` needs no
    /// second argument that could disagree with it.
    let session: WorkoutSession
    /// Whose turn it is, and who is reading — a capture has no signed-in
    /// profile, so the world states it.
    let selfID: UUID
    let routineName: String
    let routineExercises: [RoutineExercise]
    /// The exercises those rows name. Only these are resolvable: the live
    /// view looks every name up in this array.
    let allExercises: [Exercise]
    /// Already-logged sets, `logged_at` ASC — `allSessionSets`' own order.
    let sets: [SetLog]
    /// What the header rail's people-count prints.
    let participantCount: Int
    /// The vitals card's reading, past `heartRateFor(_:)`'s freshness gate
    /// rather than through it.
    let heartRate: Reading?
    /// The entry card, pre-filled — `prefillLogInputs()` is a repository-fed
    /// derivation, so a capture states what it would have produced.
    let logReps: String
    let logWeight: String
    let logRPE: Double

    /// DEBUG-only rest-window override (plan task S6, frame 156) for
    /// `SessionLiveView.freestyleScreen`'s rest card. `RoundCopy.elapsed
    /// (since:now:)` computes against a live `TimelineView` tick — the
    /// engine every `.freestyle` catalog frame ticks on, not something this
    /// world can seed away — so the one fixture value that cannot drift with
    /// the day the screenshot is taken is the RENDERED STRING itself: the
    /// same idiom `RoundWaitWorld.rest.elapsed`/`FreestyleWorld.restElapsed`
    /// already use. `nil` in every existing world, which keeps
    /// `session-your-turn` and `session-solo-live` byte-identical.
    var restElapsedOverride: String? = nil

    /// DEBUG-only self-swap seed (plan task S6, frame 157): `[slotID:
    /// SessionLiveView.SwapTarget]`, seeded into `selfScales[selfID]` at
    /// `init(catalog:)` — the same idiom `logReps`/`logWeight`/`logRPE`
    /// already use to seed other `@State`. `RoutineLayering.apply` (the pure
    /// function `effectiveRoutineExercises` already delegates to) reads it
    /// exactly as it reads a durable row's `self_swaps`; no repository, no
    /// broadcast, no production seam. Empty in every existing world, which
    /// keeps `effectiveRoutineExercises` resolving the UNSWAPPED routine for
    /// `session-your-turn` and `session-solo-live`.
    var selfSwaps: [UUID: SessionLiveView.SwapTarget] = [:]

    struct Reading: Equatable {
        let bpm: Int
        let zone: HeartRateZone?
    }
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
    /// Tappable by any crewmate now (ruling R-B13, fix-forward
    /// `20260913000107`) — `SkipOffer` no longer carries an
    /// organizer-only flag.
    static let skipOffer = SkipOffer(
        name: "Sam",
        waited: 151,
        threshold: RoundHold.threshold(medianRestSeconds: 96))

    // MARK: - Spotter mode (frame 139)

    /// `session-round-spotter`: round 4, Dana lifting, Lee next, and the
    /// crew's live readings across all four zones — a frame that showed one
    /// zone would prove nothing about the ramp.
    ///
    /// The bpm values are the design round's own readings (`Variations/`,
    /// retired by plan task S10); the ZONES come from `HeartRateZone.zone(bpm:)`
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

    // MARK: - The quiet scale-down (frame 143, plan task S2)

    /// `session-scale-down`: SAM IS ON A GOBLET SQUAT AND NOBODY WAS TOLD.
    ///
    /// The spotter world with the rotation re-ordered so Sam holds the turn,
    /// and his tile — and only his — carrying the `doing` line spec §3.4
    /// mode 2 adds. No banner, no badge, no colour, and nothing on anyone
    /// else's tile: the whole point of mode 2 is that a scale-down is a fact
    /// the crew can see, not an announcement it has to receive.
    ///
    /// IT IS A `SpotterWorld`, AND THE PLAN'S FRAME TABLE SAYS `RoundWaitView`
    /// — a discrepancy this task records rather than papers over.
    /// `RoundWaitView` mounts `StationCard`s and NO `TurnStrip`; `SpotterView`
    /// is the strip's only mount in the app. The station-card half of mode 2
    /// has shipped since plan task S6 and is already on frame 137 (see
    /// `rackA`, where Sam carries `scaleDown: "Goblet squat"`), so the half
    /// that needed a frame is this one. S10 renders `SpotterView` here, or
    /// the plan gives `RoundWaitView` a strip of its own.
    static let scaleDown = SpotterWorld(
        kicker: RoundCopy.kicker(crew: crewName, round: 4),
        title: "You're spotting",
        turn: [
            TurnStrip.Tile(id: samID, label: "NOW", name: "Sam", isNow: true,
                           doing: "Goblet squat"),
            TurnStrip.Tile(id: leeID, label: "NEXT", name: "Lee", isNow: false),
            TurnStrip.Tile(id: danaID, label: "3RD", name: "Dana", isNow: false),
            TurnStrip.Tile(id: alexID, label: "4TH", name: "You", isNow: false),
        ],
        stillToGo: RoundCopy.stillToGo(2),
        crew: [
            crewRow(samID, "Sam Obi", isLifting: true, bpm: 143),
            crewRow(leeID, "Lee Vance", isLifting: false, bpm: 121),
            crewRow(danaID, "Dana Kord", isLifting: false, bpm: 158),
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

    // MARK: - Together (frame 140)

    /// The design round's own twelve-slot traces: rounds 1-6 recorded, 7-12
    /// still empty, which is what a session six intervals in looks like. The
    /// empty slots are `0` and the timeline draws them as empty rather than
    /// as nothing, so the four lanes keep one axis.
    static let togetherLanes: [TogetherLane] = [
        lane(alexID, "You",  trace: [118, 141, 152, 158, 163, 168, 0, 0, 0, 0, 0, 0]),
        lane(danaID, "Dana", trace: [112, 132, 143, 149, 151, 154, 0, 0, 0, 0, 0, 0]),
        lane(samID,  "Sam",  trace: [124, 148, 161, 168, 172, 176, 0, 0, 0, 0, 0, 0]),
        lane(leeID,  "Lee",  trace: [104, 121, 128, 134, 137, 139, 0, 0, 0, 0, 0, 0]),
    ]

    /// The live reading is the LAST recorded slot, and the zone is derived
    /// from it — a lane cannot disagree with its own trace. Every PAST
    /// sample gets the same treatment (fix round 3 / F7): each bpm here is
    /// a FIXTURE'S OWN invented number, so deriving its own zone the same
    /// way is self-consistent — unlike live code, which never recomputes
    /// another participant's broadcast zone, a fixture has no broadcast to
    /// defer to in the first place.
    private static func lane(_ id: UUID, _ name: String, trace rawTrace: [Int]) -> TogetherLane {
        let bpm = rawTrace.last(where: { $0 > 0 })
        let samples = rawTrace.map { value in
            value > 0 ? TogetherTrace.Sample(bpm: value, zone: HeartRateZone.zone(bpm: value))
                      : TogetherTrace.Sample.empty
        }
        return TogetherLane(id: id, name: name, bpm: bpm,
                            zone: bpm.map { HeartRateZone.zone(bpm: $0) },
                            trace: samples)
    }

    /// Twelve fixed intervals, one minute each, WORK (Z4) and RECOVER (Z2)
    /// alternating — `TogetherIntervals.Interval.minutes` is WHOLE MINUTES
    /// only (`cardio_minutes`), so a sub-minute "40s work / 20s rest"
    /// scheme is not expressible and this fixture does not pretend
    /// otherwise (fix round 3 / F8: the previous version's title, "HIIT ·
    /// 40 / 20", described a shape `TogetherIntervals.plan` could never
    /// produce). Fixed ids per constraint 11.
    static let togetherIntervalPlan: [TogetherIntervals.Interval] = (0..<12).map { index in
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000009\(String(format: "%02d", index))") ?? UUID()
        let isWork = index % 2 == 1
        return TogetherIntervals.Interval(id: id, name: isWork ? "Work" : "Recover",
                                          zone: isWork ? 4 : 2, minutes: 1)
    }

    /// 5 whole intervals (300 s) + 42 s into the sixth — lands exactly on
    /// interval index 5 (the sixth, "Work", Z4) with 18 s left of its 60 s
    /// length, `0:18` on the clock.
    static let togetherElapsed: TimeInterval = 5 * 60 + 42

    /// `session-together-clock` (frame 140): interval 6 of 12, 18 s left,
    /// four hearts on one axis.
    ///
    /// EVERY NUMBER BELOW IS DERIVED from `togetherIntervalPlan` and
    /// `togetherElapsed` through `TogetherIntervals.position(in:elapsed:)`
    /// — the SAME pure law `SessionLiveView.togetherScreen(now:)` calls in
    /// production — so this fixture cannot drift into the impossible
    /// triple (interval length, elapsed and progress disagreeing) the
    /// hand-typed version shipped (fix round 3 / F8). Nothing here is a
    /// literal except the plan and the elapsed time themselves.
    static let together: TogetherWorld = {
        let position = TogetherIntervals.position(in: togetherIntervalPlan, elapsed: togetherElapsed)
            ?? TogetherIntervals.Position(index: 0, elapsedInInterval: 0, remaining: 0, progress: 0)
        let current = togetherIntervalPlan.indices.contains(position.index)
            ? togetherIntervalPlan[position.index] : nil
        let next = togetherIntervalPlan.indices.contains(position.index + 1)
            ? togetherIntervalPlan[position.index + 1] : nil
        return TogetherWorld(
            kicker: "PUSH CREW · TOGETHER",
            title: "HIIT",
            intervalKicker: RoundCopy.intervalKicker(index: position.index, count: togetherIntervalPlan.count),
            phase: (current?.name ?? TogetherIntervals.openIntervalName).uppercased(),
            phaseDetail: current?.detail ?? "",
            readout: RoundCopy.clock(position.remaining ?? position.elapsedInInterval),
            progress: position.progress,
            nextLine: RoundCopy.nextInterval(next.map { $0.detail.isEmpty ? $0.name : $0.detail }),
            lanes: togetherLanes,
            axisStart: RoundCopy.intervalKicker(index: 0, count: togetherIntervalPlan.count),
            axisEnd: RoundCopy.intervalKicker(index: togetherIntervalPlan.count - 1,
                                              count: togetherIntervalPlan.count),
            dockNames: dockNames,
            reactionEmojis: reactionEmojis)
    }()

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

    // MARK: - Freestyle (frame 141)

    /// You (Alex), Dana, Lee and Sam — the design round's own four
    /// (`SessionVariationKit.freestyleRail`), out of 18 sets on the plan.
    /// You are 3 ahead of the crew's slowest (Sam, 11), which is what puts
    /// both suggestions on the frame.
    static let freestyleRail = FreestyleRailModel(
        lifters: [
            FreestyleRailModel.Lifter(id: alexID, name: "You", isYou: true, setsDone: 14),
            FreestyleRailModel.Lifter(id: danaID, name: "Dana", isYou: false, setsDone: 12),
            FreestyleRailModel.Lifter(id: leeID, name: "Lee", isYou: false, setsDone: 12),
            FreestyleRailModel.Lifter(id: samID, name: "Sam", isYou: false, setsDone: 11),
        ],
        totalSets: 18)

    // MARK: - The crew's routine change (frame 142, plan task S1)

    /// Two exercise ids, fixed for the same reason the lifters' are.
    static let backSquatID = UUID(uuidString: "00000000-0000-0000-0000-0000000001c1") ?? UUID()
    static let gobletSquatID = UUID(uuidString: "00000000-0000-0000-0000-0000000001c2") ?? UUID()

    /// `session-swap-consent` (frame 142): Dana proposes back squat → goblet
    /// squat for the whole crew; two of four present lifters have agreed and
    /// I have not answered, which is the only state that draws the answers.
    ///
    /// The PROPOSED door's load line carries no weight, deliberately: a
    /// squad swap inherits the row's sets and reps and drops `targetWeight`
    /// (`SessionLiveView.effectiveRoutineExercises`), so a proposed door
    /// that repeated `@ 225` would promise a prescription the swap does not
    /// produce.
    static let swapConsent = SwapConsentCard.Model(
        proposerName: "Dana",
        from: SwapConsentCard.Door(exerciseID: backSquatID,
                                   name: "Back squat",
                                   detail: "4 × 5 @ 225"),
        to: SwapConsentCard.Door(exerciseID: gobletSquatID,
                                 name: "Goblet squat",
                                 detail: "4 × 5"),
        crewSize: 4,
        agreed: 2,
        agreedNames: ["Dana", "Lee"],
        iHaveAnswered: false)

    // MARK: - Rounds, your turn (frame 145, plan task S4)

    private static let liveSessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000001d0") ?? UUID()
    private static let liveGroupID   = UUID(uuidString: "00000000-0000-0000-0000-0000000001d1") ?? UUID()
    private static let liveRoutineID = UUID(uuidString: "00000000-0000-0000-0000-0000000001d2") ?? UUID()
    private static let rdlID         = UUID(uuidString: "00000000-0000-0000-0000-0000000001c3") ?? UUID()
    private static let legPressID    = UUID(uuidString: "00000000-0000-0000-0000-0000000001c4") ?? UUID()
    private static let lungeID       = UUID(uuidString: "00000000-0000-0000-0000-0000000001c5") ?? UUID()

    /// Noon UTC from components — `LobbyFixtures.utcDate`'s own idiom, the
    /// only hour that survives a simulator anywhere from UTC-11 to UTC+11
    /// printing the same calendar day. Never `Date()`, never an epoch
    /// literal (constraint 11).
    private static func utcDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month,
                                                  day: day, hour: hour))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// The four exercises the live body can name. The current one is a
    /// BARBELL movement on purpose: `turnVitalsRow`'s second slot is LOAD THE
    /// BAR for barbell work and LAST TIME otherwise, and LAST TIME's meta
    /// line ("6 DAYS AGO") is computed against `Date()`.
    static let liveExercises: [Exercise] = [
        Exercise(id: backSquatID, name: "Back squat", slug: "back-squat",
                 category: "compound", primaryMuscle: "quads",
                 secondaryMuscles: ["glutes", "core"], equipment: "barbell",
                 defaultUnit: "lb", demoVideoURL: nil),
        Exercise(id: rdlID, name: "Romanian deadlift", slug: "romanian-deadlift",
                 category: "compound", primaryMuscle: "hamstrings",
                 secondaryMuscles: ["glutes"], equipment: "barbell",
                 defaultUnit: "lb", demoVideoURL: nil),
        Exercise(id: legPressID, name: "Leg press", slug: "leg-press",
                 category: "compound", primaryMuscle: "quads",
                 secondaryMuscles: ["glutes"], equipment: "machine",
                 defaultUnit: "lb", demoVideoURL: nil),
        Exercise(id: lungeID, name: "Walking lunge", slug: "walking-lunge",
                 category: "compound", primaryMuscle: "quads",
                 secondaryMuscles: ["glutes"], equipment: "dumbbell",
                 defaultUnit: "lb", demoVideoURL: nil),
    ]

    /// The same leg day `plan` words, as the routine rows the live body
    /// actually reads. Fixed row ids, reused from `plan` so one session is
    /// described once.
    static let liveRoutineExercises: [RoutineExercise] = [
        RoutineExercise(id: squatRowID, routineID: liveRoutineID, exerciseID: backSquatID,
                        position: 1, targetSets: 4, targetReps: "5",
                        targetWeight: "225", restSeconds: 150, notes: nil),
        RoutineExercise(id: rdlRowID, routineID: liveRoutineID, exerciseID: rdlID,
                        position: 2, targetSets: 3, targetReps: "8",
                        targetWeight: "185", restSeconds: 120, notes: nil),
        RoutineExercise(id: pressRowID, routineID: liveRoutineID, exerciseID: legPressID,
                        position: 3, targetSets: 3, targetReps: "10",
                        targetWeight: "270", restSeconds: 120, notes: nil),
        RoutineExercise(id: lungeRowID, routineID: liveRoutineID, exerciseID: lungeID,
                        position: 4, targetSets: 3, targetReps: "20",
                        targetWeight: nil, restSeconds: 90, notes: nil),
    ]

    /// Two of four back squats already logged, so the entry card reads
    /// `3 OF 4` and the SETS page has two columns behind the live one.
    /// `loggedAt` is a fixture date and is not rendered on this page — the
    /// only reader of a `loggedAt` here is `turnSetsPage`'s ORDER.
    static let liveSets: [SetLog] = [
        SetLog(id: UUID(uuidString: "00000000-0000-0000-0000-0000000001e1") ?? UUID(),
               userID: alexID, sessionID: liveSessionID, exerciseID: backSquatID,
               setIndex: 1, reps: 5, weight: 225, rpe: 7,
               isFailed: false, isPenalty: false, note: nil,
               loggedAt: utcDate(year: 2026, month: 9, day: 16, hour: 18)),
        SetLog(id: UUID(uuidString: "00000000-0000-0000-0000-0000000001e2") ?? UUID(),
               userID: alexID, sessionID: liveSessionID, exerciseID: backSquatID,
               setIndex: 2, reps: 5, weight: 225, rpe: 8,
               isFailed: false, isPenalty: false, note: nil,
               loggedAt: utcDate(year: 2026, month: 9, day: 16, hour: 19)),
    ]

    /// `session-your-turn` (frame 145): Rounds, round 2, the turn is mine.
    ///
    /// NO CLOCK, ANYWHERE (constraint 11). `startedAt` and
    /// `currentTurnStartedAt` are NIL rather than dates built from
    /// components, and that is a deliberate departure from the plan's
    /// wording: both are rendered as `Text(date, style: .timer)`, a LIVE
    /// counter, so any non-nil value makes the frame differ from itself
    /// between two runs. Nil takes the header rail's clock off the rail
    /// (its `if` requires the date) and prints the entry card's turn clock
    /// as an em dash — which is what a session with no turn stamp honestly
    /// shows, and it needed no edit to either surface.
    ///
    /// `liftingStartedAt` is nil for the same reason it is on every other
    /// world here: the round wait's own derivations measure from it, and the
    /// my-turn page reads it not at all.
    static let yourTurn = LiveWorld(
        session: WorkoutSession(
            id: liveSessionID,
            routineID: liveRoutineID,
            organizerID: danaID,
            state: "in_progress",
            startedAt: nil,
            completedAt: nil,
            createdAt: utcDate(year: 2026, month: 9, day: 16),
            groupID: liveGroupID,
            roomCode: nil,
            scheduledFor: utcDate(year: 2026, month: 9, day: 16, hour: 18),
            seriesID: nil,
            currentTurnUserID: alexID,
            currentTurnStartedAt: nil,
            style: .rounds,
            round: 2),
        selfID: alexID,
        routineName: rungLine,
        routineExercises: liveRoutineExercises,
        allExercises: liveExercises,
        sets: liveSets,
        participantCount: 4,
        heartRate: LiveWorld.Reading(bpm: 142, zone: HeartRateZone.zone(bpm: 142)),
        // What `prefillLogInputs()` would have produced from the two logged
        // sets: the routine's rep target, and the same load at RPE 8 (which
        // `SetProgression` holds rather than steps).
        logReps: "5",
        logWeight: "225",
        logRPE: 7.0)

    // MARK: - The ad-hoc solo session (frame 155, plan task S6)

    private static let soloLiveSessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000001f0") ?? UUID()

    /// `session-solo-live` (frame 155): an ad-hoc solo session in the one
    /// body — `.freestyle`, a roster of one, the entry card up.
    ///
    /// `groupID`/`roomCode`/`scheduledFor` are all nil —
    /// `SoloSessionShape.isSoloByConstruction`'s own triple (decision 1) —
    /// so `hidesCrewFurniture` answers true from the session alone, before
    /// any roster is even read; `participantCount: 1` is the honest roster
    /// reading on top of it.
    ///
    /// `sets: []`, DELIBERATELY. `SessionLiveView.freestylePage` ticks on
    /// `TimelineView(.periodic(from: .now, by: 1))` and computes
    /// `restElapsed: RoundCopy.elapsed(since: myLastLoggedAt, now:)` — but
    /// `RoundCopy.elapsed` returns the FIXED string `"0:00"` whenever its
    /// `since` is nil, and `myLastLoggedAt` is nil exactly when this lifter
    /// has no logged sets. An empty `sets` array is the one fixture choice
    /// that keeps this frame's rendered text independent of the day the
    /// screenshot is taken (constraint 11's "no Date.now reachable" — the
    /// TimelineView tick is production's, not this builder's, but the
    /// fixture still must not let a live clock show through it). The
    /// routine and its exercises are `liveRoutineExercises`/`liveExercises`
    /// (frame 145's own world) reused verbatim — only the session shape,
    /// the style and the empty sets change.
    ///
    /// `LiveWorld` carries no roster (its own header) — `presentRotation` is
    /// derived from `participants`, a `@State` that a catalog world never
    /// seeds — so `FreestyleRailView`'s rail draws no lifter rows here,
    /// exactly as it draws none for `session-your-turn` (145). That is the
    /// existing fixture limitation, not a new one.
    ///
    /// WHAT THIS FRAME NOW PROVES, after the solo-wording round (the render
    /// is what found it): the header reads `PUSH A` over `Back squat` — the
    /// routine, and the lift the entry card is about to log, which the page
    /// named nowhere before; the rail card reads `SETS DONE · 0 OF 13` (the
    /// routine's own 4+3+3+3, none logged in this world) with no crew word
    /// and no legend; and the button reads `LOG SET`, because there is
    /// nobody to pass to. None of that needed a fixture change — every value
    /// is derived from the world this frame already carried, which is the
    /// point: the page had the truth and was not saying it.
    static let soloLive = LiveWorld(
        session: WorkoutSession(
            id: soloLiveSessionID,
            routineID: liveRoutineID,
            organizerID: alexID,
            state: "in_progress",
            startedAt: nil,
            completedAt: nil,
            createdAt: utcDate(year: 2026, month: 9, day: 16),
            groupID: nil,
            roomCode: nil,
            scheduledFor: nil,
            seriesID: nil,
            currentTurnUserID: nil,
            currentTurnStartedAt: nil,
            style: .freestyle),
        selfID: alexID,
        routineName: "Push A",
        routineExercises: liveRoutineExercises,
        allExercises: liveExercises,
        sets: [],
        participantCount: 1,
        heartRate: nil,
        logReps: "5",
        logWeight: "225",
        logRPE: 7.0)

    /// `session-solo-rest` (frame 156): the SAME solo world at rest — the
    /// rest card reading a fixture elapsed time instead of "0:00".
    /// `restElapsedOverride` is the only difference from `soloLive`; see its
    /// own doc comment on `LiveWorld` for why a literal string, not a
    /// `Date`, is the fixture-safe way to show it. The header, the rail card
    /// and the button therefore read exactly as they do in 155 — `PUSH A` /
    /// `Back squat`, `SETS DONE · 0 OF 13`, `LOG SET` — over a rest that is
    /// running.
    static let soloRest = LiveWorld(
        session: WorkoutSession(
            id: soloLiveSessionID,
            routineID: liveRoutineID,
            organizerID: alexID,
            state: "in_progress",
            startedAt: nil,
            completedAt: nil,
            createdAt: utcDate(year: 2026, month: 9, day: 16),
            groupID: nil,
            roomCode: nil,
            scheduledFor: nil,
            seriesID: nil,
            currentTurnUserID: nil,
            currentTurnStartedAt: nil,
            style: .freestyle),
        selfID: alexID,
        routineName: "Push A",
        routineExercises: liveRoutineExercises,
        allExercises: liveExercises,
        sets: [],
        participantCount: 1,
        heartRate: nil,
        logReps: "5",
        logWeight: "225",
        logRPE: 7.0,
        restElapsedOverride: "3:15")

    /// The goblet squat `Exercise` the swap below substitutes in — a real
    /// object, not just the `SwapConsentCard.Door` text `swapConsent`
    /// already carries, so `allExercises.first(where:)` resolves a name
    /// for the swapped slot exactly as it would for a durable row.
    static let gobletSquatExercise = Exercise(
        id: gobletSquatID, name: "Goblet squat", slug: "goblet-squat",
        category: "compound", primaryMuscle: "quads",
        secondaryMuscles: ["glutes", "core"], equipment: "dumbbell",
        defaultUnit: "lb", demoVideoURL: nil)

    /// `session-solo-swap` (frame 157): the same solo world with slot 1
    /// (Back squat) swapped to Goblet squat — the RESULT, not the sheet:
    /// `groupSwapSheet`'s suggestions come from a live
    /// `ExerciseSubstitutionRepository` call (constraint 11), so this
    /// photographs what a completed swap looks like on the page itself,
    /// exactly the way `content_sessionScaleDown`'s "one lifter on a
    /// different exercise, nothing announced" already reads for the crew.
    /// `selfSwaps` is seeded into `selfScales[selfID]` at `init(catalog:)`
    /// and read by the SAME `RoutineLayering.apply` a durable row goes
    /// through — no repository, no broadcast.
    ///
    /// AND THE HEADER IS WHERE THE SWAP IS NOW LEGIBLE: the swapped slot is
    /// the current one (position 1, nothing logged), so the page's title
    /// resolves through `effectiveRoutineExercises` and reads `Goblet squat`,
    /// not `Back squat`. That is the whole difference between this frame and
    /// 155 in one line of copy — the previous render said "Own pace" in both
    /// and photographed a swap nobody could see.
    static let soloSwap = LiveWorld(
        session: WorkoutSession(
            id: soloLiveSessionID,
            routineID: liveRoutineID,
            organizerID: alexID,
            state: "in_progress",
            startedAt: nil,
            completedAt: nil,
            createdAt: utcDate(year: 2026, month: 9, day: 16),
            groupID: nil,
            roomCode: nil,
            scheduledFor: nil,
            seriesID: nil,
            currentTurnUserID: nil,
            currentTurnStartedAt: nil,
            style: .freestyle),
        selfID: alexID,
        routineName: "Push A",
        routineExercises: liveRoutineExercises,
        allExercises: liveExercises + [gobletSquatExercise],
        sets: [],
        participantCount: 1,
        heartRate: nil,
        logReps: "5",
        logWeight: "225",
        logRPE: 7.0,
        selfSwaps: [squatRowID: SessionLiveView.SwapTarget(id: gobletSquatID, name: "Goblet squat")])

    /// `session-freestyle-rail` (frame 141): the rail, the stretched rest,
    /// and Coach's accessory — both suggestions, because the frame is built
    /// to show the crew's ahead branch (`round-wait-v2`'s sister frame 116
    /// was the same choice).
    static let freestyle = FreestyleWorld(
        kicker: "\(crewName.uppercased()) · FREESTYLE",
        title: RoundCopy.freestyleTitle,
        rail: freestyleRail,
        restElapsed: "2:30",
        standing: .ahead(by: 3),
        stretchSuggestion: FreestyleSuggestion(
            kicker: RoundCopy.freestyleStretchKicker,
            sentence: RoundCopy.freestyleStretchSentence(setsAhead: 3)),
        accessorySuggestion: FreestyleSuggestion(
            kicker: RoundCopy.freestyleAccessoryKicker,
            sentence: RoundCopy.freestyleAccessorySentence(name: "Face pulls", prescription: "3 × 12")))
}
