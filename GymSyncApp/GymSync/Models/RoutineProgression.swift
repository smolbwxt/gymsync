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
    /// A caller with LOGS in hand should prefer `currentSlot` fed from a
    /// `SlotProgress`: counting by lift is what let a routine naming one
    /// lift twice fill slot 3 with slot 7's sets.
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

// MARK: - SlotProgress
//
// WHICH LOGGED SETS BELONG TO WHICH SLOT — decision 3's rule, written down
// once, and computed in ONE PASS over the logs rather than once per slot
// (review F6: the per-slot spelling made a single body pass roughly
// O(slots² × logs), inside a view whose render budget is a stated
// constraint).
//
// THE RULE, as amended by review F2:
//
//   A slot's sets are the rows that NAME it, plus the unattributed rows
//   whose exercise is the slot's EFFECTIVE (layered) exercise — divided
//   among the slots naming that lift in routine order, each taking only what
//   its target still has room for, and any surplus going to the last of them.
//
// The shipped rule was "plus, ONLY when the slot has zero named rows" —
// decision 3's own words, faithfully implemented, and wrong in two ways the
// review caught. A session that STRADDLES the app update (two pre-column
// sets, then one attributed) counted 1 instead of 3 and rewound the lifter
// into re-logging work already in the log — a one-session instance of the
// exact failure this phase exists to end. And any future unattributed writer
// — a wrist tap from an older Watch build — silently vanished from a slot
// that already had phone-logged sets. NULL-slot rows are never dropped now:
// they are placed, and the placement is deterministic.
//
// WHY "IN ORDER, UP TO TARGET" RATHER THAN "AT THE FIRST SLOT ONLY" (ruling
// R-F2-1): the literal reading gives every unattributed row of a lift to the
// first slot naming it, which changes the answer for an ALL-NULL routine that
// names one lift twice — four bench sets across two slots of three would read
// 4 / 0 where the shipped walk reads 3 / 1. Decision 3 requires a pre-column
// session to land exactly where it landed yesterday, and that greedy division
// IS yesterday. Counting in order with a cap carries the same
// anti-double-count guarantee — no row is counted at two slots — and keeps
// the old answer.
//
// THE FALLBACK IS PERMANENT, not transitional: a freeform ad-hoc set has no
// slot to name and never will (its rows are synthesized and never persisted),
// and there is no backfill for history.
//
// `logs` is already this lifter's own with penalties dropped. The caller owns
// "whose sets" and "which sets count", exactly as the injected counter always
// has.
struct SlotProgress {
    /// slot id → the rows that slot owns.
    private let bySlot: [UUID: [SetLog]]

    init(routine: [RoutineExercise], logs: [SetLog]) {
        var attributed: [UUID: [SetLog]] = [:]
        var unattributed: [UUID: [SetLog]] = [:]
        for log in logs {
            if let slotID = log.routineExerciseID {
                attributed[slotID, default: []].append(log)
            } else {
                unattributed[log.exerciseID, default: []].append(log)
            }
        }
        // Routine order, so the division of an undifferentiated pre-column
        // pile is deterministic and agrees with `currentSlot`'s own walk.
        let ordered = routine.sorted { $0.position < $1.position }
        var owned: [UUID: [SetLog]] = [:]
        for re in ordered {
            var rows = attributed[re.id] ?? []
            let room = max(0, max(1, re.targetSets ?? 1) - rows.count)
            if room > 0, let pool = unattributed[re.exerciseID], !pool.isEmpty {
                let take = min(room, pool.count)
                rows.append(contentsOf: pool.prefix(take))
                unattributed[re.exerciseID] = Array(pool.dropFirst(take))
            }
            owned[re.id] = rows
        }
        // NOTHING IS DROPPED. A pile bigger than every target's room — a
        // lifter doing bonus sets before the column existed — lands on the
        // LAST slot naming that lift, which is where the shipped walk left
        // them standing.
        for re in ordered.reversed() {
            guard let pool = unattributed[re.exerciseID], !pool.isEmpty else { continue }
            owned[re.id, default: []].append(contentsOf: pool)
            unattributed[re.exerciseID] = []
        }
        bySlot = owned
    }

    /// The rows this slot owns, in the order they were handed in.
    func rows(for re: RoutineExercise) -> [SetLog] { bySlot[re.id] ?? [] }

    func count(for re: RoutineExercise) -> Int { bySlot[re.id]?.count ?? 0 }
}
