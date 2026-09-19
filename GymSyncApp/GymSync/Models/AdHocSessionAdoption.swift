import Foundation

// MARK: - AdHocSessionAdoption
//
// ADOPT THE WORKOUT ALREADY RUNNING, OR BEGIN ONE — AND CLOSE WHAT WAS LEFT
// OPEN (fix round 1 / N6).
//
// THE LAW THIS CARRIES is the 2026-08-22 one: any entry point adopts the live
// solo session instead of minting a second row, because Start-Workout-as-a-
// dismissible-sheet let swipe-down + Start-again create a fresh session with
// an empty carry ("weight not carrying forward"). It lived inside
// `WorkoutSessionView.startIfNeeded()`, keyed on an in-memory `AppState`
// handle; Phase C1 moved the capability out of that view, so the law moved
// with it into `SessionRepository.startOrAdoptSolo`.
//
// TWO THINGS THE MOVE LOST, AND THIS RESTORES:
//
//   1. THE OLD LAW ADOPTED ONLY A ROW THIS DEVICE HAD CREATED — it read a
//      handle the view itself had written. The moved version asked only
//      "is it ad-hoc, and is it for this routine", and its safety was
//      incidental: nothing else writes a triple-nil `in_progress` row today,
//      so adopting somebody else's was unreachable rather than refused. The
//      check is now stated: `organizerID == me`.
//
//   2. `liveForCurrentUser`'s six-hour floor meant a solo row older than six
//      hours was not adopted and a second was minted — and the first stayed
//      `in_progress` FOREVER, because nothing in this app ever ends a session
//      on its own (there is no reaper; `20260716000003_push_cron.sql:169-199`
//      notifies at 30 and 60 minutes idle and never transitions the row). B1
//      made that the ordinary outcome rather than the exception: a Freestyle
//      session could not be ended at all, so every ad-hoc workout was leaving
//      one behind. Those rows are now CLOSED.
//
// CLOSED MEANS `complete()`, NOT "abandoned", and that is what the completion
// path honestly supports: `sessions.state` admits `'abandoned'` but NO
// repository function writes it (grep: the only `"abandoned"` literal in the
// app is `ProgramRepository.end(reason:)`, an unrelated column). `complete()`
// is the shipped write — `state = 'completed'`, `completed_at = now` — and it
// is also the truthful one: a workout whose sets are in `set_logs` happened,
// and the streak and week credit those rows earn should not be voided because
// the lifter walked away without tapping anything.
//
// PURE, so the decision is a value a test can read rather than a sequence of
// awaits nobody can reach.
enum AdHocSessionAdoption {

    /// The fields of one candidate `sessions` row this decision reads.
    struct Candidate: Equatable {
        let id: UUID
        let routineID: UUID?
        let organizerID: UUID
        let groupID: UUID?
        let roomCode: String?
        let scheduledFor: Date?
        /// `in_progress` rows always carry one — `liveForCurrentUser`'s own
        /// floor already excludes a row that cannot say when it began — but
        /// it is optional here so a malformed row is skipped rather than
        /// crashing the start.
        let startedAt: Date?
    }

    struct Decision: Equatable {
        /// The row to run, or nil to start a new one.
        var adopt: UUID?
        /// Rows to close first: this lifter's own stale ad-hoc sessions.
        var end: [UUID]
    }

    /// Six hours, the same bound `liveForCurrentUser` applies to what Home
    /// OFFERS, for the same stated reason: no real gym session outlasts it.
    static let staleAfter: TimeInterval = 6 * 3600

    /// - Parameters:
    ///   - rows: every `in_progress` session this user participates in, with
    ///     NO age floor applied — the floor is this function's to interpret,
    ///     because a stale row is something to close rather than something to
    ///     hide.
    ///   - routineID: the routine the lifter just tapped; nil is freeform,
    ///     and a freeform session adopts only another freeform one.
    static func decide(rows: [Candidate],
                       routineID: UUID?,
                       me: UUID,
                       now: Date,
                       staleAfter: TimeInterval = AdHocSessionAdoption.staleAfter) -> Decision {
        // MINE, AND AD-HOC. A crew session is never adopted and never closed
        // by this path, whoever organizes it: ending somebody else's session
        // — or your own crew's, from a solo Start button — is not a thing a
        // tap on START WORKOUT may do.
        let mine = rows.filter { row in
            row.organizerID == me
                && row.groupID == nil
                && row.roomCode == nil
                && row.scheduledFor == nil
        }

        // Newest first, so the row offered is the one that just started
        // rather than the stalest — `liveForCurrentUser` orders this way and
        // the reasoning is its own.
        let byRecency = mine.sorted {
            ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
        }

        let fresh = byRecency.filter { row in
            guard let startedAt = row.startedAt else { return false }
            return now.timeIntervalSince(startedAt) < staleAfter
        }

        // THE ROUTINE MUST MATCH. Resuming yesterday's push day because the
        // lifter tapped a pull routine is the 2026-08-22 bug from the other
        // direction — a fragmented history, arrived at by adopting too
        // eagerly rather than too little.
        let adopt = fresh.first { $0.routineID == routineID }?.id

        // Everything else of mine that is stale gets closed. A FRESH row for
        // a DIFFERENT routine is deliberately left alone: the lifter may
        // genuinely be running two things this hour, and six hours from now
        // this same function will close it if they were not.
        let end = byRecency.filter { row in
            guard row.id != adopt, let startedAt = row.startedAt else { return false }
            return now.timeIntervalSince(startedAt) >= staleAfter
        }.map(\.id)

        return Decision(adopt: adopt, end: end)
    }
}
