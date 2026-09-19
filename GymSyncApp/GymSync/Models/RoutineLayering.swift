import Foundation

// MARK: - RoutineLayering
//
// THE THREE LAYERS BETWEEN THE ROUTINE AND WHAT THE LIFTER ACTUALLY DOES, in
// one place. The order is the rule, and the rule is a product decision:
//
//   1. THE SQUAD SWAP, which is everyone's — the crew voted, so the lift in
//      that slot changes for the whole crew.
//   2. MY QUIET SELF-SCALE, which beats it — my own choice for my own body
//      outranks the squad's choice for the room. Never announced.
//   3. TODAY'S ACCEPTED SET REDUCTION, last — the warm-up's own Accept, which
//      is mine alone and is about the DOSE rather than about the lift. Keyed
//      on the ROUTINE'S OWN exercise, which is what the warm-up's plan rows
//      carried when the athlete accepted: a squad swap that lands afterwards
//      replaces the lift in that slot and the reduced set count rides WITH
//      the slot, which is what "one set fewer today" meant.
//
// It was written out by hand in THREE places (the docket's B2 leftovers):
// `SessionLiveView.effectiveRoutineExercises`, `SessionRunnerView.planRows`
// and one test. Three copies of an order is three chances for two screens to
// print different prescriptions for the same lift, so it lives here now and
// `RoutineLayeringTests` is the ONLY place the order is asserted.
enum RoutineLayering {

    /// THE ONE REBUILD A SWAP PERFORMS on a routine row — the replacement's
    /// exercise id, the same prescription, and no weight (a bar number for one
    /// lift is not a bar number for another).
    ///
    /// It lives BESIDE the layering, not inside it, because TWO places need
    /// it: `apply` uses it for real, and `SessionLiveView.swapDoorDetails`
    /// uses it to word the consent card's PROPOSED door. A door that computed
    /// the proposed prescription its own way could promise something the swap
    /// does not produce — which is exactly what it did for a to-failure row
    /// (R-B2-15).
    ///
    /// `targetFailure` IS CARRIED (R-B2-13). The old spelling listed fields by
    /// hand and left it behind, so a swapped `AMRAP` row silently became
    /// `3 × —`: a prescribed failure is the assignment fulfilled (the failure
    /// doctrine), and swapping the lift does not cancel it.
    ///
    /// `setType`, `dropSteps` and `dropPercent` ARE CARRIED TOO (hotfix
    /// 2026-09-18, ruling H6). They were named here as knowingly dropped on
    /// the grounds that the live body renders none of them — but SOLO does:
    /// `WorkoutSessionView.repTargetLabel` prints "TOP + DROP 2×20%" from
    /// them and the log path arms the drop-ladder sheet off `setType`. Solo
    /// kept its own hand-written rebuild, which dropped these AND
    /// `targetFailure`; routing it here is what closes that, so the fields
    /// the one caller reads have to survive the trip. A drop prescription is
    /// a set STRUCTURE — how hard the dose is, not which lift delivers it —
    /// so it rides the slot exactly as the set count does.
    ///
    /// The bar number is the one thing that never survives: a weight for one
    /// lift is not a weight for another.
    static func swapped(_ re: RoutineExercise, to targetID: UUID) -> RoutineExercise {
        RoutineExercise(
            id: re.id, routineID: re.routineID, exerciseID: targetID,
            position: re.position, targetSets: re.targetSets,
            targetReps: re.targetReps, targetWeight: nil,
            restSeconds: re.restSeconds, notes: re.notes,
            setType: re.setType,
            supersetGroup: re.supersetGroup,
            dropSteps: re.dropSteps,
            dropPercent: re.dropPercent,
            targetFailure: re.targetFailure,
            targetRepsLow: re.targetRepsLow, targetRepsHigh: re.targetRepsHigh,
            cardioZone: re.cardioZone, cardioMinutes: re.cardioMinutes)
    }

    /// The routine as this lifter will actually run it.
    ///
    /// - Parameters:
    ///   - rows: the shared routine, in its own order.
    ///   - squadSwaps: original exercise id → the replacement the crew voted
    ///     in, for everyone.
    ///   - selfScale: MY OWN quiet replacements, original exercise id → the
    ///     lift I am doing instead. Beats a squad swap for the same slot.
    ///   - todaysScale: the warm-up's accepted set reduction, keyed on the
    ///     routine's own exercise.
    ///
    /// Every default is the empty layer, so a caller that has only one of the
    /// three — the warm-up screen, which has no swaps at all — names only what
    /// it has.
    static func apply(_ rows: [RoutineExercise],
                      squadSwaps: [UUID: UUID] = [:],
                      selfScale: [UUID: UUID] = [:],
                      todaysScale: TodaysScale? = nil) -> [RoutineExercise] {
        rows.map { re in
            var target: UUID? = squadSwaps[re.exerciseID]
            if let mine = selfScale[re.exerciseID] { target = mine }
            var row = target.map { swapped(re, to: $0) } ?? re
            if let scale = todaysScale, scale.exerciseID == re.exerciseID {
                row.targetSets = scale.setsInstead
            }
            return row
        }
    }
}
