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
//   2. `liveForCurrentUser`'s six-hour floor is applied HERE rather than in
//      SQL, so the window the law turns on is written down in one place a
//      test can read instead of being split between a query and a function.
//
// A STALE ROW IS IGNORED, NOT CLOSED — AND THAT IS A WITHDRAWN RULING
// (fix round 2 / B3). This function briefly returned a list of stale ad-hoc
// rows for `startOrAdoptSolo` to `complete()`, on the argument that a row
// nothing ever ends stays `in_progress` forever (true: there is no reaper,
// and `20260716000003_push_cron.sql:169-199` notifies at 30 and 60 minutes
// idle without ever transitioning the row). The argument was right about the
// problem and wrong about the remedy, because `complete()` IS NOT A QUIET
// WRITE. `AFTER UPDATE OF state ON public.sessions` fires:
//
//   * `leaderboard_recompute_on_session_completion` (`20260723000001:245-307`)
//     — marks EVERY `workout_attempts` row for the session complete, opted in
//     or not, and INSERTs a `leaderboard_entries` row whose `time_seconds` is
//     `completed_at - started_at`: the whole wall-clock gap since the lifter
//     walked away, published as a finished run.
//   * `zzleaderboard_social_effects_on_completion` (`20260723000002:309`) —
//     ranks the opted-in ones and `enqueue_push(..., 'leaderboard_passed')`,
//     a notification sent to ANOTHER USER because this lifter tapped START on
//     something unrelated.
//   * `campaign_progress_on_session_completion` (`20260728000002:346`) —
//     credits a session against any campaign whose `curated_routine_ids`
//     holds this routine, and on crossing the target INSERTs a
//     `system_campaign` chat row into EVERY GROUP the lifter belongs to.
//
// None of that is a thing a tap on START WORKOUT may do on the lifter's
// behalf, to a session they never asked to close. So the stale row is left
// exactly as master leaves it: ignored, and a fresh session is started
// beside it.
//
// THE OPEN ROW IS A REAL RESIDUAL AND IT NEEDS A SERVER-SIDE ABANDON, WHICH
// IS C2's. `sessions.state` already admits `'abandoned'` but NO repository
// function writes it (grep: the app's only `"abandoned"` literal is
// `ProgramRepository.end(reason:)`, an unrelated column), and `'abandoned'`
// is not `'completed'`, so none of the three triggers above would fire for
// it — which is precisely why it, and not `complete()`, is the right shape
// for this. C2 owns discard/abandon; until it lands, an ad-hoc row the lifter
// walked away from stays `in_progress` and is simply never offered again.
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

    /// TWO OUTCOMES, AND ONLY TWO (fix round 2 / B3). There is deliberately
    /// no third that writes anything to a row the lifter did not act on.
    enum Decision: Equatable {
        /// Run this row — the workout already in progress.
        case adopt(UUID)
        /// Begin a new one, and touch nothing that is already there.
        case startFresh
    }

    /// Six hours, the same bound `liveForCurrentUser` applies to what Home
    /// OFFERS, for the same stated reason: no real gym session outlasts it.
    static let staleAfter: TimeInterval = 6 * 3600

    /// - Parameters:
    ///   - rows: every `in_progress` session this user participates in, with
    ///     no age floor applied in SQL — the window is this function's, so
    ///     that the one law is in one place and a test can read it.
    ///   - routineID: the routine the lifter just tapped; nil is freeform,
    ///     and a freeform session adopts only another freeform one.
    static func decide(rows: [Candidate],
                       routineID: UUID?,
                       me: UUID,
                       now: Date,
                       staleAfter: TimeInterval = AdHocSessionAdoption.staleAfter) -> Decision {
        // MINE, AND AD-HOC. Somebody else's session is never adopted, and
        // neither is a crew session of my own — resuming either from a solo
        // Start button is not a thing a tap on START WORKOUT may do.
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

        // WITHIN THE WINDOW. A row older than the floor is not resumed, and
        // is not touched either (see the header): no real gym session
        // outlasts six hours, so what is on the other side of that line is
        // something the lifter walked away from, not something to drop them
        // back into mid-set. A row that cannot say when it began is a data
        // anomaly rather than a live session and is left alone for the same
        // reason `liveForCurrentUser`'s own floor excludes it.
        let fresh = byRecency.filter { row in
            guard let startedAt = row.startedAt else { return false }
            return now.timeIntervalSince(startedAt) < staleAfter
        }

        // THE ROUTINE MUST MATCH. Resuming yesterday's push day because the
        // lifter tapped a pull routine is the 2026-08-22 bug from the other
        // direction — a fragmented history, arrived at by adopting too
        // eagerly rather than too little.
        guard let adopt = fresh.first(where: { $0.routineID == routineID }) else {
            return .startFresh
        }
        return .adopt(adopt.id)
    }
}
