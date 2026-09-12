import Foundation

// MARK: - CrewWeek
//
// THE CREW'S WEEK — owner addition of 2026-09-12 (controller ruling), on trial
// in the Phase A lobby so the owner can see how it looks and feels on the
// proof frames before it becomes permanent.
//
// SELF-CONTAINED AND REMOVABLE IN ONE LINE: this file plus `CrewWeekStrip` in
// `SessionPieces.swift` plus one line in `LobbyView.lobbyScroll`. Nothing else
// depends on it.
//
// The maths lives here, pure and tested (`CrewWeekMathTests`) — the plan sum,
// the pace at today, the ahead/on-pace/behind wording and both series. A chart
// that computed its own numbers in a view body is a chart nobody can review.

/// One lifter's week.
struct CrewWeekLifter: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// `profiles.weekly_session_goal`. **nil = no goal set**, which excludes
    /// this lifter from the plan sum — a crew's planned pace must not count a
    /// target nobody set.
    let goal: Int?
    /// Sessions completed so far this week.
    let done: Int
    /// Completed sessions per weekday, Monday first, seven entries — when the
    /// session DATES are known. nil when only a total is: the actual line then
    /// runs straight from Monday 0 to today's count, which is honest about
    /// being a straight line rather than pretending to a shape.
    let doneByDay: [Int]?
}

/// The crew's week, as the strip draws it.
struct CrewWeek: Equatable, Sendable {
    let lifters: [CrewWeekLifter]
    /// Today's 0-based index within Monday…Sunday. A VALUE, never `Date.now`:
    /// a catalog frame must render the same chart on every run (constraint 11).
    let todayIndex: Int
}

enum CrewWeekMath {

    /// Monday…Sunday.
    static let daysInWeek = 7

    /// The sum of the goals the crew actually set. A lifter with no goal
    /// contributes nothing — see `CrewWeekLifter.goal`.
    static func planTotal(_ week: CrewWeek) -> Int {
        week.lifters.compactMap(\.goal).reduce(0, +)
    }

    static func doneTotal(_ week: CrewWeek) -> Int {
        week.lifters.map(\.done).reduce(0, +)
    }

    /// Today's clamped index, so a malformed input cannot index off the week.
    static func today(_ week: CrewWeek) -> Int {
        min(max(0, week.todayIndex), daysInWeek - 1)
    }

    /// Where the plan says the crew should be by the end of today — the
    /// dotted line's height at today's x. Linear from 0 to `planTotal` across
    /// the seven days, rounded to whole sessions because half a session is
    /// not a thing a crew can have done.
    static func paceAtToday(_ week: CrewWeek) -> Int {
        let fraction = Double(today(week) + 1) / Double(daysInWeek)
        return Int((Double(planTotal(week)) * fraction).rounded())
    }

    /// `+n` ahead, `0` on pace, `-n` behind.
    static func delta(_ week: CrewWeek) -> Int {
        doneTotal(week) - paceAtToday(week)
    }

    /// `ON PACE · 8 OF 13 SESSIONS` · `2 AHEAD · 9 OF 13` · `1 BEHIND · 6 OF 13`
    ///
    /// **In words, never in colour.** Design rule 2: accent is the screen's
    /// one invitation, green means done, gold means the window is open. A crew
    /// one session behind on a Wednesday is none of those, so the strip says
    /// so in a caption and spends no colour on it at all.
    ///
    /// The on-pace form carries the noun and the other two do not — the
    /// owner's own three examples, verbatim.
    static func caption(_ week: CrewWeek) -> String {
        let done = doneTotal(week)
        let plan = planTotal(week)
        switch delta(week) {
        case 0:           return "ON PACE · \(done) OF \(plan) SESSIONS"
        case let d where d > 0: return "\(d) AHEAD · \(done) OF \(plan)"
        case let d:       return "\(-d) BEHIND · \(done) OF \(plan)"
        }
    }

    /// The dotted planned line: eight points, `y[i] = planTotal · i / 7`, so
    /// `y[0]` is Monday morning's nothing and `y[7]` is Sunday night's whole
    /// plan.
    static func plannedSeries(_ week: CrewWeek) -> [Double] {
        let plan = Double(planTotal(week))
        return (0...daysInWeek).map { plan * Double($0) / Double(daysInWeek) }
    }

    /// The solid actual line, ending on today.
    ///
    /// With per-day counts it is the crew's cumulative total, day by day, up
    /// to and including today. With only a total it is TWO points — Monday's
    /// zero and today's count — because a straight line is what a total
    /// honestly is, and inventing a shape for it would be a chart that lies.
    static func actualSeries(_ week: CrewWeek) -> [Double] {
        let last = today(week) + 1
        let perDay = week.lifters.compactMap(\.doneByDay)
        guard !perDay.isEmpty else {
            return [0, Double(doneTotal(week))]
        }
        var running = 0.0
        var series: [Double] = [0]
        for day in 0..<min(last, daysInWeek) {
            for lifter in week.lifters {
                // A lifter with a total but no breakdown contributes on the
                // last day rather than nowhere — their sessions happened.
                if let byDay = lifter.doneByDay, day < byDay.count {
                    running += Double(byDay[day])
                } else if lifter.doneByDay == nil, day == min(last, daysInWeek) - 1 {
                    running += Double(lifter.done)
                }
            }
            series.append(running)
        }
        return series
    }

    /// `Alex 2/3` · `Mo 2/–` for a lifter with no goal. An EN DASH, not a
    /// zero: a lifter who set no target has not set a target of none.
    static func chip(_ lifter: CrewWeekLifter) -> String {
        let goal = lifter.goal.map(String.init) ?? "–"
        return "\(SessionCopy.firstName(lifter.name)) \(lifter.done)/\(goal)"
    }
}
