import Foundation

// MARK: - SoloResumeCursor
//
// WHERE A RESUMED SOLO SESSION PICKS BACK UP, as a pure function.
//
// This is the attribution loop `WorkoutSessionView.restoreLoggedProgress`
// used to perform inline, with ONE correction and one consequence:
//
//   THE CORRECTION — the walk runs against the SWAP-LAYERED routine, not
//   the routine as stored. A hot-swap writes its set logs under the
//   SUBSTITUTE's `exercise_id` (deliberately: history, PRs and the debrief
//   should all see the lift that was actually done). The overrides lived
//   only in the view's `@State`, so a swipe-down lost them and the walk
//   then compared the substitute's logs against the ORIGINAL row's
//   exercise id — never equal, so the slot read as zero sets done and the
//   lifter was sent back to the exercise they had swapped away, to repeat
//   work already in the log. That is the double-logging report
//   (2026-09-18). Layering FIRST is the fix, and it is the entire fix.
//
//   THE CONSEQUENCE — it is testable. Nothing about the decision needs a
//   View, a session, or a network, so `SoloResumeCursorTests` asserts it
//   directly; the inline version could not be asserted at all.
//
// ATTRIBUTION IS BY SLOT (Phase C1, decision 3 — this comment's predecessor
// named it as the known gap and said it was Phase C's). A set row now
// carries the `routine_exercises` row it was logged against, so a routine
// naming the same lift in two slots no longer fills the first to its target
// out of the second's sets, and a slot whose lift was swapped MID-EXERCISE
// counts both halves as the one slot they are.
//
// The pre-column fallback — `routine_exercise_id IS NULL`, matched by
// exercise id — lives in `SlotProgress` and is applied there PER SLOT, in
// routine order and capped at each target, so a session logged entirely
// before the column lands on exactly the cursor it landed on yesterday.
enum SoloResumeCursor {

    /// Exercise index + the 1-based set number to log next.
    struct Position: Equatable {
        let exerciseIndex: Int
        let setIndex: Int
    }

    /// The routine as this session is actually running it: every row the
    /// lifter has hot-swapped replaced by its substitute.
    ///
    /// Keyed by ROUTINE-EXERCISE ROW ID, which is what makes a swap
    /// idempotent — swapping the same slot twice replaces one entry rather
    /// than stacking two. `WorkoutSessionView.activeExercises` calls this
    /// so the list the screen draws and the list the cursor is derived
    /// against can never be two different layerings.
    static func layered(_ rows: [RoutineExercise],
                        swapOverrides: [UUID: RoutineExercise]) -> [RoutineExercise] {
        guard !swapOverrides.isEmpty else { return rows }
        return rows.map { swapOverrides[$0.id] ?? $0 }
    }

    /// Walk the plan in order, attributing logged sets to slots greedily,
    /// and land on the first slot still short of its target. A fully
    /// logged routine lands on the LAST slot one past its target — the
    /// lifter finishes from there.
    ///
    /// - Parameters:
    ///   - rows: the routine's own rows, UNLAYERED — the overrides are
    ///     applied here so no caller can forget to.
    ///   - swapOverrides: session-local hot-swaps by routine-exercise row id.
    ///   - logs: the session's `set_logs`. Penalty rows are dropped here
    ///     rather than by the caller: a burpee penalty is not progress
    ///     through the plan, and that rule belongs with the walk.
    /// - Returns: `(0, 1)` for an empty routine — the honest floor.
    ///
    /// THE DIVISION OF THE LOGS IS `SlotProgress`'s, not this function's
    /// (review F2/F6): built ONCE, in one pass, and the walk below is then a
    /// dictionary lookup per slot. The two-pass loop that used to live here
    /// was a second expression of the same rule, and it carried the version
    /// of it the review rejected — a slot that had started naming itself
    /// stopped counting its own pre-column rows, so a session straddling the
    /// app update rewound the lifter into work already logged.
    ///
    /// THE SET NUMBER IS CAPPED AT THE TARGET, the count is not. A slot with
    /// five rows against a target of three lands the lifter on set 4 of 3 —
    /// shipped behaviour for bonus sets — while `SlotProgress.count` still
    /// answers 5, which is what a display should say.
    static func derive(rows: [RoutineExercise],
                       swapOverrides: [UUID: RoutineExercise],
                       logs: [SetLog]) -> Position {
        let layeredRows = layered(rows, swapOverrides: swapOverrides)
        let progress = SlotProgress(routine: layeredRows,
                                    logs: logs.filter { !$0.isPenalty })
        var position = Position(exerciseIndex: 0, setIndex: 1)
        for (index, re) in layeredRows.enumerated() {
            let target = max(re.targetSets ?? 1, 1)
            let done = progress.count(for: re)
            position = Position(exerciseIndex: index, setIndex: min(done, target) + 1)
            if done < target { break }
        }
        return position
    }
}
