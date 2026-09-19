import Foundation

// MARK: - SessionRoutineCache
//
// THE PLAN A RUNNING SESSION LAST SAW, SO A LOST SIGNAL DOES NOT LOSE IT
// (final review NEW-1).
//
// `RoutineRepository.fetch(id:)` is a plain two-query network read with no
// cache of any kind, and every session body consumes it as
// `if let (routine, exercises) = try? await RoutineRepository.fetch(…)`. That
// is correct while the network answers and silently catastrophic when it does
// not: MINIMISE destroys the view, and a re-entry with no signal leaves
// `routineExercises == []`. Everything this phase fixed then has nothing to
// stand on — a restored swap layer has no row to layer, `SlotProgress` over an
// empty routine owns none of the restored rows, so there is no slot and no
// cursor, and a set logged from that screen writes `routine_exercise_id NULL`.
//
// THE SAME STANCE AS `SessionSwapPendingStore` AND `LiveSessionTimerStore`:
// app-level, in memory, survives the destruction of a view and NOT a relaunch.
// A cold launch with no network is a different problem — it needs the plan on
// disk — and that is deliberately not attempted here (docketed to C2).
//
// A SUCCESSFUL FETCH ALWAYS WINS. This is a fallback, never a cache the app
// reads first: `resolve` returns and records the fresh value whenever there is
// one, so a routine edited between two entries is never masked by a stale
// copy. The cached value is consulted only where the fetch produced nothing.
//
// IT IS FOR THE SESSION BODIES ONLY. The routine editor, the routines list,
// the hub and the trainer screens must keep SHOWING failures — a builder that
// silently edits a remembered copy of a routine it could not read is a worse
// outcome than an error, and those screens have somewhere honest to put one.
// Session bodies do not: their alternative is a workout with no plan.
//
// KEYED BY ROUTINE ID, which is owner-scoped by construction (a routine row
// carries `owner_id` and is read through RLS), so there is nothing here for a
// second user of a shared device to see that they could not read themselves —
// and nothing is written to disk to outlive the process either way.
@MainActor
final class SessionRoutineCache {
    static let shared = SessionRoutineCache()
    /// Public so a test can own its own cache rather than mutate a singleton
    /// — the same reason `SessionSwapPendingStore.init` is public.
    init() {}

    /// What one routine read produces, as a single value: the two halves
    /// travel together or not at all, because a name without rows and rows
    /// without a name are both half a plan.
    struct Loaded {
        var routine: Routine
        var exercises: [RoutineExercise]

        init(routine: Routine, exercises: [RoutineExercise]) {
            self.routine = routine
            self.exercises = exercises
        }
    }

    private var byRoutine: [UUID: Loaded] = [:]

    /// THE WHOLE RULE, in one call so no caller can implement half of it.
    ///
    /// - Parameters:
    ///   - routineID: the routine this session names.
    ///   - fetched: the result of the read — `nil` when it FAILED (or
    ///     returned no row), which is exactly what `try?` produces.
    /// - Returns: the fresh value when there is one (recorded on the way
    ///   through), else the last one that succeeded for this routine, else
    ///   `nil` — which is today's behaviour, unchanged, for a session whose
    ///   plan this process has never seen.
    @discardableResult
    func resolve(routineID: UUID, fetched: Loaded?) -> Loaded? {
        if let fetched {
            byRoutine[routineID] = fetched
            return fetched
        }
        return byRoutine[routineID]
    }

    /// What this process remembers, without recording anything. Only for a
    /// caller that has not made a fetch at all.
    func cached(routineID: UUID) -> Loaded? { byRoutine[routineID] }
}
