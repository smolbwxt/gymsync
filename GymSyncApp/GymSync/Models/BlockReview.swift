import Foundation

// MARK: - BlockReview
//
// Block N's outcomes seed block N+1 (longitudinal spec 3e, owner: "have
// the entire history of your work together inform the future"). Pure
// functions over set logs — no network, no UI.
//
// The stall verdicts come from `BlockProgression.decide` — the SAME
// engine the live session runs, never a reimplementation, so the review
// can never disagree with what Coach told the athlete mid-block.

enum BlockReview {

    /// What one lift was prescribed as, for the review's stall oracle.
    struct Prescription {
        let exerciseID: UUID
        let repsLow: Int
        let repsHigh: Int
        let isLowerBody: Bool
    }

    struct Outcome: Equatable {
        /// Best e1RM per lift, canonical pounds — the next block's frozen
        /// baselines (the owner-pinned re-freeze-at-block-start rule).
        var newBaselines: [UUID: Decimal] = [:]
        /// Lifts the engine flags as stalled or fatigue-deloading at
        /// block end — the next generation treats them differently
        /// (variation swap via the graph, or a band change).
        var strugglingLiftIDs: Set<UUID> = []
        /// Prescribed lifts the athlete kept skipping (logged in under
        /// 40% of their sessions) — deprioritized next block, never
        /// silently re-prescribed. Adherence beats optimality.
        var abandonedExerciseIDs: Set<UUID> = []
        /// Sessions completed / sessions planned, 0...1+.
        var adherence: Double = 0
        /// What the athlete's actual attendance supports.
        var suggestedDaysPerWeek: Int = 3
    }

    /// - Parameters:
    ///   - logs: the block's set logs, all exercises, any order.
    ///   - prescriptions: the block's prescribed lifts (rep ranges feed
    ///     the stall oracle; lifts absent from logs count as abandoned).
    ///   - plannedSessions: sessions the block scheduled in total.
    ///   - weeks: block length, for the attendance math.
    static func analyze(logs: [SetLog],
                        prescriptions: [Prescription],
                        plannedSessions: Int,
                        weeks: Int) -> Outcome {
        var outcome = Outcome()
        let byExercise = Dictionary(grouping: logs, by: \.exerciseID)
        let allSessions = Set(logs.map(\.sessionID))

        // Attendance: what actually happened, and what it supports.
        outcome.adherence = plannedSessions > 0
            ? Double(allSessions.count) / Double(plannedSessions) : 0
        let perWeek = Double(allSessions.count) / Double(max(1, weeks))
        outcome.suggestedDaysPerWeek = min(7, max(1, Int(perWeek.rounded())))

        for prescription in prescriptions {
            let liftLogs = byExercise[prescription.exerciseID] ?? []

            // Abandonment: prescribed but logged in <40% of the athlete's
            // sessions. A lift they never met (zero logs) counts too.
            let appearances = Set(liftLogs.map(\.sessionID)).count
            if Double(appearances) < 0.4 * Double(max(1, allSessions.count)) {
                outcome.abandonedExerciseIDs.insert(prescription.exerciseID)
            }

            // Baseline re-freeze: best qualifying e1RM across the block.
            if let best = WorkingWeight.bestQualifyingSet(in: liftLogs) {
                outcome.newBaselines[prescription.exerciseID] =
                    StatMath.estimatedOneRepMax(weight: best.weight, reps: best.reps)
            }

            // Stall oracle: the live engine's own verdict at block end.
            switch BlockProgression.decide(history: liftLogs,
                                           repsLow: prescription.repsLow,
                                           repsHigh: prescription.repsHigh,
                                           isLowerBody: prescription.isLowerBody,
                                           isIsolation: false) {
            case .flagStall, .proposeDeload:
                outcome.strugglingLiftIDs.insert(prescription.exerciseID)
            case .advanceLoad, .advanceReps, .warnFatigue, .hold:
                break
            }
        }
        return outcome
    }
}

// MARK: - BlockPlanner
//
// The goal weights allocate BLOCKS over time (owner 2026-08-20 blending
// decision; RP's specialization advice made mechanical: combined training
// that stalls both goals pivots to alternating specialization blocks). A
// 70/30 hypertrophy/strength profile runs mostly hypertrophy mesocycles
// with a periodic strength block — proportional, deterministic.

enum BlockPlanner {

    /// Goals that can OWN a block — the five with full band support.
    /// Weight-only goals (bone density, mobility, general health) tilt
    /// selection inside every block instead of claiming blocks.
    static let blockCapableGoals: Set<TrainingGoal> =
        [.hypertrophy, .maxStrength, .powerRFD, .conditioning, .fatLoss]

    /// The next block's dominant goal, by largest deficit: each goal
    /// deserves weight x (blocks so far + 1); the one furthest behind its
    /// share goes next. Ties break by profile ranking. Deterministic —
    /// the same profile and history always plan the same block.
    static func nextBlockGoal(profile: TrainingProfile,
                              history: [TrainingGoal]) -> TrainingGoal {
        let weights = profile.goalWeights.filter { blockCapableGoals.contains($0.key) }
        guard !weights.isEmpty else { return profile.dominantGoal }
        let total = weights.values.reduce(0, +)
        let horizon = Double(history.count + 1)
        var best: (goal: TrainingGoal, deficit: Double)? = nil
        // Iterate in RANKING order so equal deficits fall to the higher-
        // ranked goal (dictionary order would be nondeterministic).
        for goal in profile.rankedGoals where weights[goal] != nil {
            let share = weights[goal]! / total
            let deserved = share * horizon
            let has = Double(history.filter { $0 == goal }.count)
            let deficit = deserved - has
            if best == nil || deficit > best!.deficit + 0.0001 {
                best = (goal, deficit)
            }
        }
        return best?.goal ?? profile.dominantGoal
    }
}
