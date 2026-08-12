import Foundation

// MARK: - WorkingWeight
//
// "What weight should be on the bar for THIS set?" — one ordered ladder,
// best information first, shared by the live session's bar loader and (via
// the same call) the solo screen.
//
// User direction 2026-07-30: "If there is a bar, it should be prepopulated
// with what the estimated weight should be based on rep goal and campaign
// modifier." Before this, the loader prefilled with the routine's typed
// target or simply the last weight lifted — which answers "what did I
// lift", not "what should I lift".
//
// THE LADDER (first rung with real inputs wins):
//   1. .campaign     enrolled + this exercise is a focus lift + the current
//                    program week prescribes a percentage
//                    → percent × the frozen enrollment baseline
//   2. .routine      an explicit target typed into the routine
//   3. .repGoal      inverse Epley from the user's best qualifying set,
//                    solved for the routine's target rep count
//   4. .lastSet      what they actually lifted last on this exercise
//   5. nil           NOTHING. The bar loader falls back to bar weight.
//
// THE FLOOR IS ABSOLUTE: this never invents a number. Every rung returns
// nil when its inputs are missing, matching the doctrine already stated
// twice in this layer — `ProgramMath.targetWeight` ("no baseline → no number,
// never a guess") and `StatMath.projectedWeight` ("callers show NO estimate
// when there is no PR"). A wrong prefilled weight is worse than none,
// because someone will load it.
//
// All weights in and out are CANONICAL POUNDS. Display conversion happens
// at the call site, exactly once, the same as everywhere else.
enum WorkingWeight {

    /// Where a suggestion came from — so the UI can show its reasoning
    /// rather than an unexplained number.
    enum Source: Equatable {
        case campaign(percent: Double, week: Int)
        case routine
        case repGoal(targetReps: Int)
        case lastSet
    }

    struct Suggestion: Equatable {
        let pounds: Decimal
        let source: Source
    }

    /// The ladder. `history` is this user's prior sets for THIS exercise
    /// (any order); `lastSet` is their most recent one, if any.
    ///
    /// `enrollment`/`template` are passed in rather than fetched so this
    /// stays pure and unit-testable — the caller already holds them.
    static func suggest(
        exerciseID: UUID,
        targetReps: Int?,
        routineTargetPounds: Decimal?,
        history: [SetLog],
        lastSetPounds: Decimal?,
        enrollment: ProgramEnrollment?,
        now: Date = .now
    ) -> Suggestion? {

        // 1 — CAMPAIGN. Outranks the routine's own number because it IS the
        // rep goal plus this week's modifier, already computed against a
        // baseline frozen at enrollment.
        if let enrollment,
           enrollment.endedAt == nil,
           let template = enrollment.template,
           enrollment.focus.exerciseIDs?.contains(exerciseID) == true,
           let baseline = enrollment.baselineValue(for: exerciseID) {
            let week = ProgramMath.currentWeek(startedOn: enrollment.startedOn,
                                           weeks: template.weeks.count,
                                           now: now)
            // `currentWeek` is 1-based and clamped, so this index is safe.
            let scheme = template.weeks[week - 1]
            if let percent = scheme.percentOfBaseline,
               let target = ProgramMath.targetWeight(percentOfBaseline: percent, baseline: baseline) {
                return Suggestion(pounds: Decimal(target),
                                  source: .campaign(percent: percent, week: week))
            }
            // A volume/test week prescribes no percentage — fall through
            // rather than inventing one.
        }

        // 2 — ROUTINE. An explicit number the user typed into the routine.
        if let routineTargetPounds, routineTargetPounds > 0 {
            return Suggestion(pounds: routineTargetPounds, source: .routine)
        }

        // 3 — REP GOAL. Inverse Epley off their best qualifying set: the
        // weight that should yield `targetReps` given demonstrated strength.
        if let targetReps, targetReps > 0,
           let best = bestQualifyingSet(in: history),
           let projected = StatMath.projectedWeight(prWeight: best.weight,
                                                    prReps: best.reps,
                                                    targetReps: targetReps) {
            return Suggestion(pounds: Decimal(projected),
                              source: .repGoal(targetReps: targetReps))
        }

        // 4 — LAST SET. What they actually did last time.
        //
        // Deliberately NOT rep-scaled (considered and rejected 2026-08-02):
        // scaling needs a rep count to scale FROM, and any history entry that
        // could supply one already satisfies rung 3's identical precondition —
        // so rung 3 returns first and a rep-aware rung 4 would be unreachable.
        // This rung fires only when we know a weight and nothing about the
        // reps behind it, where passing the number through unchanged is the
        // honest answer.
        if let lastSetPounds, lastSetPounds > 0 {
            return Suggestion(pounds: lastSetPounds, source: .lastSet)
        }

        // 5 — nothing honest to say.
        return nil
    }

    /// Best (weight, reps) pair by Epley est-1RM — the same qualifying
    /// filter `ProgramMath.baseline(fromHistory:)` uses, so a rep-goal
    /// projection and a program baseline never disagree about which sets
    /// count: no failed sets, no penalty sets, both fields present.
    static func bestQualifyingSet(in logs: [SetLog]) -> (weight: Decimal, reps: Int)? {
        var best: (weight: Decimal, reps: Int)?
        var bestOneRM: Decimal = 0
        for log in logs {
            guard !log.isFailed, !log.isPenalty,
                  let reps = log.reps, let weight = log.weight,
                  reps > 0, weight > 0 else { continue }
            // RPE-aware (research audit 2026-08): a hard 5×315 @9 and an
            // easy 5×315 @6 are different signals — reps-in-reserve feed
            // the estimate on suggestion paths (never on PR judgments).
            let oneRM = StatMath.estimatedOneRepMax(weight: weight, reps: reps, rpe: log.rpe)
            if oneRM > bestOneRM {
                bestOneRM = oneRM
                best = (weight, reps)
            }
        }
        return best
    }
}
