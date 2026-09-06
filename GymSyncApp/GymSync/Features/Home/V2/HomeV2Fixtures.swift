import SwiftUI

/// One fixture world for Home v2 — everything both arrangements need, so that
/// A and B can be rendered from the SAME facts and the owner is comparing
/// arrangements rather than data.
///
/// Values are the plan's (`docs/superpowers/plans/2026-09-05-home-v2-catalog
/// .md`, "Shared pieces"). Nothing here reads `AppState` or a repository: the
/// catalog capture must be hermetic and identical on every run, so even
/// "today" is a fixture integer rather than a `Date`.
struct HomeV2World {
    // Greeting (chrome — see `HomeV2GreetingHeader`).
    let greeting: String
    let dateLine: String
    let avatarInitials: String

    /// The one button's state on this day.
    let primary: HomeOneButtonState
    /// Outstanding burpee debt. The counter emerges beside the solo pill, and
    /// the pill itself only appears when the primary is a crew state (rule 5).
    let burpeesOwed: Int

    // Streak — the all-time number, and the week that protects it.
    let streak: Int
    let daysDone: Int
    let weeklyGoal: Int
    let weekDays: [HomeWeekStrip.Day]

    // Coach — one line, first person (rule 7).
    let coachSentence: String
    let coachWaiting: Int?

    // Arrangement B's today card. `todayPill` is optional: a crew night has
    // nothing to say there that the button does not already say.
    let todayKicker: String
    let todayPill: String?
    let todayTitle: String
    let todayLine: String

    // The training calendar, folded.
    let months: [HomeCalendarCard.Month]
    let appointments: [HomeCalendarCard.Appointment]
}

enum HomeV2Fixtures {

    // MARK: The two worlds

    /// The crew night: a session tonight with Push Crew, the window open, debt
    /// on the board, three days of four in the bank. This is arrangement A's
    /// own fixture (plan, Task 2) and the swapped state for B.
    static let crewNight = HomeV2World(
        greeting: greeting,
        dateLine: dateLine,
        avatarInitials: avatarInitials,
        primary: .checkIn(crew: "Push Crew", routine: "Push A", time: "5:00 PM"),
        burpeesOwed: 12,
        streak: 12,
        daysDone: 3,
        weeklyGoal: 4,
        weekDays: [
            .init(id: 0, letter: "M", state: .done),
            .init(id: 1, letter: "T", state: .done),
            .init(id: 2, letter: "W", state: .empty),
            .init(id: 3, letter: "T", state: .done),
            .init(id: 4, letter: "F", state: .today),
            .init(id: 5, letter: "S", state: .empty),
            .init(id: 6, letter: "S", state: .empty),
        ],
        coachSentence: coachSentence,
        coachWaiting: 1,
        // The crew night's card names the session and who is already there —
        // the plan's own fixture detail ("Dana checked in, Sam on the way"),
        // which has no other home in either arrangement.
        todayKicker: "TONIGHT · WITH PUSH CREW",
        // No pill: the time is already in the button's second line 60 pt
        // below ("PUSH CREW · PUSH A · 5:00 PM · OPEN NOW"), and saying it
        // twice on one card is noise.
        todayPill: nil,
        todayTitle: "Push A",
        todayLine: "Dana checked in · Sam on the way",
        months: months(trainedThisMonth: [1, 2, 4]),
        appointments: crewNightAppointments
    )

    /// The solo day: today's lift comes from the enrolled block, no time set,
    /// the week's goal already met. This is arrangement B's own fixture (plan,
    /// Task 3) and the swapped state for A.
    static let soloDay = HomeV2World(
        greeting: greeting,
        dateLine: dateLine,
        avatarInitials: avatarInitials,
        primary: .startRoutine("Pull A"),
        burpeesOwed: 12,
        streak: 12,
        daysDone: 4,
        weeklyGoal: 4,
        weekDays: [
            .init(id: 0, letter: "M", state: .done),
            .init(id: 1, letter: "T", state: .done),
            .init(id: 2, letter: "W", state: .done),
            .init(id: 3, letter: "T", state: .done),
            .init(id: 4, letter: "F", state: .today),
            .init(id: 5, letter: "S", state: .empty),
            .init(id: 6, letter: "S", state: .empty),
        ],
        coachSentence: coachSentence,
        coachWaiting: 1,
        todayKicker: "TODAY · FROM YOUR BLOCK",
        todayPill: "WEEK 2 OF 6",
        todayTitle: "Pull A",
        todayLine: "5 exercises · about 50 min · no time set",
        // Four training days in the bank this week, matching 4/4 above.
        months: months(trainedThisMonth: [1, 2, 3, 4]),
        appointments: soloDayAppointments
    )

    // MARK: Shared facts

    static let greeting = "Good afternoon, Smola"
    static let dateLine = "Friday, September 5"
    static let avatarInitials = "SM"

    /// Coach's line, verbatim from the plan — first person, a safety-shaped
    /// read on a stall, then the call.
    static let coachSentence = "bench stalled twice at 205. Take 185 × 8 today, then we climb."

    /// B's quiet escape when the primary is NOT a crew state. (When it IS,
    /// rule 5's `START SOLO WORKOUT` pill takes this slot instead, which is
    /// also where the burpee counter surfaces.)
    static let somethingElsePrefix = "Something else? "
    static let somethingElseAction = "Start solo workout ›"

    // MARK: The calendar

    /// Previous / current / next month, the shape production's field renders.
    /// Trained days are a Mon-Wed-Fri texture in the past month — the field's
    /// whole point is that a habit reads as a vertical line.
    static func months(trainedThisMonth: Set<Int>) -> [HomeCalendarCard.Month] {
        [
            HomeCalendarCard.Month(
                id: "aug", label: "AUG", dayCount: 31, leadingBlanks: 6,
                trained: [3, 5, 7, 10, 12, 14, 17, 19, 21, 24, 26, 28],
                planned: [], today: nil, position: .past
            ),
            HomeCalendarCard.Month(
                id: "sep", label: "SEP", dayCount: 30, leadingBlanks: 2,
                trained: trainedThisMonth,
                planned: [5, 7, 9, 12], today: 5, position: .current
            ),
            HomeCalendarCard.Month(
                id: "oct", label: "OCT", dayCount: 31, leadingBlanks: 4,
                trained: [], planned: [], today: nil, position: .future
            ),
        ]
    }

    // Each world gets its OWN three rows, because the calendar's first row is
    // a statement about today and the two worlds disagree about today. Sharing
    // one list put "Today 5:00 PM · Push A · Push Crew · IN" three hundred
    // points under a hero reading "TODAY · FROM YOUR BLOCK / Pull A / no time
    // set" — a frame telling two stories about the same day, which spends the
    // owner's attention on the contradiction instead of on the arrangement.
    //
    // Crew tiles wear their group identity colour (`GSGroupColor`'s Okabe-Ito
    // palette — colourblind-safe, and never the user's accent); a solo row
    // passes `nil` so it resolves to the accent at render.

    /// The crew night: tonight's session is the first row, already checked in.
    static let crewNightAppointments: [HomeCalendarCard.Appointment] = [
        HomeCalendarCard.Appointment(
            id: 1, day: "Today", time: "5:00 PM", initials: "PC",
            tint: GSGroupColor.palette[4], ink: groupInk,
            title: "Push A", subtitle: "Push Crew", repeats: false, status: .checkedIn
        ),
        HomeCalendarCard.Appointment(
            id: 2, day: "Sat", time: "9:00 AM", initials: "LC",
            tint: GSGroupColor.palette[2], ink: groupInk,
            title: "Lower B", subtitle: "Legs Crew", repeats: true, status: nil
        ),
        HomeCalendarCard.Appointment(
            id: 3, day: "Sun", time: "10:00 AM", initials: "You",
            tint: nil, ink: nil,
            title: "Pull A", subtitle: "from your block", repeats: false, status: nil
        ),
    ]

    /// The solo day: the first row IS the hero's lift — the block's own Pull A,
    /// no time set — and the rows after it are the ones the v7 proof's Home B
    /// shows (Tuesday's crew session still uncommitted, Thursday's block day).
    static let soloDayAppointments: [HomeCalendarCard.Appointment] = [
        HomeCalendarCard.Appointment(
            id: 1, day: "Today", time: "No time set", initials: "You",
            tint: nil, ink: nil,
            title: "Pull A", subtitle: "from your block", repeats: false, status: nil
        ),
        HomeCalendarCard.Appointment(
            id: 2, day: "Tue", time: "5:00 PM", initials: "PC",
            tint: GSGroupColor.palette[4], ink: groupInk,
            title: "Push B", subtitle: "Push Crew", repeats: false, status: .commit
        ),
        HomeCalendarCard.Appointment(
            id: 3, day: "Thu", time: "6:30 AM", initials: "You",
            tint: nil, ink: nil,
            title: "Lower A", subtitle: "from your block", repeats: false, status: nil
        ),
    ]

    /// Ink on a group-colour tile — `GSGroupColor.onColor`'s value for every
    /// palette entry (all are mid-to-light hues, so near-black reads on each).
    private static let groupInk = Color.gsHex(0x0A0B0D)

    // MARK: Home v3
    //
    // The eight new pieces' values, from the v3 plan's "New pieces" table
    // (`docs/superpowers/plans/2026-09-06-home-v3-ten-variations.md`) —
    // verbatim except for UP NEXT, which carries a controller waiver granted
    // in review round 1 and is explained where it is declared below.
    //
    // Most are SHARED by both worlds: the last lift, the PR watch, the body
    // weight and the lifetime total are facts about the LIFTER, not about
    // which kind of session today happens to be, and keeping them shared
    // keeps the ten frames comparable — a difference between two
    // compositions then reads as the composition rather than as the data.
    //
    // A value that names a DAY cannot be shared, because the two worlds
    // disagree about the days: that is the same reason the calendar's rows
    // are already split into `crewNightAppointments`/`soloDayAppointments`
    // (:160-168 makes the argument in full).
    //
    // They live as statics rather than as new `HomeV2World` fields on
    // purpose: adding stored properties to that struct would rewrite both
    // world literals above (v2 pieces are frozen except for additive
    // parameters).

    /// `HomeUpNextStrip`'s two strings, kept together as one value so the
    /// when and the session can never drift apart — which is exactly what
    /// they did in round 1, when a single shared pair told the crew world's
    /// Saturday story on three solo-day frames whose calendar shows Today,
    /// Tue and Thu and no Saturday at all.
    struct UpNext {
        /// The when, e.g. `NEXT · TUE 5:00 PM`.
        let kicker: String
        /// The session, e.g. `Push B with Push Crew`.
        let title: String
    }

    /// The crew night's next — `crewNightAppointments`' second row, the Legs
    /// Crew Saturday, which is the plan's own verbatim value. No composition
    /// uses it today (the strip appears only on the solo frames 02, 04 and
    /// 10), but it exists so a crew composition can take the strip later
    /// without inheriting another world's day.
    static let crewNightUpNext = UpNext(kicker: "NEXT · SAT 9:00 AM",
                                        title: "Lower B with Legs Crew")

    /// The solo day's next — `soloDayAppointments`' second row. Today's row
    /// on that day IS the hero's own Pull A, from the block, with no time
    /// set, so the next thing wearing a clock is Tuesday's Push Crew
    /// session: the row the calendar still marks COMMIT.
    static let soloDayUpNext = UpNext(kicker: "NEXT · TUE 5:00 PM",
                                      title: "Push B with Push Crew")

    /// `HomeLastLiftTile`.
    static let lastLiftRoutine = "Push A"
    static let lastLiftDetail = "Wed · 7,240 lb · 1 PR"

    /// `HomePRWatchTile` — the second line is an invitation, so it is the
    /// one place a v3 tile spends accent (design language rule 3).
    static let prWatchLift = "Bench 205"
    static let prWatchInvitation = "210 is within reach"

    /// `HomeRecoveryStrip`.
    static let recoveryFresh = "BACK · LEGS"
    static let recoveryTender = "CHEST"
    static let recoverySentence = "Back and legs are fresh. Chest is still tender."

    /// `HomeMilestoneTile` — the percentage in the line and the bar's fill
    /// are the same number stated twice, deliberately: 0.29 is what the bar
    /// draws, `29% of Mount Fuji` is what it says.
    static let milestoneTotal = "1.31M lb"
    static let milestoneLine = "29% of Mount Fuji"
    static let milestoneProgress = 0.29

    /// `HomeBodyWeightTile`. The change opens with U+2212 MINUS SIGN, not a
    /// hyphen — it sits beside tabular digits and a hyphen reads as a dash
    /// at that size.
    static let bodyWeight = "180.4 lb"
    static let bodyWeightChange = "−5.8 since July"

    /// `HomeCrewPulseStrip` — Dana is the crew-night fixture's own first
    /// checked-in lifter (`crewNightAppointments`' Push Crew row says the
    /// same session), so the two agree on any frame that shows both.
    static let crewPulseInitials = "DA"
    static let crewPulseHeadline = "Dana is lifting now"
    static let crewPulseDetail = "Push Crew · tonight 5:00 PM"

    /// `HomeWeekPlanStrip` — two done, one next, matching the `soloDay`
    /// week's shape closely enough that a frame carrying both does not
    /// contradict itself (the plan's three named days are the training days
    /// of that week; the strip names them where the week strip only counts
    /// them).
    static let weekPlan: [HomeWeekPlanStrip.Entry] = [
        .init(id: 0, label: "TUE PUSH", state: .done),
        .init(id: 1, label: "THU PULL", state: .done),
        .init(id: 2, label: "SAT LEGS", state: .next),
    ]

    // MARK: Home v3 addendum — Coach's targets
    //
    // The owner, on variation 08 (plan:
    // `docs/superpowers/plans/2026-09-06-home-v3-addendum-targets-strip.md`):
    // "maybe above the join with code, we display the weekly muscle group
    // goals, or whatever goal the coach is tracking as a strip?"

    /// `HomeCoachTargetsStrip`'s four groups, the addendum plan's own values:
    /// chest 8/12, back 10/12, legs 6/12 — the one furthest behind, so the
    /// one NEXT — and arms 8/8, the one already MET. Exactly one of each, so
    /// the two states the strip can show are both on screen in one frame,
    /// which is the whole reason a mockup exists.
    ///
    /// SHARED by both worlds, for the same reason the last lift and the PR
    /// watch are: what a block asks of a lifter this week is a fact about
    /// the BLOCK, not about which kind of session today happens to be, and
    /// keeping it shared keeps the two placements comparable — the
    /// difference between 08a and 08b then reads as the placement.
    static let coachTargets: [HomeCoachTargetsStrip.Target] = [
        .init(id: 0, name: "CHEST", done: 8, target: 12, isNext: false),
        .init(id: 1, name: "BACK", done: 10, target: 12, isNext: false),
        .init(id: 2, name: "LEGS", done: 6, target: 12, isNext: true),
        .init(id: 3, name: "ARMS", done: 8, target: 8, isNext: false),
    ]

    /// The kicker row's right-hand read, one value per world. It is that
    /// world's `weeklyGoal - daysDone` and NOTHING else: both addendum
    /// frames put this strip on the same page as `HomeStreakTile`, and a
    /// page may not tell two stories about one week — the law :160-168
    /// states for the calendar's rows, and the one round 1 enforced on UP
    /// NEXT.
    ///
    /// The crew night has 3 of its 4 in the bank (`crewNight.daysDone`), so
    /// one session is left, and the word is singular because the count is.
    static let crewNightSessionsLeft = "1 SESSION LEFT"

    /// The solo day has met its 4 of 4, so no session is left this week to
    /// move these numbers with. No composition uses this today — both
    /// addendum frames render the crew night, following variation 08 — but
    /// it exists so a solo composition can take the strip later without
    /// inheriting another world's week, the same reason `crewNightUpNext`
    /// exists.
    ///
    /// Deliberately NOT `GOAL MET`, which is `HomeWeekStrip`'s own tail and
    /// means the SESSION goal there. The goal in view on THIS strip is
    /// Coach's targets, and three of those four are unmet (chest 8/12, back
    /// 10/12, legs 6/12) — those words here would congratulate the reader
    /// in front of the evidence against them.
    static let soloDaySessionsLeft = "0 SESSIONS LEFT"
}
