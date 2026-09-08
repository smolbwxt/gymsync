import Foundation

// MARK: - LadderMath
//
// Spec §3.5 (adaptive re-laddering), §4 (materialisation) and §6 (standing).
// PURE — the repository fetches, this decides.
//
// THE TWO LAWS THIS FILE ENFORCES:
//   1. re-laddering rewrites ONLY rungs whose status is `ahead` or `current`
//      (spec §8), so a missed week and an overridden week stay visible after
//      the ladder moves;
//   2. the milestone and its date are NEVER moved here. When the re-derived
//      ladder can no longer reach the milestone, `standing` says so and Coach
//      PROPOSES through the shipped propose channel — it does not write.
enum LadderMath {

    /// Mark each rung against the week it describes and what was measured.
    ///
    /// `met` is decided by the metric's own direction: a benchmark TIME is met
    /// by going lower, everything else by going higher. Getting that backwards
    /// would paint a whole ladder green for an athlete who got slower.
    static func statuses(rungs: [LadderRung], metric: GoalMetric,
                         measuredByWeek: [String: GoalTarget],
                         currentWeekStart: String,
                         overriddenWeeks: Set<String> = []) -> [LadderRung] {
        rungs.map { rung in
            var updated = rung
            if overriddenWeeks.contains(rung.weekStartString) {
                updated.status = .overridden
                return updated
            }
            if let measured = measuredByWeek[rung.weekStartString],
               reached(metric: metric, measured: measured, target: rung.target) {
                updated.status = .met
                return updated
            }
            if rung.weekStartString == currentWeekStart {
                updated.status = .current
            } else if rung.weekStartString < currentWeekStart {
                updated.status = .missed
            } else {
                updated.status = .ahead
            }
            return updated
        }
    }

    /// Did `measured` reach `target` for this metric?
    static func reached(metric: GoalMetric, measured: GoalTarget,
                        target: GoalTarget) -> Bool {
        switch metric {
        case .benchmarkTime:
            guard let want = target.targetSeconds, let got = measured.targetSeconds
            else { return false }
            return got <= want                     // lower is better
        case .bodyWeight:
            guard let want = target.bodyWeightLbs, let got = measured.bodyWeightLbs
            else { return false }
            // Direction comes from the goal, not from the number: a cut is met
            // by going under, a gain by going over. `bodyWeightRatePercent` is
            // signed by the rule that wrote the rung (A7).
            let losing = (target.bodyWeightRatePercent ?? 0) < 0
            return losing ? got <= want : got >= want
        case .weeklyMuscleSets:
            let wanted = target.muscleTargets ?? [:]
            let got = measured.muscleTargets ?? [:]
            guard !wanted.isEmpty else { return false }
            return wanted.allSatisfy { (got[$0.key] ?? 0) >= $0.value }
        case .liftOneRepMax:
            return compare(measured.targetWeightLbs, target.targetWeightLbs)
        case .liftRepsAtLoad:
            guard let want = target.targetReps, let got = measured.targetReps
            else { return false }
            return got >= want
        case .weeklyDistance:
            return compare(measured.distance, target.distance)
        case .trainingDaysPerWeek:
            return compare(measured.days, target.days)
        case .sessionsOfTypePerWeek:
            return compare(measured.sessions, target.sessions)
        case .lissMinutesPerWeek:
            return compare(measured.lissMinutes, target.lissMinutes)
        case .stretchingExercisesPerWeek:
            return compare(measured.stretchingExercises, target.stretchingExercises)
        case .cumulativeVolume:
            return compare(measured.volumeLbs, target.volumeLbs)
        }
    }

    private static func compare<T: Comparable>(_ measured: T?, _ target: T?) -> Bool {
        guard let target, let measured else { return false }
        return measured >= target
    }

    /// Re-derive the remaining rungs from `current` — the MEASURED state, not
    /// last week's rung (spec §3.5: "a missed week does not leave a hole to
    /// catch up; the ladder moves").
    ///
    /// Only `ahead` and `current` rungs are replaced. The rungs already met,
    /// missed or overridden are returned exactly as they came in, which is
    /// what makes the ladder page a record of the climb rather than a rolling
    /// forecast that erases its own history.
    static func reLadder(existing: Ladder, metric: GoalMetric,
                         current: GoalTarget, milestone: GoalTarget,
                         constraints: LadderConstraints,
                         rule: any LadderRule,
                         derivedAt: Date) -> Ladder {
        let mutable = existing.rungs.filter { $0.status == .ahead || $0.status == .current }
        guard !mutable.isEmpty else { return existing }

        let fresh = rule.rungs(current: current, target: milestone,
                               weeks: mutable.count, constraints: constraints)
        var byWeek: [String: GoalTarget] = [:]
        for (rung, target) in zip(mutable, fresh) {
            byWeek[rung.weekStartString] = target
        }
        var out = existing
        out.derivedAt = derivedAt
        out.rungs = existing.rungs.map { rung in
            guard let replacement = byWeek[rung.weekStartString] else { return rung }
            var updated = rung
            updated.target = replacement
            return updated
        }
        return out
    }
}
