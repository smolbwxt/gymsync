import Foundation

// MARK: - WeeklyGoalProgressMath
//
// Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
// -goal-design.md §B. Plan: docs/superpowers/plans/2026-09-06-home-v3
// -production-plan.md, Stream A tasks A3-A7.
//
// Everything here is PURE. No network, no `Date.now`, no `ThemeStore`
// read — every input is passed in, including the clock and the calendar.
// That is what makes the design's agreement law testable: the number the
// goal strip renders and the number the streak tile renders come out of
// this file, and a test can put both under the same fixture.
//
// The boundary this writes is `WeeklyGoalProgress`
// (Models/WeeklyGoalRepository.swift). A view that recomputed any of it
// would be a second opinion about the same week.

enum WeeklyGoalProgressMath {

    // MARK: - A3: the muscle-sets tally

    /// What a week of `set_logs` gave each of the six groups.
    ///
    /// A log counts when it is not a penalty and `completedReps != nil`.
    /// Both halves are load-bearing:
    ///
    /// - **Penalty sets are not training.** They are the burpee tax a late
    ///   arrival owes (`sessions.late_penalty`), logged against the
    ///   exercise so the ledger balances. Crediting them would let being
    ///   late fill a chest target.
    /// - **`completedReps`, never raw `reps`.** `SetLog.completedReps`
    ///   (`SetLog.swift:41`) is this app's failure doctrine in one place: a
    ///   failed triple completed 2 reps and counts, a failed single
    ///   completed nothing and does not. Reading `reps` here would credit
    ///   a missed single as a full set, and reading `isFailed` directly
    ///   would throw away the honest triple. Every e1RM and PR path in the
    ///   app already reads `completedReps`; this is the same rule, so the
    ///   goal strip and the PR sheet cannot disagree about what a set was.
    ///
    /// An `exerciseID` the catalog does not carry is skipped rather than
    /// guessed — the catalog is paged and a stale local copy is a real
    /// state, and a set of an unknown exercise credits an unknown muscle.
    ///
    /// Callers pass the week's logs; this function does no date filtering,
    /// because the one definition of "this week" lives in `WeekMath` and
    /// having two would break the agreement law.
    static func muscleSetCredit(logs: [SetLog],
                                catalog: [UUID: Exercise]) -> [MuscleGroup: Double] {
        var tally: [MuscleGroup: Double] = [:]
        for log in logs {
            guard !log.isPenalty, log.completedReps != nil else { continue }
            guard let exercise = catalog[log.exerciseID] else { continue }
            let perSet = MuscleGroup.credit(primary: exercise.primaryMuscle,
                                            secondaries: exercise.secondaryMuscles)
            for (group, credit) in perSet {
                tally[group, default: 0] += credit
            }
        }
        return tally
    }

    // MARK: - A4: distinct training days

    /// DISTINCT training days this calendar week (solo included — they count
    /// toward streaks since `20260803000005`). Days, not sessions: two
    /// sessions on the same day fill one slot.
    ///
    /// THIS IS `HomeView.daysThisWeek` (:950), lifted here verbatim — same
    /// `completedAt`-non-nil guard, same
    /// `isDate(_:equalTo:toGranularity: .weekOfYear)` week test, same
    /// `startOfDay` bucketing, same `Set(...).count`. Only the two implicit
    /// globals became parameters (`.now` → `now`, `Calendar.current` →
    /// `calendar`) so it is testable.
    ///
    /// Stream B task B1 replaces `HomeView`'s copy with a call to this one.
    /// Until it does there are two copies, which is exactly the drift the
    /// design's agreement law forbids — the streak tile's number and the
    /// goal strip's `days` number must be the same number, and after B1
    /// they are literally the same function.
    static func distinctTrainingDays(sessions: [WorkoutSession],
                                     now: Date = .now,
                                     calendar: Calendar = .current) -> Int {
        let days = sessions.compactMap { session -> Date? in
            guard let completedAt = session.completedAt,
                  calendar.isDate(completedAt, equalTo: now, toGranularity: .weekOfYear)
            else { return nil }
            return calendar.startOfDay(for: completedAt)
        }
        return Set(days).count
    }

    // MARK: - A4: the strip's copy

    /// `3 DAYS LEFT`, and `1 DAY LEFT` singular. The caller owns the caps
    /// nowhere else — this is the one place the phrase is built, so the
    /// strip's right-hand read and the met kicker cannot pluralise
    /// differently.
    static func daysLeftPhrase(_ days: Int) -> String {
        days == 1 ? "1 DAY LEFT" : "\(days) DAYS LEFT"
    }

    /// `THIS WEEK · COACH'S GOAL` / `THIS WEEK · YOUR GOAL`, or
    /// `GOAL MET · {n} DAYS LEFT` once the goal is met — the design's three
    /// kicker strings, built in one place for every kind.
    static func kicker(source: WeeklyGoalSource, met: Bool, daysLeft: Int) -> String {
        if met { return "GOAL MET · \(daysLeftPhrase(daysLeft))" }
        return source == .user ? "THIS WEEK · YOUR GOAL" : "THIS WEEK · COACH'S GOAL"
    }

    // MARK: - A4: muscleSets

    /// The four-chip row.
    ///
    /// Chips are the **four largest** `params.muscleTargets` values, ties
    /// broken by `MuscleGroup.allCases` order — declaration order, not
    /// dictionary order — so the strip cannot reshuffle between two
    /// refreshes of the same week. A `muscleTargets` key that is not one of
    /// the six is dropped rather than rendered as an unknown chip.
    ///
    /// `isNext` is the single largest `target - done` DEFICIT among the
    /// rendered four, not the smallest fraction: 2 sets short of 12 is
    /// closer to done than 4 short of 8, and the chip is a prompt about
    /// what to train next, not a progress ranking. A tie resolves to the
    /// first in render order, which is itself deterministic. No chip is
    /// `isNext` when every rendered chip is met, and a chip whose target is
    /// 0 is never `isNext` (its deficit cannot be positive).
    static func muscleSetsProgress(goal: WeeklyGoal,
                                   logs: [SetLog],
                                   catalog: [UUID: Exercise],
                                   now: Date = .now,
                                   calendar: Calendar = .current) -> WeeklyGoalProgress {
        let tally = muscleSetCredit(logs: logs, catalog: catalog)
        let order = Dictionary(uniqueKeysWithValues:
            MuscleGroup.allCases.enumerated().map { ($0.element, $0.offset) })

        let rendered = (goal.params.muscleTargets ?? [:])
            .compactMap { key, target -> (group: MuscleGroup, target: Int)? in
                guard let group = MuscleGroup(rawValue: key) else { return nil }
                return (group, target)
            }
            .sorted { lhs, rhs in
                if lhs.target != rhs.target { return lhs.target > rhs.target }
                return (order[lhs.group] ?? 0) < (order[rhs.group] ?? 0)
            }
            .prefix(4)

        // First STRICTLY greatest deficit: a later chip tying the best does
        // not displace the earlier one, which is what makes the tie-break
        // "first in render order" rather than "last".
        let deficits = rendered.map { Double($0.target) - (tally[$0.group] ?? 0) }
        var nextIndex: Int?
        var bestDeficit = 0.0
        for (index, deficit) in deficits.enumerated() where deficit > bestDeficit {
            bestDeficit = deficit
            nextIndex = index
        }

        let chips = rendered.enumerated().map { index, entry in
            WeeklyGoalProgress.Chip(name: entry.group.rawValue.uppercased(),
                                    done: tally[entry.group] ?? 0,
                                    target: Double(entry.target),
                                    isNext: index == nextIndex)
        }

        let met = !chips.isEmpty && chips.allSatisfy { $0.done >= $0.target }
        let daysLeft = WeekMath.daysRemaining(in: now, from: now, calendar: calendar)

        return WeeklyGoalProgress(chips: chips,
                                  met: met,
                                  rightHandRead: daysLeftPhrase(daysLeft),
                                  kicker: kicker(source: goal.source, met: met,
                                                 daysLeft: daysLeft))
    }

    // MARK: - A4: days

    /// The week's day chips: distinct training days against the athlete's
    /// weekly goal.
    ///
    /// `target` is `Profile.effectiveWeeklyGoal` — the ANTI-GOALPOST value
    /// (`Profile.swift:88`), where a goal edited mid-week governs from next
    /// week and this week keeps the number it started with. `params.count`
    /// is deliberately NOT read here even though the detector and the editor
    /// both write it: the streak tile renders `effectiveWeeklyGoal`, and the
    /// design's agreement law says the strip and the tile describe the same
    /// week. Reading the mirror instead of the source is precisely how those
    /// two numbers would come to disagree.
    static func daysProgress(goal: WeeklyGoal,
                             sessions: [WorkoutSession],
                             effectiveWeeklyGoal: Int,
                             now: Date = .now,
                             calendar: Calendar = .current) -> WeeklyGoalProgress {
        let done = Double(distinctTrainingDays(sessions: sessions, now: now,
                                               calendar: calendar))
        let target = Double(effectiveWeeklyGoal)
        let met = done >= target
        let daysLeft = WeekMath.daysRemaining(in: now, from: now, calendar: calendar)

        return WeeklyGoalProgress(value: done,
                                  target: target,
                                  met: met,
                                  rightHandRead: daysLeftPhrase(daysLeft),
                                  kicker: kicker(source: goal.source, met: met,
                                                 daysLeft: daysLeft))
    }

    // MARK: - A5: lift

    /// `Decimal` -> `Double` at the one edge where `WeeklyGoalProgress`
    /// forces it. Stored weights are Decimal all the way to here; the
    /// progress type is Double because a view renders it.
    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// Best estimated 1RM for one exercise across the logs given, in
    /// CANONICAL POUNDS, or nil when the exercise has no usable set.
    ///
    /// `completedReps`, not raw `reps` — the same failure doctrine A3
    /// applies, and the same one `StatMath`'s own consumers apply. The
    /// PLAIN `estimatedOneRepMax(weight:reps:)` and not the RPE-aware
    /// variant at `StatMath.swift:141`: that variant's own doc comment
    /// reserves it for SUGGESTION paths ("a record is what you DID, not
    /// what you had in the tank"), and a goal readout is a record.
    ///
    /// Penalty sets are excluded for the same reason A3 excludes them.
    static func bestE1RMPounds(logs: [SetLog], exerciseID: UUID) -> Decimal? {
        var best: Decimal?
        for log in logs where log.exerciseID == exerciseID && !log.isPenalty {
            guard let reps = log.completedReps, let weight = log.weight else { continue }
            let estimate = StatMath.estimatedOneRepMax(weight: weight, reps: reps)
            if best == nil || estimate > best! { best = estimate }
        }
        return best
    }

    /// The e1RM of the EARLIEST usable set for one exercise, by `loggedAt`.
    /// The meter's floor when the enrollment carries no baseline.
    static func earliestE1RMPounds(logs: [SetLog], exerciseID: UUID) -> Decimal? {
        logs
            .filter { $0.exerciseID == exerciseID && !$0.isPenalty
                      && $0.completedReps != nil && $0.weight != nil }
            .min { $0.loggedAt < $1.loggedAt }
            .map { StatMath.estimatedOneRepMax(weight: $0.weight ?? 0,
                                               reps: $0.completedReps ?? 0) }
    }

    /// `3 WEEKS LEFT` to the goal's `by` date, `1 WEEK LEFT` singular, and
    /// `0 WEEKS LEFT` once the date has passed — honest rather than invented
    /// copy for a deadline that is behind you. nil when the goal names no
    /// date, so the caller can fall back to the week's own days-left read.
    static func weeksLeftPhrase(to date: Date?, from now: Date,
                                calendar: Calendar) -> String? {
        guard let date else { return nil }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        let weeks = max(0, Int((Double(days) / 7.0).rounded(.up)))
        return weeks == 1 ? "1 WEEK LEFT" : "\(weeks) WEEKS LEFT"
    }

    /// `205 → 225`: where a focus lift's estimated 1RM stands against its
    /// target.
    ///
    /// `value` and `target` are the READABLE numbers, converted to the
    /// athlete's unit — stored weights are always pounds
    /// (`Models/Units.swift:7-12`) and this is one of the two edges that
    /// converts. Both are emitted unrounded, following `Chip.done`'s own
    /// convention that the view rounds.
    ///
    /// THE METER DOES NOT START AT ZERO. The design runs it from the
    /// block's starting e1RM, because a lifter who opened a block at 205
    /// and is chasing 225 has not "completed 91% of a goal". That floor has
    /// nowhere to live in the frozen `WeeklyGoalProgress`, so it is carried
    /// as the single `Chip`: `done` and `target` are the SPAN above the
    /// floor, which is exactly the meter's geometry, while `value` and
    /// `target` on the progress itself stay the readable pair. Stream C
    /// task C2 renders the meter from that chip; if it renders `value /
    /// target` instead, the meter ignores the block start — reconcile at I1.
    ///
    /// The floor is `ProgramEnrollment.baselineValue(for:)`
    /// (`ProgramEnrollment.swift:74`) when the active block carries one,
    /// else the earliest e1RM inside the block window, else zero.
    ///
    /// When the target is at or below the floor there is no span to fill,
    /// so the chip is a full-or-empty meter (`target: 1`) rather than a
    /// division by zero.
    static func liftProgress(goal: WeeklyGoal,
                             blockLogs: [SetLog],
                             blockStartLbs: Decimal?,
                             unit: WeightUnit,
                             now: Date = .now,
                             calendar: Calendar = .current) -> WeeklyGoalProgress {
        let daysLeft = WeekMath.daysRemaining(in: now, from: now, calendar: calendar)
        let rightHandRead = weeksLeftPhrase(to: goal.params.byDate, from: now,
                                            calendar: calendar)
            ?? daysLeftPhrase(daysLeft)

        // No exercise and no target is a goal that was never finished being
        // set. Render the chrome, not a zero that reads as "met".
        guard let exerciseID = goal.params.exerciseID,
              let targetLbs = goal.params.targetWeightLbs, targetLbs > 0 else {
            return WeeklyGoalProgress(unitLabel: unit.label,
                                      rightHandRead: rightHandRead,
                                      kicker: kicker(source: goal.source, met: false,
                                                     daysLeft: daysLeft))
        }

        let currentLbs = bestE1RMPounds(logs: blockLogs, exerciseID: exerciseID) ?? 0
        let floorLbs = blockStartLbs
            ?? earliestE1RMPounds(logs: blockLogs, exerciseID: exerciseID)
            ?? 0
        let met = currentLbs >= targetLbs

        let spanLbs = targetLbs - floorLbs
        let meter: WeeklyGoalProgress.Chip = spanLbs > 0
            ? .init(name: "E1RM",
                    done: max(0, double(currentLbs - floorLbs)),
                    target: double(spanLbs),
                    isNext: false)
            : .init(name: "E1RM", done: met ? 1 : 0, target: 1, isNext: false)

        return WeeklyGoalProgress(chips: [meter],
                                  value: double(Units.fromPounds(currentLbs, to: unit)),
                                  target: double(Units.fromPounds(targetLbs, to: unit)),
                                  unitLabel: unit.label,
                                  met: met,
                                  rightHandRead: rightHandRead,
                                  kicker: kicker(source: goal.source, met: met,
                                                 daysLeft: daysLeft))
    }

    // MARK: - A6: sessionsOfType

    /// Does one completed session count toward a `sessionsOfType` goal?
    ///
    /// **THIS IS AN INFERENCE, AND IT IS THE HONEST ONE AVAILABLE TODAY.**
    /// There is no `session_type` column and no routine tag anywhere in the
    /// schema — grep-verified. So the type is read off two signals the app
    /// genuinely has:
    ///
    /// 1. **The routine's exercise categories.** `Exercise.category` is one
    ///    of `compound | isolation | cardio | mobility`
    ///    (`20260813000001_import_free_exercise_db.sql`'s mapping comment).
    ///    A session counts for `cardio` or `mobility` when **at least half**
    ///    the routine's exercises carry that category. Half, not one: a
    ///    strength routine that ends with five minutes on the bike is not a
    ///    cardio session, and a single tagged row would make it one.
    /// 2. **The routine's name**, case-insensitively, for `hiit` and
    ///    `class` — which have no category and can be named nothing else.
    ///    The name check applies to every type as a fallback, because a
    ///    routine called "Sunday Mobility" with untagged stretches is
    ///    obviously mobility to its author.
    /// 3. **An Apple Health workout of the matching type on the same day**
    ///    outranks both (task A7's query supplies it): a real HealthKit
    ///    workout is recorded fact, where the two above are guesses about a
    ///    routine's intent.
    ///
    /// **Its limitation, stated plainly:** a routine whose exercises are
    /// mis-categorised in the catalog, or whose name says nothing, will not
    /// count no matter what the athlete actually did. A `session_type`
    /// column is the real fix and is out of this plan's scope (the plan's
    /// own "What this plan does not decide" #4).
    ///
    /// Returns a Bool per session, so a session with TWO matching signals is
    /// still one session — the caller counts sessions, not signals.
    static func sessionCounts(towardType type: String,
                              session: WorkoutSession,
                              routines: [UUID: Routine],
                              routineExercises: [UUID: [RoutineExercise]],
                              catalog: [UUID: Exercise],
                              healthWorkoutTypesByDay: [Date: Set<String>] = [:],
                              calendar: Calendar = .current) -> Bool {
        guard let completedAt = session.completedAt else { return false }
        let wanted = type.lowercased()

        // 3 — recorded fact beats inference.
        let day = calendar.startOfDay(for: completedAt)
        if healthWorkoutTypesByDay[day]?.contains(wanted) == true { return true }

        guard let routineID = session.routineID else { return false }

        // 2 — the name, for hiit/class and as everyone's fallback.
        if let name = routines[routineID]?.name.lowercased(), name.contains(wanted) {
            return true
        }

        // 1 — the category threshold, for the two types that have one.
        guard wanted == "cardio" || wanted == "mobility" else { return false }
        let categories = (routineExercises[routineID] ?? [])
            .compactMap { catalog[$0.exerciseID]?.category.lowercased() }
        guard !categories.isEmpty else { return false }
        let matching = categories.filter { $0 == wanted }.count
        return Double(matching) >= Double(categories.count) / 2.0
    }

    /// `2 of 3 HIIT` — n dots, filled as done.
    ///
    /// Sessions are counted, not signals: `sessionCounts` answers once per
    /// session, so a routine named "HIIT" whose exercises are also all
    /// cardio still moves the number by one.
    static func sessionsOfTypeProgress(goal: WeeklyGoal,
                                       sessions: [WorkoutSession],
                                       routines: [UUID: Routine],
                                       routineExercises: [UUID: [RoutineExercise]],
                                       catalog: [UUID: Exercise],
                                       healthWorkoutTypesByDay: [Date: Set<String>] = [:],
                                       now: Date = .now,
                                       calendar: Calendar = .current) -> WeeklyGoalProgress {
        let daysLeft = WeekMath.daysRemaining(in: now, from: now, calendar: calendar)
        let type = goal.params.sessionType ?? ""
        let target = Double(goal.params.count ?? 0)

        let done = Double(sessions.filter { session in
            guard let completedAt = session.completedAt,
                  calendar.isDate(completedAt, equalTo: now, toGranularity: .weekOfYear)
            else { return false }
            return sessionCounts(towardType: type, session: session,
                                 routines: routines,
                                 routineExercises: routineExercises,
                                 catalog: catalog,
                                 healthWorkoutTypesByDay: healthWorkoutTypesByDay,
                                 calendar: calendar)
        }.count)

        let met = target > 0 && done >= target

        return WeeklyGoalProgress(value: done,
                                  target: target,
                                  met: met,
                                  rightHandRead: daysLeftPhrase(daysLeft),
                                  kicker: kicker(source: goal.source, met: met,
                                                 daysLeft: daysLeft))
    }

    // MARK: - A7: distance

    /// Metres in one mile, exactly. The international mile is defined as
    /// 1609.344 m, so this is a definition rather than a measurement.
    static let metresPerMile = 1609.344

    /// `mi` with pounds, `km` with kilograms — owner answer 2. The distance
    /// unit is not a separate setting; it follows the one unit switch the
    /// app already has.
    static func distanceUnitLabel(_ unit: WeightUnit) -> String {
        unit == .lbs ? "mi" : "km"
    }

    /// Metres -> the athlete's distance unit. HealthKit answers in metres
    /// and `params.distanceTarget` is already stored in the athlete's own
    /// unit, so this is the one conversion between them.
    static func distanceValue(metres: Double, unit: WeightUnit) -> Double {
        unit == .lbs ? metres / metresPerMile : metres / 1000
    }

    /// `9.4 / 15 mi`.
    ///
    /// Pure: the caller does the HealthKit read (`HealthKitBridge
    /// .distanceMeters(activity:from:to:)`) and passes metres in. That
    /// keeps the arithmetic testable with no store, and it means the
    /// DENIED path and the NO-DATA path are the same path — HealthKit never
    /// discloses a read denial, so 0 metres is the only honest answer to
    /// both, and the strip renders `0 / 15 mi` rather than an error.
    static func distanceProgress(goal: WeeklyGoal,
                                 metres: Double,
                                 unit: WeightUnit,
                                 now: Date = .now,
                                 calendar: Calendar = .current) -> WeeklyGoalProgress {
        let daysLeft = WeekMath.daysRemaining(in: now, from: now, calendar: calendar)
        let value = distanceValue(metres: max(0, metres), unit: unit)
        let target = goal.params.distanceTarget ?? 0
        let met = target > 0 && value >= target

        return WeeklyGoalProgress(value: value,
                                  target: target,
                                  unitLabel: distanceUnitLabel(unit),
                                  met: met,
                                  rightHandRead: daysLeftPhrase(daysLeft),
                                  kicker: kicker(source: goal.source, met: met,
                                                 daysLeft: daysLeft))
    }

    // MARK: - A4: the dispatcher

    /// One entry point per goal, so `LiveWeeklyGoalRepository` (A12) never
    /// switches on `kind` itself.
    ///
    /// All five kinds route from here.
    ///
    /// `logs` are THIS WEEK's; `blockLogs` are the active block's, which the
    /// `lift` kind needs because an e1RM is a block-long fact rather than a
    /// weekly one. `distanceMetres` is what the caller's HealthKit read
    /// returned for the week. `unit` is passed rather than read from
    /// `ThemeStore.shared` so this file stays pure; its `.lbs` default is
    /// only ever reachable for the kinds whose `unitLabel` is `""` anyway.
    static func progress(goal: WeeklyGoal,
                         logs: [SetLog],
                         catalog: [UUID: Exercise],
                         sessions: [WorkoutSession],
                         effectiveWeeklyGoal: Int,
                         blockLogs: [SetLog] = [],
                         blockStartLbs: Decimal? = nil,
                         unit: WeightUnit = .lbs,
                         routines: [UUID: Routine] = [:],
                         routineExercises: [UUID: [RoutineExercise]] = [:],
                         healthWorkoutTypesByDay: [Date: Set<String>] = [:],
                         distanceMetres: Double = 0,
                         now: Date = .now,
                         calendar: Calendar = .current) -> WeeklyGoalProgress {
        switch goal.kind {
        case .muscleSets:
            return muscleSetsProgress(goal: goal, logs: logs, catalog: catalog,
                                      now: now, calendar: calendar)
        case .days:
            return daysProgress(goal: goal, sessions: sessions,
                                effectiveWeeklyGoal: effectiveWeeklyGoal,
                                now: now, calendar: calendar)
        case .lift:
            return liftProgress(goal: goal, blockLogs: blockLogs,
                                blockStartLbs: blockStartLbs, unit: unit,
                                now: now, calendar: calendar)
        case .sessionsOfType:
            return sessionsOfTypeProgress(
                goal: goal, sessions: sessions, routines: routines,
                routineExercises: routineExercises, catalog: catalog,
                healthWorkoutTypesByDay: healthWorkoutTypesByDay,
                now: now, calendar: calendar)
        case .distance:
            return distanceProgress(goal: goal, metres: distanceMetres, unit: unit,
                                    now: now, calendar: calendar)
        }
    }
}
