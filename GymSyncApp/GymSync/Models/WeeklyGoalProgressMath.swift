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

    // MARK: - A4: the dispatcher

    /// One entry point per goal, so `LiveWeeklyGoalRepository` (A12) never
    /// switches on `kind` itself.
    ///
    /// A kind whose math has not landed yet returns the strip's CHROME —
    /// the right kicker and right-hand read with no numbers — rather than a
    /// zeroed progress that would render as "0 of 0, met". Tasks A5-A7 fill
    /// the remaining three arms.
    static func progress(goal: WeeklyGoal,
                         logs: [SetLog],
                         catalog: [UUID: Exercise],
                         sessions: [WorkoutSession],
                         effectiveWeeklyGoal: Int,
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
        case .distance, .sessionsOfType, .lift:
            let daysLeft = WeekMath.daysRemaining(in: now, from: now, calendar: calendar)
            return WeeklyGoalProgress(rightHandRead: daysLeftPhrase(daysLeft),
                                      kicker: kicker(source: goal.source, met: false,
                                                     daysLeft: daysLeft))
        }
    }
}
