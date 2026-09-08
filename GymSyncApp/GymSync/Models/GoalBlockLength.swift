import Foundation

// MARK: - GoalBlockLength
//
// Spec §5.3: the goal sets "the block length from the date". PURE, so the
// answer is a test rather than a clock.
enum GoalBlockLength {

    /// The generator's own limits. Below four weeks a block has no wave to
    /// speak of (`ProgramGenerator.swift`'s wave: flat under 8, deload at the
    /// ¾ mark from 8), and `program_enrollments.weeks` is CHECKed BETWEEN 1
    /// AND 52 (`20260728000009_program_enrollments.sql:42`).
    static let minimumWeeks = 4
    static let maximumWeeks = 52
    /// What a block is when the goal names no date — Maintenance, Recovery and
    /// Consistency are "held for the block" (spec §2.1), and eight weeks is
    /// what `ProgramBuilder.build` has always defaulted to
    /// (`ProgramBuilder.swift`'s `answers?.durationWeeks ?? 8`).
    static let defaultWeeks = 8

    /// Whole weeks from `now` to `byDate`, clamped. A date inside four weeks
    /// still gets a four-week block: the ladder then says the milestone is out
    /// of reach (task B5), which is honest, where refusing to build is not.
    static func weeks(byDate: Date?, from now: Date = .now,
                      calendar: Calendar = .current) -> Int {
        guard let byDate else { return defaultWeeks }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: byDate)).day ?? 0
        let raw = Int((Double(days) / 7.0).rounded(.up))
        return min(maximumWeeks, max(minimumWeeks, raw))
    }
}

// MARK: - "Cannot reach by the date"
//
// Spec §3.2, the copy verbatim: "225 by Oct 18 needs more than this block can
// safely give; Nov 15 is the date I can build to" — and, in the same
// paragraph: **"The ladder never lies about the gap."**
extension GoalBlockLength {

    /// Can the block's own prescribed loading reach `target` by `byDate`?
    ///
    /// Answered from the LADDER, not from a second model of progress: the last
    /// rung is what the block prescribes for the final week, and if that falls
    /// short of the milestone then the block falls short of the milestone.
    /// Anything else would be a third opinion about the same eight weeks.
    struct Reach: Equatable, Sendable {
        let reaches: Bool
        /// What the block DOES get to — 218, in the spec's example.
        let projected: GoalTarget
        /// The date the block COULD build to, when it cannot make the one
        /// asked for. nil when it can.
        let achievableDate: Date?
    }

    static func reach(metric: GoalMetric, rungs: [GoalTarget], milestone: GoalTarget,
                      byDate: Date?, weeklyGain: Double?, from now: Date = .now,
                      calendar: Calendar = .current) -> Reach {
        guard let last = rungs.last else {
            return Reach(reaches: false, projected: milestone, achievableDate: nil)
        }
        if LadderMath.reached(metric: metric, measured: last, target: milestone) {
            return Reach(reaches: true, projected: last, achievableDate: nil)
        }
        // The date the block COULD build to: how many more weeks of the same
        // weekly gain the remaining distance needs. nil `weeklyGain` (a metric
        // with no linear gain, or a ladder that is flat) means the honest
        // answer is "not on this ladder", with no invented date.
        var achievable: Date?
        if let weeklyGain, weeklyGain > 0,
           let short = shortfall(metric: metric, last: last, milestone: milestone),
           short > 0 {
            let extraWeeks = Int((short / weeklyGain).rounded(.up))
            let endOfBlock = calendar.date(byAdding: .day,
                                           value: rungs.count * 7, to: now) ?? now
            achievable = calendar.date(byAdding: .day, value: extraWeeks * 7,
                                       to: byDate ?? endOfBlock)
        }
        return Reach(reaches: false, projected: last, achievableDate: achievable)
    }

    /// Coach's sentence at the door, spec §3.2 verbatim in shape:
    /// "225 by Oct 18 needs more than this block can safely give; Nov 15 is
    /// the date I can build to."
    ///
    /// Without an achievable date the sentence stops after the first clause
    /// rather than inventing a second — the design's "never lies about the
    /// gap" cuts both ways.
    static func reachSentence(milestoneText: String, byDate: Date?, reach: Reach,
                              calendar: Calendar = .current) -> String? {
        guard !reach.reaches else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        // THE CALENDAR'S ZONE, NOT THE SYSTEM'S. `DateFormatter.timeZone` does
        // not follow the calendar it is given, and a milestone stored at
        // midnight would then print the day before in every Americas timezone —
        // the exact defect the Task 0 re-review found in the stub's fixture
        // dates. One line here, and the sentence names the day the arithmetic
        // used.
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        let asked = byDate.map { " by \(formatter.string(from: $0))" } ?? ""
        let head = "\(milestoneText)\(asked) needs more than this block can safely give"
        guard let achievable = reach.achievableDate else { return head + "." }
        return head + "; \(formatter.string(from: achievable)) is the date I can build to."
    }

    /// How far the last rung still is from the milestone, in the metric's own
    /// unit — pounds for a lift, reps for rep strength, miles or kilometres for
    /// distance, seconds for a benchmark, pounds for body weight.
    ///
    /// nil for `weeklyMuscleSets`, where "distance to the milestone" is not a
    /// single number: six groups are six gaps, and one date computed over them
    /// would be a guess wearing arithmetic's clothes.
    private static func shortfall(metric: GoalMetric, last: GoalTarget,
                                  milestone: GoalTarget) -> Double? {
        switch metric {
        case .liftOneRepMax:
            return gap(milestone.targetWeightLbs, last.targetWeightLbs)
        case .liftRepsAtLoad:
            return gap(milestone.targetReps, last.targetReps)
        case .weeklyDistance:
            return gap(milestone.distance, last.distance)
        case .trainingDaysPerWeek:
            return gap(milestone.days, last.days)
        case .sessionsOfTypePerWeek:
            return gap(milestone.sessions, last.sessions)
        case .lissMinutesPerWeek:
            return gap(milestone.lissMinutes, last.lissMinutes)
        case .stretchingExercisesPerWeek:
            return gap(milestone.stretchingExercises, last.stretchingExercises)
        case .cumulativeVolume:
            return gap(milestone.volumeLbs, last.volumeLbs)
        case .benchmarkTime:
            // A TIME DESCENDS, so the distance still to travel is how far the
            // last rung sits ABOVE the milestone.
            return gap(last.targetSeconds, milestone.targetSeconds)
        case .bodyWeight:
            guard let wanted = milestone.bodyWeightLbs, let now = last.bodyWeightLbs
            else { return nil }
            let remaining = (milestone.bodyWeightRatePercent ?? -1) < 0
                ? now - wanted : wanted - now
            return NSDecimalNumber(decimal: remaining).doubleValue
        case .weeklyMuscleSets:
            return nil
        }
    }

    private static func gap(_ target: Decimal?, _ last: Decimal?) -> Double? {
        guard let target, let last else { return nil }
        return NSDecimalNumber(decimal: target - last).doubleValue
    }

    private static func gap(_ target: Int?, _ last: Int?) -> Double? {
        guard let target, let last else { return nil }
        return Double(target - last)
    }

    private static func gap(_ target: Double?, _ last: Double?) -> Double? {
        guard let target, let last else { return nil }
        return target - last
    }
}
