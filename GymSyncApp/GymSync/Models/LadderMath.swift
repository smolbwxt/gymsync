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

// MARK: - A10: the current rung becomes the week's goal

extension LadderMath {

    /// Spec §4: the shipped weekly goal IS the materialised current rung.
    ///
    /// `source = .coach` on purpose and by rule: this is a Coach write, which
    /// `WeeklyGoalWriteRule.shouldOverwrite` permits over no row and over
    /// Coach's own — and refuses over a row the athlete set, which is exactly
    /// the rung-override the design wants (§4: "an athlete's edit of this
    /// week's row is an override of the rung").
    ///
    /// nil when the metric has no weekly shape — there is none in phase 1, and
    /// the `nil` return exists so phase 2's `vo2Max` (a test day, not a week)
    /// has somewhere honest to land.
    static func weeklyGoal(from rung: LadderRung, goal: BlockGoal,
                           userID: UUID, now: Date) -> WeeklyGoal? {
        var params = WeeklyGoalParams()
        params.goalID = goal.id
        params.byDate = goal.byDate
        let kind: WeeklyGoalKind

        switch goal.metric {
        case .liftOneRepMax:
            kind = .lift
            params.exerciseID = rung.target.exerciseID ?? goal.target.exerciseID
            params.targetWeightLbs = rung.target.targetWeightLbs
        case .liftRepsAtLoad:
            kind = .lift
            params.exerciseID = rung.target.exerciseID ?? goal.target.exerciseID
            params.targetWeightLbs = rung.target.loadLbs ?? goal.target.loadLbs
            params.targetReps = rung.target.targetReps
        case .weeklyMuscleSets:
            kind = .muscleSets
            params.muscleTargets = rung.target.muscleTargets
            // Where the number came from, for the strip's own provenance —
            // "block" is a third value beside the shipped "titration" and
            // "routines", and it is the truthful one here: this target is the
            // block's prescribed volume, not the search's and not a template's.
            params.targetSource = "block"
        case .weeklyDistance:
            kind = .distance
            params.activity = rung.target.activity ?? goal.target.activity
            params.distanceTarget = rung.target.distance
        case .trainingDaysPerWeek:
            // NO `count` (the controller's 2026-09-06 ruling, which
            // `WeeklyGoalDetector.daysParams` records): the profile's weekly
            // session goal is the single source of truth for this number, and a
            // mirror in `params` is precisely how the strip and the streak tile
            // would come to disagree. The rung's own days number reaches the
            // athlete through the ladder page, not through this row.
            kind = .days
        case .sessionsOfTypePerWeek:
            kind = .sessionsOfType
            params.sessionType = rung.target.sessionType ?? goal.target.sessionType
            params.count = rung.target.sessions
        case .stretchingExercisesPerWeek, .lissMinutesPerWeek:
            // ONE goal, two metrics (spec §2.3). Whichever of the pair the goal
            // names, the row carries both numbers, because the strip renders
            // them on one rung.
            kind = .recovery
            params.count = rung.target.stretchingExercises
            params.lissMinutes = rung.target.lissMinutes
        case .bodyWeight:
            kind = .bodyWeight
            params.bodyWeightLbs = rung.target.bodyWeightLbs
        case .cumulativeVolume:
            kind = .volume
            params.volumeLbs = rung.target.volumeLbs
        case .benchmarkTime:
            kind = .benchmark
            params.routineID = rung.target.routineID ?? goal.target.routineID
            params.targetSeconds = rung.target.targetSeconds
        }

        return WeeklyGoal(userID: userID, weekStartString: rung.weekStartString,
                          kind: kind, params: params, source: .coach, setAt: now)
    }

    /// The rung for a week, or nil when the block does not cover it.
    static func rung(in ladder: Ladder, weekStart: String) -> LadderRung? {
        ladder.rungs.first { $0.weekStartString == weekStart }
    }
}
