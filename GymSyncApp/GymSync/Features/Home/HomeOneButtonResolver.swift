import Foundation

// MARK: - HomeOneButtonResolver
//
// Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
// -goal-design.md §A item 3. Plan: docs/superpowers/plans/2026-09-06-home
// -v3-production-plan.md, task B1 ("The one button's state resolver") and
// task B7 (which tests it).
//
// WHY THIS IS A SEPARATE, PURE TYPE. The five states of `HomeOneButton` are
// the whole of Home's primary action, and a SwiftUI body is not unit
// testable here — so the branch order lives in a function that takes plain
// values and returns a state, and `HomeView` does nothing but feed it.
//
// IT OWNS NO TIMING. The 20-minute check-in window
// (`HomeView.checkInOpensAt`) and the 30-minute missed-session cutoff
// (`HomeView.nextActionableSession`) stay exactly where they are, untouched,
// and arrive here ALREADY RESOLVED as booleans and pre-formatted strings.
// That is deliberate: the production plan's constraint 5 names both rules by
// file and line, and a resolver that re-derived either would be a second
// opinion about when a lifter may check in.

/// Everything the resolver needs to know about the session the button is
/// about, with every rule already applied by the caller.
struct HomeOneButtonInput: Equatable {
    /// `session.state == "in_progress"`.
    var isInProgress: Bool
    /// A formatted `startedAt` (e.g. `5:12 PM`), or `nil` when the session
    /// has no start stamp — "in progress but never started" is not a join.
    var startedAtLabel: String?
    /// `session.groupID != nil`.
    var isGroupSession: Bool
    /// `HomeView.checkInAvailable(_:now:)`.
    var checkInAvailable: Bool
    /// `HomeView.compactCountdown(to:from:)` against
    /// `HomeView.checkInOpensAt(_:)`, or `nil` when the window is not in the
    /// future (already open, or the session carries no scheduled time).
    var opensInLabel: String?
    /// The crew's name, for the `.checkIn` face.
    var crewName: String
    /// `HomeView.routineLabel(for:)`.
    var routineName: String
    /// The scheduled clock time, for the `.checkIn` face.
    var timeLabel: String

    init(isInProgress: Bool = false,
         startedAtLabel: String? = nil,
         isGroupSession: Bool = false,
         checkInAvailable: Bool = false,
         opensInLabel: String? = nil,
         crewName: String = "",
         routineName: String = "",
         timeLabel: String = "") {
        self.isInProgress = isInProgress
        self.startedAtLabel = startedAtLabel
        self.isGroupSession = isGroupSession
        self.checkInAvailable = checkInAvailable
        self.opensInLabel = opensInLabel
        self.crewName = crewName
        self.routineName = routineName
        self.timeLabel = timeLabel
    }
}

enum HomeOneButtonResolver {

    /// The plan's table, in its own order. First match wins.
    ///
    /// | condition | state |
    /// |---|---|
    /// | the next actionable session is live and started | `.joinSession` |
    /// | check-in is available and it is a group session | `.checkIn` (gold) |
    /// | a next session exists and its window has not opened | `.checkInOpens` |
    /// | today's routine resolved | `.startRoutine` |
    /// | otherwise | `.startWorkout` |
    ///
    /// A solo session inside its own check-in window falls PAST rows two and
    /// three to `.startRoutine`/`.startWorkout` on purpose: `.checkIn`'s copy
    /// is a crew sentence (`{CREW} · {ROUTINE} · {TIME} · OPEN NOW`) and there
    /// is nobody to check in with on a solo lift — the start screen is the
    /// honest door.
    static func state(next: HomeOneButtonInput?,
                      todaysRoutineName: String?) -> HomeOneButtonState {
        if let next {
            if next.isInProgress, let startedAtLabel = next.startedAtLabel {
                return .joinSession(startedAt: startedAtLabel)
            }
            if next.checkInAvailable, next.isGroupSession {
                return .checkIn(crew: next.crewName,
                                routine: next.routineName,
                                time: next.timeLabel)
            }
            if let opensInLabel = next.opensInLabel {
                return .checkInOpens(opensInLabel)
            }
        }
        if let name = todaysRoutineName, !name.isEmpty {
            return .startRoutine(name)
        }
        return .startWorkout
    }
}
