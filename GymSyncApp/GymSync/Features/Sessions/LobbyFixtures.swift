import Foundation

// MARK: - LobbyFixtures
//
// The catalog's three lobby worlds (plan task S7, captured by S11's
// `session-lobby-waiting`, `session-lobby-ready` and `session-lobby-late`).
//
// GLOBAL CONSTRAINT 11: no live repository and no `Date.now` is reachable from
// a catalog builder. Every value below is a fixture integer, string or a date
// built from COMPONENTS — never `Date()`, never an epoch literal — and every
// id is fixed, so nothing in a screenshot diff moves between runs.
//
// THE WORLD IS ALREADY WORDED. `LobbyWorld` carries `ArrivalRow`s and
// `SessionPlanRow`s rather than `SessionParticipant`/`Profile`/`RoutineExercise`
// rows, for two reasons that are the same reason: those three are DECODE-ONLY
// types (`Profile` and `SessionParticipant` both replace the synthesized
// memberwise init with `init(from:)`), and a `RoutineExercise` carries an
// exercise id that only the 1,300-row catalog can turn into "Back squat". A
// fixture that had to resolve names would need a repository, which is exactly
// what constraint 11 forbids.
//
// The cast is the design round's — Alex, Dana, Sam, Lee — so a production
// frame and the round frame it retires describe one crew rather than two that
// read alike.

/// One catalog world for `LobbyView`.
struct LobbyWorld {
    let session: WorkoutSession
    let groupName: String?
    /// Who is where, already staged. The lobby's `arrivalRows` returns this
    /// verbatim in catalog mode, so no `ArrivalLaw` input is needed and no
    /// presence socket is reachable.
    let rows: [ArrivalRow]
    /// The routine's own name, above the plan's rows — fix round 3 R-6:
    /// this used to read "Today's rung: Back squat 4 × 5 @ 225 · week 3 of
    /// 8", a line production cannot produce (`LobbyView.planRungLine` is
    /// `routineInfo?.name` and nothing else; the per-lifter rung is Phase
    /// B). HONEST FRAMES: the fixture prints what production actually
    /// would.
    let rungLine: String
    let planRows: [SessionPlanRow]
    /// Whether the frame is the leader's. `appState.currentProfile` is nil in
    /// a capture, so `isOrganizer` cannot be derived — and the leader's
    /// Change routine control and tappable ready widget are half of what
    /// these frames show.
    let isOrganizer: Bool
    /// THE CREW'S WEEK (owner addition 2026-09-12), on trial. Always supplied
    /// here so the owner sees the strip on the proof frames; nil in
    /// production until a per-member weekly read exists.
    let crewWeek: CrewWeek?
    /// Feeds `LobbyView.rackAskClass` directly (owner-decisions round, plan
    /// task S9, frame 153): a catalog world may NAME the equipment class the
    /// rack question is about, rather than deriving it from a live
    /// `routineInfo`/`allExercises` lookup — the derivation only a
    /// `RoutineRepository`/`ExerciseRepository` read can perform, which
    /// constraint 11 forbids a catalog builder from making. `nil` for every
    /// existing world (frames 129/130/131/135/136), so they render exactly
    /// what they render today.
    var rackAskClass: String? = nil
}

enum LobbyFixtures {

    // MARK: - Fixed ids

    static let sessionID = UUID(uuidString: "00000000-0000-0000-0000-00000000f001") ?? UUID()
    static let groupID = UUID(uuidString: "00000000-0000-0000-0000-00000000f002") ?? UUID()
    static let alexID = UUID(uuidString: "00000000-0000-0000-0000-00000000f011") ?? UUID()
    static let danaID = UUID(uuidString: "00000000-0000-0000-0000-00000000f012") ?? UUID()
    static let samID = UUID(uuidString: "00000000-0000-0000-0000-00000000f013") ?? UUID()
    static let leeID = UUID(uuidString: "00000000-0000-0000-0000-00000000f014") ?? UUID()

    // MARK: - Fixed dates

    /// Noon UTC from components, the `CrewsTabFixtures.utcDate` idiom — the
    /// only hour that survives a simulator anywhere from UTC-11 to UTC+11
    /// printing the same calendar day.
    private static func utcDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month,
                                                  day: day, hour: hour))
            ?? Date(timeIntervalSince1970: 0)
    }

    static let scheduledFor = utcDate(year: 2026, month: 9, day: 14)
    static let createdAt = utcDate(year: 2026, month: 9, day: 1)

    // MARK: - The session

    /// `lobby_open`, in a crew, with a routine — the state every one of these
    /// frames is captured in. No room code: these are crew sessions, and the
    /// room-code banner is a `.code` session's chrome.
    /// `style` is stated rather than defaulted (plan task S2): frame 136
    /// exists to show Rounds SELECTED with the other two readable, and a
    /// frame whose selection came from a memberwise default is a frame that
    /// silently changes if the default ever does. `liftingStartedAt` stays
    /// nil, which is what keeps the style card on screen at all.
    private static func session(state: String = "lobby_open",
                                style: SessionStyle = .rounds) -> WorkoutSession {
        WorkoutSession(
            id: sessionID,
            routineID: nil,
            organizerID: alexID,
            state: state,
            startedAt: nil,
            completedAt: nil,
            createdAt: createdAt,
            groupID: groupID,
            roomCode: nil,
            scheduledFor: scheduledFor,
            seriesID: nil,
            currentTurnUserID: nil,
            currentTurnStartedAt: nil,
            style: style)
    }

    // MARK: - The plan

    /// The design round's own leg day, so the production frame and the
    /// `lobby-crew-waiting-v2` frame it retires show one session.
    static let planRows: [SessionPlanRow] = [
        SessionPlanRow(id: UUID(uuidString: "00000000-0000-0000-0000-00000000f021") ?? UUID(),
                       name: "Back squat", prescription: "4 × 5 @ 225", isCurrent: true),
        SessionPlanRow(id: UUID(uuidString: "00000000-0000-0000-0000-00000000f022") ?? UUID(),
                       name: "Romanian deadlift", prescription: "3 × 8 @ 185"),
        SessionPlanRow(id: UUID(uuidString: "00000000-0000-0000-0000-00000000f023") ?? UUID(),
                       name: "Leg press", prescription: "3 × 10 @ 270"),
        SessionPlanRow(id: UUID(uuidString: "00000000-0000-0000-0000-00000000f024") ?? UUID(),
                       name: "Walking lunge", prescription: "3 × 20 steps"),
    ]

    /// A plausible ROUTINE TITLE, not a computed prescription line — the
    /// leader named this routine, they did not compose this sentence.
    static let rungLine = "Leg Day A"

    // MARK: - The crew

    private static func row(_ id: UUID, _ name: String, _ stage: ArrivalStage,
                            energy: Int?, isYou: Bool = false,
                            isLate: Bool = false) -> ArrivalRow {
        ArrivalRow(id: id, name: name, avatarURL: nil, stage: stage,
                   energy: energy, isYou: isYou, isLate: isLate)
    }

    // MARK: - The crew's week (owner addition 2026-09-12)

    /// The owner's own chip numbers — Alex 2/3 · Sam 3/3 · Dana 1/4 · Lee 2/3
    /// — on a fixed THURSDAY (`todayIndex: 3`), never `Date.now`.
    ///
    /// 8 done against a 13-session plan puts the crew one ahead of Thursday's
    /// pace (13 × 4/7 = 7.4 → 7), so the caption reads `1 AHEAD · 8 OF 13`.
    /// The three caption FORMS the ruling gives are formats, not one dataset:
    /// no weekday makes 8-of-13 read exactly ON PACE, and inventing chip
    /// numbers that did would be a frame that proves a sentence rather than a
    /// component.
    ///
    /// Per-day counts are supplied so the frames show the real stepped shape
    /// rather than the straight line a bare total honestly is.
    static let crewWeek = CrewWeek(
        lifters: [
            CrewWeekLifter(id: alexID, name: "Alex Rue", goal: 3, done: 2,
                           doneByDay: [1, 0, 1, 0, 0, 0, 0]),
            CrewWeekLifter(id: samID, name: "Sam Obi", goal: 3, done: 3,
                           doneByDay: [1, 1, 0, 1, 0, 0, 0]),
            CrewWeekLifter(id: danaID, name: "Dana Kord", goal: 4, done: 1,
                           doneByDay: [0, 0, 1, 0, 0, 0, 0]),
            CrewWeekLifter(id: leeID, name: "Lee Vance", goal: 3, done: 2,
                           doneByDay: [0, 1, 0, 1, 0, 0, 0]),
        ],
        todayIndex: 3)

    // MARK: - The three worlds

    /// `session-lobby-waiting` (frame 129): two checked in, one at the gym,
    /// one on the way — so Start is disabled and captioned
    /// `2 of 4 checked in`, and the energy card reads `3 OF 4 REPORTED`.
    static let waiting = LobbyWorld(
        session: session(style: .rounds),
        groupName: "Push Crew",
        rows: [
            row(alexID, "Alex Rue", .checkedIn, energy: 4, isYou: true),
            row(danaID, "Dana Kord", .checkedIn, energy: 5),
            row(samID, "Sam Obi", .atTheGym, energy: 3),
            row(leeID, "Lee Vance", .onTheWay, energy: nil),
        ],
        rungLine: rungLine,
        planRows: planRows,
        isOrganizer: true,
        crewWeek: crewWeek)

    /// `session-lobby-rack-ask` (frame 153, owner-decisions round, plan task
    /// S9): the SAME crew, routine and Rounds style `waiting` (frame 129)
    /// captures, copied rather than shared so 129 cannot drift if this world
    /// is ever edited — with `rackAskClass: "barbell"` naming the class the
    /// question is about, which is what makes `LobbyView.styleCard` draw the
    /// stepper. `rack_counts` stays empty (no read happens in catalog mode
    /// either way), so the ask reads as "no count yet, skippable" here.
    static let rackAsk = LobbyWorld(
        session: session(style: .rounds),
        groupName: "Push Crew",
        rows: [
            row(alexID, "Alex Rue", .checkedIn, energy: 4, isYou: true),
            row(danaID, "Dana Kord", .checkedIn, energy: 5),
            row(samID, "Sam Obi", .atTheGym, energy: 3),
            row(leeID, "Lee Vance", .onTheWay, energy: nil),
        ],
        rungLine: rungLine,
        planRows: planRows,
        isOrganizer: true,
        crewWeek: crewWeek,
        rackAskClass: "barbell")

    /// `session-lobby-ready` (frame 130): everyone checked in. The accent
    /// moves to the arrival widget and the foot's Start becomes the neutral
    /// secondary — and, per the owner's ruling of 2026-09-12, EVERYTHING ELSE
    /// STAYS: the whole plan, the energy card and Coach's door are all still
    /// on screen, exactly as in the waiting frame.
    static let ready = LobbyWorld(
        session: session(),
        groupName: "Push Crew",
        rows: [
            row(alexID, "Alex Rue", .checkedIn, energy: 4, isYou: true),
            row(danaID, "Dana Kord", .checkedIn, energy: 5),
            row(samID, "Sam Obi", .checkedIn, energy: 3),
            row(leeID, "Lee Vance", .checkedIn, energy: 4),
        ],
        rungLine: rungLine,
        planRows: planRows,
        isOrganizer: true,
        crewWeek: crewWeek)

    /// `session-lobby-late` (frame 131): three checked in, one late. Start is
    /// LIVE for the leader and still captioned `3 of 4 checked in`; tapping it
    /// raises the shipped confirmation, whose copy this frame makes reachable.
    static let late = LobbyWorld(
        session: session(),
        groupName: "Push Crew",
        rows: [
            row(alexID, "Alex Rue", .checkedIn, energy: 4, isYou: true),
            row(danaID, "Dana Kord", .checkedIn, energy: 5),
            row(samID, "Sam Obi", .checkedIn, energy: 3),
            row(leeID, "Lee Vance", .onTheWay, energy: nil, isLate: true),
        ],
        rungLine: rungLine,
        planRows: planRows,
        isOrganizer: true,
        crewWeek: crewWeek)
}
