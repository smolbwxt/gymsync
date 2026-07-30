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
enum RoutineProgression {

    static func currentExercise(
        routine: [RoutineExercise],
        completedSets: (UUID) -> Int
    ) -> RoutineExercise? {
        let ordered = routine.sorted { $0.position < $1.position }
        return ordered.first { re in
            completedSets(re.exerciseID) < max(1, re.targetSets ?? 1)
        } ?? ordered.last
    }
}
