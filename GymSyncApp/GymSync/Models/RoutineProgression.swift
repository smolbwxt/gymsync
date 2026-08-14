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

    static func currentExercise(
        routine: [RoutineExercise],
        completedSets: (UUID) -> Int
    ) -> RoutineExercise? {
        let ordered = routine.sorted { $0.position < $1.position }
        var index = 0
        while index < ordered.count {
            let re = ordered[index]
            if let group = re.supersetGroup, index + 1 < ordered.count,
               ordered[index + 1].supersetGroup == group {
                let partner = ordered[index + 1]
                let a = completedSets(re.exerciseID)
                let b = completedSets(partner.exerciseID)
                let targetA = max(1, re.targetSets ?? 1)
                let targetB = max(1, partner.targetSets ?? 1)
                if a >= targetA && b >= targetB { index += 2; continue }
                // A leads each round; B owes a set whenever A is ahead.
                if a > b && b < targetB { return partner }
                if a < targetA { return re }
                return partner
            }
            if completedSets(re.exerciseID) < max(1, re.targetSets ?? 1) {
                return re
            }
            index += 1
        }
        return ordered.last
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
