import Foundation

// MARK: - SessionRoutineEditStore
//
// THE MID-SESSION ROUTINE EDIT IS NEVER ONLY IN THE VIEW (Phase C2,
// decision 2).
//
// `SessionRoutineEditor` rebuilds the slot list mid-workout — add, remove,
// reorder, retune — against a SESSION-LOCAL copy that never touches the
// stored routine mid-flight. On the old solo screen that copy was
// `@State soloEditedList` on `WorkoutSessionView`, which was survivable
// there because that screen was a push nothing destroyed.
//
// IT IS NOT SURVIVABLE IN THE ONE BODY. Phase C1 made an ad-hoc solo
// session a `.fullScreenCover` with MINIMISE as the deliberate way out
// (`SoloSessionLayer.swift`'s `soloMinimiseOverlay`), and MINIMISE
// DESTROYS THE VIEW. An overlay held only in `@State` would be gone the
// moment the lifter checked a message — the added exercise simply vanishes
// from a live workout, which is the same class of live-session data loss
// as the swap the 2026-09-18 hotfix chased.
//
// So this is the same shape `SessionSwapPendingStore` established
// (`Models/SessionSwapLayer.swift`): app-level, `@MainActor`, keyed by
// SESSION id, in memory. The view keeps a mirror it renders from and
// WRITES THROUGH to here on every edit; `reload()` seeds the mirror back
// from here, which is what makes a re-entry after MINIMISE find the list
// the lifter left.
//
// THERE IS NO DURABLE TRUTH BEHIND IT, and that is the difference from the
// swap outbox. A swap has a row (`self_swaps` / `squad_swaps`); a
// mid-session edit has none by design — the stored routine is deliberately
// not written until the workout ends and the lifter answers "Keep your
// mid-session edits?". So this store is the ONLY holder of the edited list
// for the life of the session, and it does not survive a process death.
// Disk persistence for this store and the three beside it is decided and
// docketed: **M2's first task**, copying `OfflineSetLogQueue`'s SwiftData
// idiom (C2 plan, decision 7).
@MainActor
final class SessionRoutineEditStore {
    static let shared = SessionRoutineEditStore()
    /// Public so a test can own its own store rather than mutate a singleton
    /// — `SessionSwapPendingStore`'s own reason.
    init() {}

    private var bySession: [UUID: [RoutineExercise]] = [:]

    /// The edited list this phone holds for the session, or nil when the
    /// lifter has not edited it. NIL AND EMPTY ARE DIFFERENT: an empty array
    /// is a lifter who removed every slot (a freeform workout before its
    /// first pick), and `effectiveRoutineExercises` must show that rather
    /// than falling back to the stored routine.
    func edited(for sessionID: UUID) -> [RoutineExercise]? { bySession[sessionID] }

    /// Record on every Done, before anything else reads it.
    func record(_ rows: [RoutineExercise], for sessionID: UUID) {
        bySession[sessionID] = rows
    }

    /// The session finished, was discarded, or the lifter deliberately left
    /// it — the same moment the swap outbox is cleared, and only then. A
    /// MINIMISE must not reach this (that is the whole reason the store
    /// exists).
    func clear(_ sessionID: UUID) { bySession[sessionID] = nil }
}

// MARK: - SessionRoutineEdit

/// THE END-OF-WORKOUT THREE-WAY'S WRITE HALF, as pure row-building (spec
/// 2026-08-22 §2; Phase C2, decision 2).
///
/// `WorkoutSessionView.persistSessionEdits(asNew:)` built both branches'
/// rows inline, inside a `private func` on a 4,929-line view, so the one
/// rule that matters about them — WHICH IDS SURVIVE — could not be
/// asserted anywhere. It is asserted here instead, and the view's function
/// is now a delegation plus the write.
///
/// THE RULE: a surviving slot keeps its id; an edit is in place; a removal
/// is a removal, never a re-key (ruling R-C-5, generalised). `set_logs`
/// carries `routine_exercise_id` and has no foreign key, so a fresh `UUID()`
/// on a surviving slot silently orphans every set already logged against it
/// — nothing raises, the sets simply stop counting.
enum SessionRoutineEdit {

    /// "Update this routine" — the stored routine is rewritten IN PLACE.
    /// Positions renumber from 1; **every id is preserved**, which is what
    /// makes an ADDED slot's client-minted id become valid retroactively and
    /// what keeps a surviving slot's already-logged sets attributed.
    static func rowsForUpdate(_ edited: [RoutineExercise]) -> [RoutineExercise] {
        edited.enumerated().map { index, re in
            var row = re
            row.position = index + 1
            return row
        }
    }

    /// "Save as a new routine" — cloned into a NEW routine id with FRESH row
    /// ids, through the one copy helper (ruling R-C-6: a hand-written list
    /// dropped `setType`, `dropSteps`, `dropPercent` and `targetFailure`,
    /// silently cancelling a drop ladder and an AMRAP prescription).
    ///
    /// The live session's `routine_id` still points at the ORIGINAL routine,
    /// whose rows are untouched, so nothing this session logged is re-keyed:
    /// an added slot's id never reaches the database at all and its set rows
    /// keep `SlotProgress`'s per-`exerciseID` fallback.
    static func rowsForNewRoutine(_ edited: [RoutineExercise],
                                  routineID: UUID) -> [RoutineExercise] {
        edited.enumerated().map { index, re in
            RoutineLayering.copied(re, intoRoutine: routineID, position: index + 1)
        }
    }
}
