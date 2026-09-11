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
                               weeks: mutable.count,
                               constraints: windowed(constraints, over: mutable))
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

    /// `constraints` translated from BLOCK-RELATIVE week indices to the window
    /// the rule is about to iterate (fix round 1, finding F2).
    ///
    /// THIS IS THE DELOAD LAW'S ONE SHARP EDGE. `LadderReadout.constraints`
    /// builds `deloadWeeks` by enumerating the whole template, so a
    /// `march-to-1rm` deload is index 4 of eight. `reLadder` then asks the rule
    /// for only the rungs that are still `ahead` or `current`, and every rule
    /// tests `deloadWeeks.contains(index)` with `index` running `0..<weeks` —
    /// local to that window. Handed the absolute set unchanged, the light week
    /// drifted one week later on every refresh (after week 1 closed, local 4 was
    /// absolute 5; after week 2, absolute 6) and then vanished entirely once
    /// the block index fell off the front. Silently, because nothing rebuilt the
    /// ladder from the block afterwards to notice.
    ///
    /// Translating puts every constraint back on the week the block actually
    /// marked, and constraints outside the window simply do not appear: a deload
    /// the athlete has already trained through is not a deload still ahead of
    /// them.
    ///
    /// TRANSLATED BY POSITION, not by subtracting the first index, and the
    /// difference only shows on a ladder with a HOLE in it. `mutable` is
    /// normally contiguous — past weeks are met/missed, then current, then
    /// ahead — but an athlete who sets their own goal for a FUTURE week makes
    /// that rung `overridden`, and it drops out of the middle. Subtracting a
    /// single offset would then shift every rung after the hole; asking each
    /// mutable rung for its own position cannot. For a contiguous window the two
    /// are the same arithmetic.
    ///
    /// THERE IS NO SHORT-CIRCUIT FOR A WINDOW THAT STARTS AT WEEK 0, and there
    /// used to be (round 2, item O1). It looked safe — translating a full-block
    /// window is the identity — but that is only true when the window is also
    /// CONTIGUOUS. A ladder whose week 1 is overridden while week 0 is still
    /// current starts at 0 and has a hole, so the identity is wrong and the
    /// guard was skipping the very correction the hole needs.
    ///
    /// WHAT THIS DOES NOT FIX, and it is worth knowing: a rule with its OWN
    /// cadence — `PercentRampLadderRule`'s `downWeekEvery` — still counts from
    /// the start of the window, so an endurance down-week re-phases on a
    /// re-ladder. Carrying a phase offset would mean widening `LadderConstraints`,
    /// which is frozen Task 0 surface; it is recorded for the controller rather
    /// than invented here.
    private static func windowed(_ constraints: LadderConstraints,
                                 over mutable: [LadderRung]) -> LadderConstraints {
        var local = constraints
        // Where local index 0 sits in the BLOCK, so a rule with a cadence of its
        // own can anchor it there rather than to this window (O2).
        local.phaseOriginWeekIndex = mutable.first?.weekIndex ?? 0
        local.deloadWeeks = Set(mutable.enumerated().compactMap { position, rung in
            constraints.deloadWeeks.contains(rung.weekIndex) ? position : nil
        })
        local.taperWeeks = Set(mutable.enumerated().compactMap { position, rung in
            constraints.taperWeeks.contains(rung.weekIndex) ? position : nil
        })
        return local
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
    ///
    /// `previousRung` exists for ONE metric. `cumulativeVolume`'s rungs are
    /// tonnage-to-date (see `CumulativeLadderRule`), and the strip asks for a
    /// WEEK — so the week's own share is this rung minus the one before it.
    /// Defaulted, because every other metric's rung already is the week.
    static func weeklyGoal(from rung: LadderRung, goal: BlockGoal,
                           userID: UUID, now: Date,
                           previousRung: LadderRung? = nil) -> WeeklyGoal? {
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
            // THE LADDER COUNTS A BLOCK; THE STRIP ASKS FOR A WEEK. The rung is
            // the tonnage-to-date this week should end on, so what the athlete
            // owes THIS week is the step up from the week before it. Without
            // the subtraction a week-six rung would ask for the whole block's
            // total in seven days.
            let banked = previousRung?.target.volumeLbs ?? 0
            params.volumeLbs = rung.target.volumeLbs.map { Swift.max(0, $0 - banked) }
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

// MARK: - A12: the ladder page's model (spec §6)
//
// **THE ONLY PLACE THE LADDER'S WORDS ARE CHOSEN.** The page, the schedule card
// and Coach's line all render from `LadderPageModel`, so one rung cannot be
// spelled three ways. A view that formatted a `GoalTarget` itself would be a
// second opinion about what the week asks for.
//
// PURE, and it takes `now` and the `calendar` for the reason
// `WeeklyGoalProgressMath` does: a page whose week number came from `Date.now`
// could not be tested and could not be captured.
extension LadderMath {

    /// Everything the ladder page renders, already worded.
    ///
    /// `reachesMilestone` is `reached(metric:measured:target:)` applied to the
    /// LAST RUNG against the MILESTONE. When it is false the coach line becomes
    /// the proposal — and NOTHING IS WRITTEN. Spec §3.5's whole point is that
    /// Coach proposes the date move and the athlete accepts it.
    static func page(goal: BlockGoal, ladder: Ladder, liftName: String,
                     rungSets: Int, notesByWeek: [Int: String],
                     deloadWeeks: Set<Int> = [], unit: WeightUnit,
                     now: Date, calendar: Calendar) -> LadderPageModel {
        var model = LadderPageModel()
        model.source = goal.source
        model.weekCount = ladder.rungs.count

        model.rows = ladder.rungs.enumerated().map { index, rung in
            let isDeload = deloadWeeks.contains(rung.weekIndex)
            // The rung BEFORE this one, for the one metric whose rungs are
            // cumulative: the row says where the block stands, and its
            // implication says what this week adds.
            let previous = index > 0 ? ladder.rungs[index - 1].target : nil
            let (text, implication) = rungText(metric: goal.metric, target: rung.target,
                                               previous: previous,
                                               sets: rungSets, unit: unit)
            return LadderRow(
                weekNumber: rung.weekIndex + 1,
                weekStartString: rung.weekStartString,
                targetText: text,
                // A DELOAD ROW CARRIES NO IMPLICATION. "≈ 197 e1RM" under a
                // week the block deliberately made light reads as a setback;
                // the number is true and the sentence it forms is not.
                implication: isDeload ? nil : implication,
                status: rung.status,
                isDeload: isDeload,
                note: notesByWeek[rung.weekIndex])
        }

        // The week the athlete is ON is the one rung marked `current`. Falling
        // back to `now`'s own week key covers a ladder that has not been
        // re-laddered yet; falling back to 1 covers a block that has not started.
        let currentWeekKey = WeekMath.weekStartString(now, calendar: calendar)
        let currentRung = ladder.rungs.first(where: { $0.status == .current })
            ?? ladder.rungs.first(where: { $0.weekStartString == currentWeekKey })
        model.weekNumber = currentRung.map { $0.weekIndex + 1 } ?? 1

        let dated = goal.byDate
        model.dateLine = dated.map { longDate($0, calendar: calendar) } ?? ""
        model.headline = headline(goal: goal, liftName: liftName, unit: unit,
                                  calendar: calendar)

        // A GOAL WITH NO DATE CANNOT FALL SHORT OF ONE. `reachesMilestone` asks
        // whether the ladder still arrives BY THE DATE (spec §6), so a
        // held-for-the-block goal is true by construction rather than by
        // measuring a milestone it does not have.
        if dated == nil {
            model.reachesMilestone = true
            model.coachLine = "Held for the block."
            return model
        }

        let last = ladder.rungs.last
        model.reachesMilestone = last.map {
            reached(metric: goal.metric, measured: $0.target, target: goal.target)
        } ?? false
        if model.reachesMilestone {
            model.coachLine = "On track"
        } else {
            // NAMES THE NUMBER. "This ladder reaches 218 — move the date?" is
            // the spec's own wording, and the point of it is that the ladder
            // never lies about the gap: it says where it actually arrives.
            let reach = last.map { bareNumber(metric: goal.metric, target: $0.target,
                                              unit: unit) } ?? ""
            model.coachLine = reach.isEmpty
                ? "This ladder does not reach the milestone — move the date?"
                : "This ladder reaches \(reach) — move the date?"
        }
        return model
    }

    // MARK: - Wording

    /// The milestone as the headline — spec §6's table, verbatim where it
    /// gives the copy.
    private static func headline(goal: BlockGoal, liftName: String,
                                 unit: WeightUnit, calendar: Calendar) -> String {
        // HELD FOR THE BLOCK gets its own two sentences, because "12 chest sets
        // a week by Oct 18" would put a deadline on a goal that has none.
        //
        // The preset is UNWRAPPED FIRST rather than switched over as an
        // optional. `HomeWeeklyGoalStrip.unitLabel` spells `.some(...)` for the
        // same reason; an `if let` reads better here because only two of the
        // eleven presets have an answer.
        if goal.byDate == nil, let preset = goal.preset {
            switch preset {
            case .maintenance: return "Hold the recommended volumes"
            case .recovery:    return "A recovery block"
            default: break
            }
        }
        let subject = headlineSubject(goal: goal, liftName: liftName, unit: unit)
        guard let byDate = goal.byDate else { return subject }
        return "\(subject) by \(shortDate(byDate, calendar: calendar))"
    }

    private static func headlineSubject(goal: BlockGoal, liftName: String,
                                        unit: WeightUnit) -> String {
        let target = goal.target
        switch goal.metric {
        case .liftOneRepMax:
            let load = target.targetWeightLbs
                .map { Units.wholeNumber(pounds: $0, unit: unit) } ?? ""
            return [liftName, load].filter { !$0.isEmpty }.joined(separator: " ")
        case .liftRepsAtLoad:
            let load = (target.loadLbs ?? target.targetWeightLbs)
                .map { Units.wholeNumber(pounds: $0, unit: unit) } ?? ""
            let reps = target.targetReps.map { "\($0)" } ?? ""
            let at = [reps, load].filter { !$0.isEmpty }.joined(separator: " at ")
            return [liftName, at].filter { !$0.isEmpty }.joined(separator: " ")
        case .weeklyMuscleSets:
            guard let biggest = largestGroup(target.muscleTargets) else {
                return "Weekly volume"
            }
            return "\(biggest.sets) \(biggest.group) sets a week"
        case .weeklyDistance:
            let label = WeeklyGoalProgressMath.distanceUnitLabel(unit)
            let value = target.distance.map { WeeklyGoalProgressMath.groupedNumber($0) } ?? ""
            let activity = (target.activity ?? "").isEmpty ? "" : " \(target.activity ?? "")"
            return "\(value) \(label) a week\(activity)".trimmingCharacters(in: .whitespaces)
        case .trainingDaysPerWeek:
            let days = target.days ?? 0
            return "\(days) \(days == 1 ? "day" : "days") a week"
        case .sessionsOfTypePerWeek:
            let count = target.sessions ?? 0
            let type = (target.sessionType ?? "").uppercased()
            return "\(count) \(type) a week".replacingOccurrences(of: "  ", with: " ")
        case .lissMinutesPerWeek:
            return "\(target.lissMinutes ?? 0) LISS min a week"
        case .stretchingExercisesPerWeek:
            let count = target.stretchingExercises ?? 0
            return "\(count) \(count == 1 ? "stretch" : "stretches") a week"
        case .bodyWeight:
            return target.bodyWeightLbs
                .map { Units.formatBodyWeight(pounds: $0, unit: unit) } ?? "Body weight"
        case .cumulativeVolume:
            let value = target.volumeLbs.map {
                WeeklyGoalProgressMath.groupedNumber(Units.fromPounds($0, to: unit))
            } ?? ""
            return "\(value) \(unit.label) moved"
        case .benchmarkTime:
            return target.targetSeconds
                .map { WeeklyGoalProgressMath.clock(Double($0)) } ?? "A benchmark"
        }
    }

    /// One rung, worded — and its implication when the number implies something
    /// the text does not say.
    private static func rungText(metric: GoalMetric, target: GoalTarget,
                                 previous: GoalTarget? = nil,
                                 sets: Int,
                                 unit: WeightUnit) -> (String, String?) {
        switch metric {
        case .liftOneRepMax, .liftRepsAtLoad:
            // ONE FUNCTION, on both surfaces — `LadderReadout.strengthRungText`
            // is what the schedule card prints too.
            let spelled = LadderReadout.strengthRungText(target, sets: sets, unit: unit)
            return (spelled.text, spelled.implication)
        case .weeklyMuscleSets:
            let groups = (target.muscleTargets ?? [:])
                .sorted { lhs, rhs in
                    lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
                }
                .map { "\($0.value) \($0.key)" }
            return (groups.isEmpty ? "—" : groups.joined(separator: " · "), nil)
        case .weeklyDistance:
            guard let distance = target.distance else { return ("—", nil) }
            return ("\(WeeklyGoalProgressMath.groupedNumber(distance)) "
                    + WeeklyGoalProgressMath.distanceUnitLabel(unit), nil)
        case .trainingDaysPerWeek:
            guard let days = target.days else { return ("—", nil) }
            return ("\(days) \(days == 1 ? "day" : "days")", nil)
        case .sessionsOfTypePerWeek:
            guard let count = target.sessions else { return ("—", nil) }
            return ("\(count) \((target.sessionType ?? "").uppercased())"
                        .trimmingCharacters(in: .whitespaces), nil)
        case .lissMinutesPerWeek, .stretchingExercisesPerWeek:
            // ONE RUNG, TWO NUMBERS — Recovery is one goal with two metrics
            // (spec §2.3) and the row says both, in the order `LadderRow`'s own
            // doc comment gives.
            var parts: [String] = []
            if let minutes = target.lissMinutes { parts.append("\(minutes) LISS min") }
            if let count = target.stretchingExercises {
                parts.append("\(count) \(count == 1 ? "stretch" : "stretches")")
            }
            return (parts.isEmpty ? "—" : parts.joined(separator: " · "), nil)
        case .bodyWeight:
            guard let pounds = target.bodyWeightLbs else { return ("—", nil) }
            let rate = target.bodyWeightRatePercent.map { value -> String in
                // `%@` with a Swift String bridges on Darwin but does not need
                // to: the sign is interpolation and only the number is formatted.
                let sign = value < 0 ? "" : "+"
                return "\(sign)\(String(format: "%.2f", value)) %/wk"
            }
            return (Units.formatBodyWeight(pounds: pounds, unit: unit), rate)
        case .cumulativeVolume:
            guard let pounds = target.volumeLbs else { return ("—", nil) }
            // THE ROW IS THE RUNNING TOTAL and the implication is the week's own
            // share, because a cumulative ladder read as a list of weekly
            // numbers looks like it is asking for the block eight times.
            let banked = previous?.volumeLbs ?? 0
            let thisWeek = Swift.max(0, pounds - banked)
            let total = "\(WeeklyGoalProgressMath.groupedNumber(Units.fromPounds(pounds, to: unit)))"
                + " \(unit.label)"
            let share = "+\(WeeklyGoalProgressMath.groupedNumber(Units.fromPounds(thisWeek, to: unit)))"
                + " this week"
            return (total, thisWeek > 0 ? share : nil)
        case .benchmarkTime:
            guard let seconds = target.targetSeconds else { return ("—", nil) }
            return (WeeklyGoalProgressMath.clock(Double(seconds)), nil)
        }
    }

    /// The bare number a coach line names — "218", "12 mi", "46:40".
    private static func bareNumber(metric: GoalMetric, target: GoalTarget,
                                   unit: WeightUnit) -> String {
        switch metric {
        case .liftOneRepMax, .liftRepsAtLoad:
            return (target.targetWeightLbs ?? target.loadLbs)
                .map { Units.wholeNumber(pounds: $0, unit: unit) } ?? ""
        case .weeklyMuscleSets:
            return largestGroup(target.muscleTargets).map { "\($0.sets) \($0.group)" } ?? ""
        case .weeklyDistance:
            return target.distance.map {
                "\(WeeklyGoalProgressMath.groupedNumber($0)) "
                    + WeeklyGoalProgressMath.distanceUnitLabel(unit)
            } ?? ""
        case .trainingDaysPerWeek:
            return target.days.map { "\($0)" } ?? ""
        case .sessionsOfTypePerWeek:
            return target.sessions.map { "\($0)" } ?? ""
        case .lissMinutesPerWeek:
            return target.lissMinutes.map { "\($0) min" } ?? ""
        case .stretchingExercisesPerWeek:
            return target.stretchingExercises.map { "\($0)" } ?? ""
        case .bodyWeight:
            return target.bodyWeightLbs
                .map { Units.formatBodyWeight(pounds: $0, unit: unit) } ?? ""
        case .cumulativeVolume:
            return target.volumeLbs.map {
                WeeklyGoalProgressMath.groupedNumber(Units.fromPounds($0, to: unit))
            } ?? ""
        case .benchmarkTime:
            return target.targetSeconds.map { WeeklyGoalProgressMath.clock(Double($0)) } ?? ""
        }
    }

    /// The group a muscle headline names: the largest target, ties broken by
    /// `MuscleGroup.allCases` order so the headline cannot reshuffle between
    /// two renders of the same goal.
    private static func largestGroup(_ targets: [String: Int]?)
        -> (group: String, sets: Int)? {
        let order = Dictionary(uniqueKeysWithValues:
            MuscleGroup.allCases.enumerated().map { ($0.element.rawValue, $0.offset) })
        return (targets ?? [:])
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return (order[lhs.key] ?? .max) < (order[rhs.key] ?? .max)
            }
            .first
            .map { (group: $0.key, sets: $0.value) }
    }

    // MARK: - Dates
    //
    // **`en_US_POSIX`, DELIBERATELY.** Every other string this file produces is
    // an English literal — "On track", "Held for the block.", "a week" — so a
    // locale-aware month name would be the single translated word on an
    // otherwise English page. When this app is localised the whole page moves
    // together; until then one locale for one page is the honest choice, and it
    // is also what makes "Bench 225 by Oct 18" assertable in a test.

    /// "Oct 18" — the headline's date.
    private static func shortDate(_ date: Date, calendar: Calendar) -> String {
        formatter("MMM d", calendar: calendar).string(from: date)
    }

    /// "Sunday 18 October" — the page's own date line.
    private static func longDate(_ date: Date, calendar: Calendar) -> String {
        formatter("EEEE d MMMM", calendar: calendar).string(from: date)
    }

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: - A13: blocks that predate goals (spec §5.4)

extension LadderMath {

    /// The goal a block that predates goals gets, derived from the
    /// enrollment's OWN evidence and nothing else.
    ///
    /// **THIS IS A13'S FUNCTION AND IT LANDS BESIDE B4'S `detectedGoal(profile:)`
    /// RATHER THAN ON TOP OF IT.** The two answer different questions and
    /// overload on their parameters, exactly as that one's doc comment says:
    /// B4's is what `ProgramBuilder.build(goal:)` receives when nothing was
    /// chosen at a door, and this one is what an ALREADY-BUILT block gets on
    /// first Home load.
    ///
    /// `source = .coach`, which is what makes the athlete's later edit on the
    /// ladder page an override Coach must respect (owner decision 8), and
    /// `preset` is nil because this goal was not chosen at a door.
    ///
    /// The derivation, in the order it is tried:
    ///   * `focus.exerciseIDs.first` WITH a `baseline` → `liftOneRepMax` at
    ///     `WeeklyGoalDetector.liftTarget` — the same baseline + 5 %, rounded in
    ///     the athlete's own unit, that the weekly detector takes. CALLED, not
    ///     re-derived: two functions for "next milestone on a lift" is how the
    ///     ladder and the strip come to disagree by 5 lb.
    ///   * `focus.muscleGroup` → `weeklyMuscleSets` for that group, from
    ///     `volume_targets` when the titration has a row for it and from the
    ///     block's own prescribed sets otherwise.
    ///   * anything else → `trainingDaysPerWeek` at `Profile.effectiveWeeklyGoal`
    ///     — the same NEVER-RETURNS-NIL floor `WeeklyGoalDetector`'s rule 3 is,
    ///     for the same reason: a block with no goal is the state this function
    ///     exists to end.
    ///
    /// `prescribedMuscleSets` is defaulted so the pure call reads exactly as the
    /// plan writes it. A muscle focus with NEITHER a titration row NOR a
    /// prescription falls through to the days floor rather than naming a number
    /// nobody set — the ladder would otherwise open on a target invented here.
    static func detectedGoal(enrollment: ProgramEnrollment,
                             volumeTargets: [VolumeTarget],
                             effectiveWeeklyGoal: Int,
                             prescribedMuscleSets: [String: Int] = [:],
                             unit: WeightUnit,
                             now: Date,
                             calendar: Calendar) -> BlockGoalDraft {
        let byDate = WeeklyGoalDetector.blockEnd(enrollment, calendar: calendar)

        if let exerciseID = enrollment.focus.exerciseIDs?.first,
           let baseline = enrollment.baselineValue(for: exerciseID), baseline > 0 {
            let target = WeeklyGoalDetector.liftTarget(fromBaselineLbs: baseline,
                                                       unit: unit)
            return BlockGoalDraft(
                metric: .liftOneRepMax,
                target: GoalTarget(exerciseID: exerciseID, targetWeightLbs: target),
                byDate: byDate, preset: nil, source: .coach)
        }

        if let muscle = enrollment.focus.muscleGroup,
           let group = MuscleGroup.group(muscle) {
            let titrated = WeeklyGoalDetector.titratedTargets(volumeTargets)
            let sets = titrated[group] ?? prescribedMuscleSets[group.rawValue]
            if let sets, sets > 0 {
                return BlockGoalDraft(
                    metric: .weeklyMuscleSets,
                    target: GoalTarget(muscleTargets: [group.rawValue: sets]),
                    byDate: byDate, preset: nil, source: .coach)
            }
        }

        return BlockGoalDraft(metric: .trainingDaysPerWeek,
                              target: GoalTarget(days: max(1, effectiveWeeklyGoal)),
                              byDate: byDate, preset: nil, source: .coach)
    }
}
