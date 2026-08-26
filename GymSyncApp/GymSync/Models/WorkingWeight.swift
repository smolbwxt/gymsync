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
//   2. .repGoal      inverse Epley from the user's best qualifying set,
//                    solved for the routine's target rep count
//   3. .routine      an explicit target typed into the routine
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
        /// Getting-started anchor (owner 2026-08-12): derived from the
        /// confident 5-rep weights stated at onboarding (LiftAnchorMath).
        /// Fires only below every real-data rung — the UI should present
        /// it as a starting estimate, not history.
        case seeded
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
        seededPounds: Decimal? = nil,
        now: Date = .now
    ) -> Suggestion? {

        // THE RETURN HORIZON. Derived from the history we were already
        // handed, never passed in — see TrainingHorizon for why this is
        // not a parameter. When it is nil (nobody has had a layoff) every
        // rung below behaves exactly as it did before.
        //
        // What it suppresses, and why each rung carries pre-layoff data:
        //   1 campaign — a baseline frozen at an enrollment that predates
        //     the layoff IS a pre-layoff max, wearing a percentage.
        //   2 repGoal  — the unbounded best-ever set. THE defect: an
        //     inverse-Epley projection of a two-year-old PR, on the bar,
        //     on session one back.
        //   5 seeded   — the onboarding anchor. A layoff detectable in
        //     this log means signup precedes it, so the anchor is from a
        //     different era of this lifter.
        // Rung 4 (lastSet) needs no guard: callers derive it from this
        // same `history`, so it is post-return by construction whenever a
        // return exists at all.
        let resumedOn = TrainingHorizon.returnDate(in: history, now: now)

        // 1 — CAMPAIGN. Outranks the routine's own number because it IS the
        // rep goal plus this week's modifier, already computed against a
        // baseline frozen at enrollment.
        if let enrollment,
           enrollment.endedAt == nil,
           // A block enrolled before the layoff is prescribing percentages
           // of who they used to be. Note `endedAt == nil` alone does NOT
           // cover this: an abandoned block is never explicitly ended, so
           // a stale enrollment stays "active" indefinitely and its
           // clamped-forward week prescribes a PEAK percentage.
           resumedOn.map({ enrollment.startedOn >= $0 }) ?? true,
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

        // 2 — REP GOAL. Inverse Epley off their best qualifying set: the
        // weight that should yield `targetReps` given demonstrated strength.
        //
        // ABOVE the routine's typed number since 2026-08-24 (field: "a
        // seeded weight when establishing a routine for the first time
        // overrides the felt experience of performing that movement" —
        // JM press written at 135, performed at 155 × 8, still prescribed
        // 135 forever). Demonstrated strength outranks a static seed; the
        // routine's number now fires only until the first qualifying set
        // exists, exactly like the onboarding anchor one rung further
        // down. Deliberate light prescriptions still have homes that
        // outrank this: campaign percentages (rung 1) and BlockProgression
        // decisions at the call site.
        if let targetReps, targetReps > 0,
           let best = bestQualifyingSet(in: TrainingHorizon.sinceReturn(history, now: now)),
           let projected = StatMath.projectedWeight(prWeight: best.weight,
                                                    prReps: best.reps,
                                                    targetReps: targetReps) {
            return Suggestion(pounds: Decimal(projected),
                              source: .repGoal(targetReps: targetReps))
        }

        // 3 — ROUTINE. An explicit number typed into the routine — the
        // starting prescription while no performance evidence exists yet.
        if let routineTargetPounds, routineTargetPounds > 0 {
            return Suggestion(pounds: routineTargetPounds, source: .routine)
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

        // 5 — SEEDED (owner 2026-08-12). The onboarding anchor, via
        // LiftAnchorMath at the call site. Below every real-data rung BY
        // DESIGN: the first real logged set (rung 3/4) permanently outranks
        // the seed, and a seed placed higher could override a lighter real
        // first session.
        if let seededPounds, seededPounds > 0, resumedOn == nil {
            return Suggestion(pounds: seededPounds, source: .seeded)
        }

        // 6 — nothing honest to say.
        return nil
    }

    /// Best (weight, reps) pair by Epley est-1RM — the same qualifying
    /// filter `ProgramMath.baseline(fromHistory:)` uses, so a rep-goal
    /// projection and a program baseline never disagree about which sets
    /// count: failed sets at their completed reps, no penalty sets, both
    /// fields present.
    static func bestQualifyingSet(in logs: [SetLog]) -> (weight: Decimal, reps: Int)? {
        var best: (weight: Decimal, reps: Int)?
        var bestOneRM: Decimal = 0
        for log in logs {
            guard !log.isPenalty,
                  let reps = log.completedReps, let weight = log.weight,
                  weight > 0 else { continue }
            // RPE-aware (research audit 2026-08): a hard 5×315 @9 and an
            // easy 5×315 @6 are different signals — reps-in-reserve feed
            // the estimate on suggestion paths (never on PR judgments).
            // Failure is authoritative (owner 2026-08-13): a failed set IS
            // RIR 0 — base Epley on its completed reps, the truest
            // calibration point history can offer; any logged RPE is
            // contradicted by the miss and ignored.
            let oneRM = log.isFailed
                ? StatMath.estimatedOneRepMax(weight: weight, reps: reps)
                : StatMath.estimatedOneRepMax(weight: weight, reps: reps, rpe: log.rpe)
            if oneRM > bestOneRM {
                bestOneRM = oneRM
                best = (weight, reps)
            }
        }
        return best
    }
}
