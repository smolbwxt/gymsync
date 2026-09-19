import Foundation

// MARK: - Coach's readiness suggestion (spec §2 and §4, plan decisions 4 and 5)
//
// Spec §2's example — "you slept five hours and today is 4×5 at 225 — want
// 3×5?" — names a signal this app does not have: THERE IS NO SLEEP SOURCE.
// HealthKit is read for heart rate only (`HealthKitBridge`) and global
// constraint 10 forbids any new authorization request, so this reads three
// things that already exist:
//
//   the block's standing   `BlockGoalRepository.activeGoal()` + `.page(goalID:)`
//                          -> the current rung's status and `reachesMilestone`
//   last session's effort  `SessionRepository.recentSetLogs(userID:since:)`
//                          -> the mean RPE of the most recent logged day, and
//                             how many days ago that was
//   open soreness          `RecoveryProbeRepository.open()` -> the muscles an
//                             unanswered probe is still waiting on
//
// `suggestion(signal:)` is PURE over those values plus today's plan rows, and
// returns at most one suggestion — the strongest — or nil. **nil IS THE NORMAL
// CASE**, and a warm-up with no suggestion is the shipped screen, which is why
// frames 132 and 133 do not move (constraint 14).
//
// THE SIGNAL IS NAMED IN THE SENTENCE. A suggestion that does not say what it
// read is the thing Phase A deleted, so `Suggestion` carries both halves and
// the card prints both.
enum WarmUpReadiness {

    /// One row of today's plan, as the rule reads it.
    ///
    /// A STRUCT rather than the brief's tuple: it is stored in `@State`,
    /// compared, and built in tests, and a tuple of five labelled members is
    /// none of those things comfortably. `targetReps` is one member beyond the
    /// brief's list, so the proposal can say "4 × 5 — want 3 × 5?" instead of
    /// counting sets at the athlete.
    struct PlanRow: Equatable, Sendable {
        let exerciseID: UUID
        let name: String
        /// `Exercise.primaryMuscle`. Nil when the catalog did not resolve the
        /// row, which makes it un-suggestable rather than a guess.
        let muscle: String?
        let targetSets: Int?
        let targetReps: String?
    }

    /// Everything the rule reads. Every term is independently optional: each
    /// of the three reads is best-effort, and a signal with every term nil
    /// produces no suggestion.
    struct Signal: Equatable, Sendable {
        var rungStatus: RungStatus?
        var reachesMilestone: Bool = true
        var lastSessionMeanRPE: Double?
        var daysSinceLastSession: Int?
        /// Lower-cased muscle slugs, compared against `PlanRow.muscle` the
        /// same way.
        var openProbeMuscles: Set<String> = []
        var planRows: [PlanRow] = []
    }

    /// What Coach proposes, and what it read to propose it.
    struct Suggestion: Equatable, Sendable {
        let exerciseID: UUID
        /// One fewer than the plan's own count for that row.
        let setsInstead: Int
        /// What was read — "Your last session averaged RPE 9 yesterday, and
        /// your chest is still sore."
        let read: String
        /// What is proposed — "Today is 4 × 5 on Bench Press — want 3 × 5?"
        let proposal: String
    }

    /// Coming in hot. Spec §4's own threshold, pinned in one place.
    static let hotMeanRPE = 8.5
    /// The last dose is still being paid for only while it is this recent.
    static let stillPayingWithinDays = 2

    /// Decision 4's rule, and nothing more.
    ///
    ///  - a `.missed` rung that can no longer reach the milestone suggests
    ///    NOTHING: that conversation belongs to the ladder page's own proposal
    ///    (spec §4), and two screens proposing different repairs for one block
    ///    is how an athlete stops trusting either;
    ///  - an open probe on a muscle today trains, AND last session's mean RPE
    ///    at or above `hotMeanRPE`, AND fewer than `stillPayingWithinDays`
    ///    days since -> one set fewer on the day's heaviest dose of that
    ///    muscle;
    ///  - otherwise nil.
    ///
    /// "THE DAY'S HEAVIEST COMPOUND" IS READ AS THE DAY'S BIGGEST DOSE. The
    /// plan rows carry prescribed SETS, not load — `targetWeight` is free text
    /// most rows do not have — so the row with the most sets on a sore muscle
    /// is the one a set comes off. A one-set row is never picked: taking the
    /// only set off an exercise is deleting it, not scaling it.
    static func suggestion(signal: Signal) -> Suggestion? {
        if signal.rungStatus == .missed && !signal.reachesMilestone { return nil }

        guard let meanRPE = signal.lastSessionMeanRPE, meanRPE >= hotMeanRPE,
              let days = signal.daysSinceLastSession, days < stillPayingWithinDays,
              !signal.openProbeMuscles.isEmpty
        else { return nil }

        let sore = Set(signal.openProbeMuscles.map { $0.lowercased() })
        let candidates = signal.planRows.filter { row in
            guard let muscle = row.muscle, let sets = row.targetSets, sets >= 2
            else { return false }
            return sore.contains(muscle.lowercased())
        }
        // The first of the equals, so a tie is broken by plan order rather
        // than by whichever way `max(by:)` happens to lean.
        let pick = candidates.reduce(nil as PlanRow?) { best, row in
            guard let best else { return row }
            return (row.targetSets ?? 0) > (best.targetSets ?? 0) ? row : best
        }
        guard let pick, let sets = pick.targetSets else { return nil }

        let muscle = (pick.muscle ?? "").lowercased()
        return Suggestion(
            exerciseID: pick.exerciseID,
            setsInstead: sets - 1,
            // "your chest IS still sore" / "your quads IS still sore": muscle
            // slugs are singular and plural both, so the sentence is written
            // around the verb rather than inflecting it — and it names the
            // probe for what it is, an answer the athlete has not given yet.
            read: "Your last session averaged RPE \(rpeText(meanRPE)) \(dayPhrase(days))"
                + ", and you haven't marked \(muscle) recovered yet.",
            proposal: proposalSentence(row: pick, sets: sets))
    }

    /// `9`, not `9.0`; `8.5` keeps its half.
    static func rpeText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func dayPhrase(_ days: Int) -> String {
        switch days {
        case ..<1: return "today"
        case 1:    return "yesterday"
        default:   return "\(days) days ago"
        }
    }

    /// "Today is 4 × 5 on Bench Press — want 3 × 5?" — and, for a row with no
    /// rep target, the honest "Today is 4 sets of Bench Press — want 3?"
    private static func proposalSentence(row: PlanRow, sets: Int) -> String {
        if let reps = row.targetReps, !reps.isEmpty {
            return "Today is \(sets) × \(reps) on \(row.name) — want \(sets - 1) × \(reps)?"
        }
        return "Today is \(sets) sets of \(row.name) — want \(sets - 1)?"
    }
}

/// TODAY'S SET REDUCTION (plan decision 5), which now OUTLIVES A RELAUNCH
/// (owner 2026-09-18: "Yes" — decision 3).
///
/// There is no per-session prescription override anywhere: `routine_exercises`
/// is the routine's own row and the trainer-prescription table is a different
/// subject. So Accept sets this on `SessionRunnerView`, which passes it through
/// `SessionInProgressView` into `SessionLiveView`, where
/// `effectiveRoutineExercises` layers it after the squad swap and the self
/// scale — the order `RoutineLayering` now holds for both screens.
///
/// THE ACCEPTED CONSEQUENCE IS GONE. It used to read "a relaunch mid-session
/// loses it: nothing is written to the database". It is now written to
/// `session_participants.todays_scale` on Accept — my own row, the same
/// own-row policy `energy` already rides — and re-seeded from the participant
/// rows the runner already fetches, so a phone that died mid-session comes
/// back to the dose the athlete agreed to. The write is BEST-EFFORT: a
/// failure leaves the in-memory value standing and the session behaves
/// exactly as B2 shipped it, because §4 still holds either way — the
/// athlete's tap is the only thing that changes the number.
///
/// CLEARED BY NOTHING. The session ends and the row stops being read.
struct TodaysScale: Equatable, Sendable, Codable {
    /// The ROUTINE's own exercise for that slot, which is what the warm-up's
    /// plan rows carry. A squad swap later replaces the exercise in the slot
    /// and the reduced set count rides with the slot.
    let exerciseID: UUID
    let setsInstead: Int

    /// `session_participants.todays_scale jsonb` (20260918, decision 3) —
    /// `{"exercise_id": "<uuid>", "sets_instead": <int>}`. The column's own
    /// shape, so a row written by the app and a row read back by it are the
    /// same object and no second spelling exists.
    enum CodingKeys: String, CodingKey {
        case exerciseID = "exercise_id"
        case setsInstead = "sets_instead"
    }
}
