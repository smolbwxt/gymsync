import Foundation

// MARK: - LadderMath
//
// THE PURE ARITHMETIC OF A LADDER — no clock, no network, no catalog fetch.
//
// **THIS FILE IS STREAM A'S (task A9), AND STREAM B REACHED IT FIRST.** The
// plan says so in as many words: `LadderMath.weekStartStrings(from:count:)`
// "is a two-line pure helper this task adds to `LadderMath` (A9's file) —
// coordinate with Stream A: it lands in whichever branch reaches it first and
// the other rebases. It is the only symbol the two streams both write."
// `reached(metric:measured:target:)` joins it in task B5, because
// `GoalBlockLength.reach(…)` is written verbatim in the plan around a call to
// it, and `detectedGoal(profile:)` is the stand-in A13 replaces (see its own
// doc comment). Everything Stream A adds here is additive; nothing below is
// Stream A's to delete.
enum LadderMath {

    /// The `count` consecutive week keys a ladder's rungs sit on, walking
    /// forward one week at a time from the week containing `start`.
    ///
    /// `WeekMath`'s device-calendar week, not an ISO one, because that is what
    /// `weekly_goals.week_start` already means everywhere else in this app —
    /// a rung and the row it materialises into must name the same seven days.
    static func weekStartStrings(from start: Date, count: Int,
                                 calendar: Calendar = .current) -> [String] {
        guard count > 0 else { return [] }
        let first = WeekMath.startOfWeek(start, calendar: calendar)
        return (0..<count).compactMap { index in
            calendar.date(byAdding: .day, value: index * 7, to: first)
                .map { WeekMath.weekStartString($0, calendar: calendar) }
        }
    }

    /// Has `measured` got to `target` for this metric?
    ///
    /// PER METRIC, because "reached" is not one comparison: a benchmark time
    /// is reached by going DOWN, a body-weight target by going down or up
    /// depending on the block's own rate, and a muscle-sets target only when
    /// EVERY group named in it is met. An exhaustive switch, so a new metric
    /// cannot join the registry without answering the question.
    ///
    /// FALSE WHEN THE NUMBER IS MISSING on either side. A milestone that names
    /// no number has not been reached — it has not been asked yet — and saying
    /// otherwise is the one answer a ladder must never give.
    static func reached(metric: GoalMetric, measured: GoalTarget,
                        target: GoalTarget) -> Bool {
        switch metric {
        case .liftOneRepMax:
            return atLeast(measured.targetWeightLbs, target.targetWeightLbs)
        case .liftRepsAtLoad:
            return atLeast(measured.targetReps, target.targetReps)
        case .weeklyMuscleSets:
            guard let wanted = target.muscleTargets, !wanted.isEmpty else { return false }
            let got = measured.muscleTargets ?? [:]
            return wanted.allSatisfy { (got[$0.key] ?? 0) >= $0.value }
        case .weeklyDistance:
            return atLeast(measured.distance, target.distance)
        case .trainingDaysPerWeek:
            return atLeast(measured.days, target.days)
        case .sessionsOfTypePerWeek:
            return atLeast(measured.sessions, target.sessions)
        case .lissMinutesPerWeek:
            return atLeast(measured.lissMinutes, target.lissMinutes)
        case .stretchingExercisesPerWeek:
            return atLeast(measured.stretchingExercises, target.stretchingExercises)
        case .cumulativeVolume:
            return atLeast(measured.volumeLbs, target.volumeLbs)
        case .benchmarkTime:
            // A TIME IS BEATEN BY GOING DOWN.
            guard let got = measured.targetSeconds, let wanted = target.targetSeconds
            else { return false }
            return got <= wanted
        case .bodyWeight:
            // DIRECTIONAL, and the direction is the block's own rate: a cut is
            // reached at or below the number, a gain at or above it. A target
            // that names no rate is read as a cut — the same reading
            // `GoalGeneratorMapping.applyPlacement` gives the same preset, so
            // there is one definition of "body composition" and not two.
            guard let got = measured.bodyWeightLbs, let wanted = target.bodyWeightLbs
            else { return false }
            return (target.bodyWeightRatePercent ?? -1) < 0 ? got <= wanted : got >= wanted
        }
    }

    private static func atLeast(_ measured: Decimal?, _ target: Decimal?) -> Bool {
        guard let measured, let target else { return false }
        return measured >= target
    }

    private static func atLeast(_ measured: Int?, _ target: Int?) -> Bool {
        guard let measured, let target else { return false }
        return measured >= target
    }

    private static func atLeast(_ measured: Double?, _ target: Double?) -> Bool {
        guard let measured, let target else { return false }
        return measured >= target
    }

    /// The goal a block gets when nobody named one.
    ///
    /// **INTERIM, AND TASK A13 REPLACES IT.** Spec §5.4: "Existing enrollments
    /// without a goal get a Coach-detected one on first Home load, derived
    /// from the enrollment's `focus` and `baseline`." A13 owns that function;
    /// this one answers the different question task B4 has to answer TODAY —
    /// what does `ProgramBuilder.build(goal:)` receive from the two call sites
    /// Stream C has not reached yet, so that the tree is never in a state that
    /// builds an unconsidered block. The two overload on their parameters, so
    /// A13 lands beside this rather than on top of it.
    ///
    /// **CONSISTENCY, DELIBERATELY, AND IT IS THE ONLY SAFE ANSWER HERE.**
    /// `GoalGeneratorMapping` moves the focus band for eight of the eleven
    /// presets and places cardio for five of them; a placeholder that picked
    /// any of those would silently change what the generator builds for every
    /// athlete who comes through the consult before Stream C lands — a
    /// Maintenance stand-in would drop a strength athlete into the hypertrophy
    /// band, a Body-composition one would buy two cardio days nobody asked
    /// for. `consistency` moves NOTHING (no band override, no placement), and
    /// it is not a fiction either: a block built with no milestone named is
    /// still a commitment to train the days the profile says.
    static func detectedGoal(profile: TrainingProfile) -> BlockGoalDraft {
        BlockGoalDraft(metric: .trainingDaysPerWeek,
                       target: GoalTarget(days: profile.daysPerWeek),
                       byDate: nil,
                       preset: .consistency,
                       // COACH'S reading, not the athlete's: nobody chose this
                       // at a door, so `WeeklyGoalWriteRule` must let the
                       // athlete's own goal win over it.
                       source: .coach)
    }
}

// MARK: - A9: adaptive re-laddering (spec §3.5)
//
// STREAM B REACHED THIS FILE FIRST and the controller's ruling is that Stream A
// starts from B's copy: everything above is B's and stays exactly as it is —
// `weekStartStrings`, `reached` and its three `atLeast` overloads, and the
// interim `detectedGoal(profile:)`. A9's own draft of `reached` was DELETED in
// favour of B's rather than kept beside it; two answers to "did this week reach
// its rung" is precisely the drift the ladder cannot survive, and B's is the one
// `GoalBlockLength.reach` is already written around.
//
// THE TWO LAWS THIS SECTION ENFORCES:
//   1. re-laddering rewrites ONLY rungs whose status is `ahead` or `current`
//      (spec §8), so a missed week and an overridden week stay visible after
//      the ladder moves;
//   2. the milestone and its date are NEVER moved here. When the re-derived
//      ladder can no longer reach the milestone, standing says so (task A12)
//      and Coach PROPOSES through the shipped channel — it does not write.
extension LadderMath {

    /// Mark each rung against the week it describes and what was measured.
    ///
    /// The direction question — is a bigger number better? — is not asked here.
    /// It is `reached(metric:measured:target:)`'s, once, above.
    static func statuses(rungs: [LadderRung], metric: GoalMetric,
                         measuredByWeek: [String: GoalTarget],
                         currentWeekStart: String,
                         overriddenWeeks: Set<String> = []) -> [LadderRung] {
        rungs.map { rung in
            var updated = rung
            // AN OVERRIDE WINS OVER A READING. The athlete's own edit of that
            // week IS the record of it (spec §4), including when the numbers
            // say the rung was met anyway.
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

    /// Re-derive the remaining rungs from `current` — the MEASURED state, not
    /// last week's rung (spec §3.5: "a missed week does not leave a hole to
    /// catch up; the ladder moves").
    ///
    /// Only `ahead` and `current` rungs are replaced. The rungs already met,
    /// missed or overridden are returned exactly as they came in, which is what
    /// makes the ladder page a record of the climb rather than a rolling
    /// forecast that erases its own history. It moves TARGETS and never
    /// statuses; `statuses(…)` is the only thing that may change one.
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
