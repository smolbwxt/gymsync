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

    // Arrangement B's today card.
    let todayKicker: String
    let todayPill: String
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
        todayPill: "5:00 PM",
        todayTitle: "Push A",
        todayLine: "Dana checked in · Sam on the way",
        months: months(trainedThisMonth: [1, 2, 4]),
        appointments: appointments
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
        appointments: appointments
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

    /// Three upcoming rows. Crew tiles wear their group identity colour
    /// (`GSGroupColor`'s Okabe-Ito palette, colourblind-safe and never the
    /// user's accent); the solo row passes `nil` so it resolves to the accent
    /// at render.
    static let appointments: [HomeCalendarCard.Appointment] = [
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

    /// Ink on a group-colour tile — `GSGroupColor.onColor`'s value for every
    /// palette entry (all are mid-to-light hues, so near-black reads on each).
    private static let groupInk = Color.gsHex(0x0A0B0D)
}
