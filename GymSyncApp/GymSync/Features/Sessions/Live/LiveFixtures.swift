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
