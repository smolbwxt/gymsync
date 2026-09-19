import Foundation

// MARK: - RoutineProgression
//
// "Which exercise should this lifter be logging?" — the group session's
// answer was hardcoded to routineExercises.first since the live screen
// shipped (an in-code-documented gap): every set of a multi-exercise
// routine wrote against exercise 1, and the set counter climbed past its
// target forever ("Set 13/3", observed on device 2026-07-30).
//
// The rule, matching the solo screen's semantics: the FIRST exercise (by
// routine position) whose completed set count is below its target. Failed
// sets count — they consumed an attempt, same as solo's currentSetIndex.
// Once every exercise is finished the LAST one is returned rather than
// nil, so the session always has a valid write target (a lifter doing
// bonus sets keeps logging against the final movement, they don't crash).
//
// Pure and injected so it is unit-testable and so the caller decides what
// "completed" means (the group screen counts the LIFTER's own sets from
// the UNCAPPED session array — never the 30-row feed).
// Superset pairs (set structures phase B, 2026-08-14): an ADJACENT pair
// sharing `supersetGroup` alternates — A, then B, then A's next round —
// by comparing completed counts, and the pair only releases the
// progression once BOTH sides hit their targets. Because the group
// screen derives its current exercise through this function per lifter,
// each crew member alternates their own pair on their own turns with no
// view-side machinery.
enum RoutineProgression {

    /// DECISION 3'S RULE, WRITTEN DOWN ONCE (Phase C1, `set_logs.
    /// routine_exercise_id`):
    ///
    ///   a slot's completed count is the number of rows whose
    ///   `routine_exercise_id` equals the SLOT id, plus — ONLY when the slot
    ///   has zero such rows — the number of rows whose `exercise_id` equals
    ///   the slot's exercise id and whose `routine_exercise_id` is NULL.
    ///
    /// That gives byte-identical behaviour for an all-old session (no row
    /// names a slot, so every count comes from the fallback exactly as it
    /// did before the column), correct behaviour for an all-new one, and the
    /// OLD behaviour for the one session that straddles the deploy — which
    /// is the honest choice, because a slot that has started naming itself
    /// cannot also be served by a lift-wide guess.
    ///
    /// THE FALLBACK IS PERMANENT, not transitional: a freeform ad-hoc set has
    /// no slot to name and never will (its rows are synthesized and never
    /// persisted), and there is no backfill for history.
    ///
    /// `logs` is already this lifter's own, penalties already dropped — the
    /// caller owns "whose sets" and "which sets count", exactly as
    /// `currentExercise`'s injected counter always has.
    static func completedRows(forSlot re: RoutineExercise, in logs: [SetLog]) -> [SetLog] {
        let attributed = logs.filter { $0.routineExerciseID == re.id }
        if !attributed.isEmpty { return attributed }
        return logs.filter {
            $0.routineExerciseID == nil && $0.exerciseID == re.exerciseID
        }
    }

    /// The count of the rule above. Two spellings of one rule, and the count
    /// is derived from the rows rather than restating the filter, so a
    /// screen listing a slot's sets and a walk counting them can never
    /// disagree about which rows those are.
    static func completedSets(forSlot re: RoutineExercise, in logs: [SetLog]) -> Int {
        completedRows(forSlot: re, in: logs).count
    }

    /// WHICH SLOT THIS LIFTER SHOULD BE LOGGING — the walk, counted per SLOT.
    ///
    /// The slot-keyed sibling of `currentExercise` below and the one the app
    /// now calls (Phase C1, decision 3). It is spelled as its own function
    /// rather than an overload for a mundane reason: two `completedSets:`
    /// closures differing only in their parameter type make every call site's
    /// closure literal ambiguous.
    static func currentSlot(
        routine: [RoutineExercise],
        completedSets: (RoutineExercise) -> Int
    ) -> RoutineExercise? {
        let ordered = routine.sorted { $0.position < $1.position }
        var index = 0
        while index < ordered.count {
            let re = ordered[index]
            if let group = re.supersetGroup, index + 1 < ordered.count,
               ordered[index + 1].supersetGroup == group {
                let partner = ordered[index + 1]
                let a = completedSets(re)
                let b = completedSets(partner)
                let targetA = max(1, re.targetSets ?? 1)
                let targetB = max(1, partner.targetSets ?? 1)
                if a >= targetA && b >= targetB { index += 2; continue }
                // A leads each round; B owes a set whenever A is ahead.
                if a > b && b < targetB { return partner }
                if a < targetA { return re }
                return partner
            }
            if completedSets(re) < max(1, re.targetSets ?? 1) {
                return re
            }
            index += 1
        }
        return ordered.last
    }

    /// THE PRE-COLUMN SPELLING, KEPT — counting BY LIFT.
    ///
    /// Not a duplicate of `currentSlot`: it delegates to it, so there is one
    /// walk and one superset alternation. What it is, is the caller-facing
    /// shape for a counter that knows only an exercise id — which is what
    /// every reader had before `set_logs.routine_exercise_id`, and what a
    /// freeform session's synthesized rows still are.
    ///
    /// A caller with LOGS in hand should prefer `currentSlot` with
    /// `completedSets(forSlot:in:)`: counting by lift is what let a routine
    /// naming one lift twice fill slot 3 with slot 7's sets.
    static func currentExercise(
        routine: [RoutineExercise],
        completedSets: (UUID) -> Int
    ) -> RoutineExercise? {
        currentSlot(routine: routine,
                    completedSets: { re in completedSets(re.exerciseID) })
    }

    /// Are these two exercises the two sides of one superset pair?
    /// Adjacent + shared group — adjacency IS the pair's definition
    /// (guaranteed by the builder's save-time normalization).
    static func arePaired(_ first: RoutineExercise?, _ second: RoutineExercise?,
                          in routine: [RoutineExercise]) -> Bool {
        guard let first, let second, first.id != second.id,
              let group = first.supersetGroup,
              second.supersetGroup == group else { return false }
        let ordered = routine.sorted { $0.position < $1.position }
        guard let i = ordered.firstIndex(where: { $0.id == first.id }),
              let j = ordered.firstIndex(where: { $0.id == second.id }) else { return false }
        return abs(i - j) == 1
    }
}
