import Foundation

// MARK: - WeeklyGoalProgressMath
//
// Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
// -goal-design.md §B. Plan: docs/superpowers/plans/2026-09-06-home-v3
// -production-plan.md, Stream A tasks A3-A7.
//
// Everything here is PURE. No network, no `Date.now`, no `ThemeStore`
// read — every input is passed in, including the clock and the calendar.
// That is what makes the design's agreement law testable: the number the
// goal strip renders and the number the streak tile renders come out of
// this file, and a test can put both under the same fixture.
//
// The boundary this writes is `WeeklyGoalProgress`
// (Models/WeeklyGoalRepository.swift). A view that recomputed any of it
// would be a second opinion about the same week.

enum WeeklyGoalProgressMath {

    // MARK: - A3: the muscle-sets tally

    /// What a week of `set_logs` gave each of the six groups.
    ///
    /// A log counts when it is not a penalty and `completedReps != nil`.
    /// Both halves are load-bearing:
    ///
    /// - **Penalty sets are not training.** They are the burpee tax a late
    ///   arrival owes (`sessions.late_penalty`), logged against the
    ///   exercise so the ledger balances. Crediting them would let being
    ///   late fill a chest target.
    /// - **`completedReps`, never raw `reps`.** `SetLog.completedReps`
    ///   (`SetLog.swift:41`) is this app's failure doctrine in one place: a
    ///   failed triple completed 2 reps and counts, a failed single
    ///   completed nothing and does not. Reading `reps` here would credit
    ///   a missed single as a full set, and reading `isFailed` directly
    ///   would throw away the honest triple. Every e1RM and PR path in the
    ///   app already reads `completedReps`; this is the same rule, so the
    ///   goal strip and the PR sheet cannot disagree about what a set was.
    ///
    /// An `exerciseID` the catalog does not carry is skipped rather than
    /// guessed — the catalog is paged and a stale local copy is a real
    /// state, and a set of an unknown exercise credits an unknown muscle.
    ///
    /// Callers pass the week's logs; this function does no date filtering,
    /// because the one definition of "this week" lives in `WeekMath` and
    /// having two would break the agreement law.
    static func muscleSetCredit(logs: [SetLog],
                                catalog: [UUID: Exercise]) -> [MuscleGroup: Double] {
        var tally: [MuscleGroup: Double] = [:]
        for log in logs {
            guard !log.isPenalty, log.completedReps != nil else { continue }
            guard let exercise = catalog[log.exerciseID] else { continue }
            let perSet = MuscleGroup.credit(primary: exercise.primaryMuscle,
                                            secondaries: exercise.secondaryMuscles)
            for (group, credit) in perSet {
                tally[group, default: 0] += credit
            }
        }
        return tally
    }
}
