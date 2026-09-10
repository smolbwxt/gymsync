import Foundation

// MARK: - The ramp rules (spec §3.4)
//
// The lifting generator prescribes `liftOneRepMax`, `liftRepsAtLoad` and
// `weeklyMuscleSets`; their rungs are READ OFF the plan (task A8). Everything
// else needs a rule, and these are them — pure, tested, and each one a single
// documented shape rather than a knob.
//
// THE DELOAD LAW, once, here, because all four rules obey it: a deload week
// never advances. The block already decided that week is lighter
// (`ProgramGenerator.swift:922-935`), and a ladder that climbed through it
// would be a second opinion about the athlete's week.
//
// TWO DECISIONS THE SPEC LEFT AS A RANGE, AND THE PLAN MAKES:
//
//   * `RateOfChangeLadderRule` — the spec gives BANDS (lose 0.5-1 % a week,
//     gain 0.25-0.5 %). The rung is the implied weekly rate needed to reach the
//     target by the date, CLAMPED into the band. An athlete who asks for
//     something achievable gets exactly their own plan; one who asks for 20 lb
//     in three weeks gets the band's edge and a `reachesMilestone: false`
//     standing (task A12) that says so.
//   * `DescendingLadderRule` — benchmark time descends LINEARLY, because there
//     is no evidence-cited curve for it in `GeneratorScience` and inventing one
//     would be a number with no source.

/// +`step` a fraction each week, with every `downWeekEvery`-th week cut to
/// `downFactor` of the week before it. Endurance's shape.
struct PercentRampLadderRule: LadderRule {
    let step: Double
    let downWeekEvery: Int
    let downFactor: Double
    /// Which field of `GoalTarget` this rule ramps — the one thing that
    /// differs between a distance ladder and a minutes ladder.
    let read: @Sendable (GoalTarget) -> Double?
    let write: @Sendable (inout GoalTarget, Double) -> Void

    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget] {
        guard weeks > 0 else { return [] }
        let start = read(current) ?? 0
        let finish = read(target) ?? start
        // A ramp needs somewhere to ramp FROM. With no measured current state
        // the honest ladder is the milestone held flat, not a climb out of
        // zero that would prescribe a first week nobody can train.
        guard start > 0, finish > start else {
            return Array(repeating: target, count: weeks)
        }
        var value = start
        var out: [GoalTarget] = []
        for index in 0..<weeks {
            let isDown = constraints.deloadWeeks.contains(index)
                || (downWeekEvery > 0 && (index + 1) % downWeekEvery == 0)
            if isDown {
                var rung = target
                write(&rung, (value * downFactor).rounded(.toNearestOrEven))
                out.append(rung)
                continue                      // the down week does not consume a step
            }
            value = min(finish, value * (1 + step))
            var rung = target
            write(&rung, (value * 10).rounded() / 10)
            out.append(rung)
        }
        // The last rung IS the milestone. A ramp that lands at 14.9 of a 15
        // target would make the final week a miss by arithmetic.
        if var last = out.last { write(&last, finish); out[out.count - 1] = last }
        return out
    }
}

/// +`step` every `everyWeeks` weeks until the target, then hold. Consistency
/// and Conditioning's shape ("+1 day every two weeks until the target holds").
struct StepEveryNWeeksLadderRule: LadderRule {
    let step: Int
    let everyWeeks: Int
    let read: @Sendable (GoalTarget) -> Int?
    let write: @Sendable (inout GoalTarget, Int) -> Void

    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget] {
        guard weeks > 0 else { return [] }
        let start = read(current) ?? 0
        let finish = read(target) ?? start
        guard finish > start else { return Array(repeating: target, count: weeks) }
        var value = start
        var sinceStep = 0
        var out: [GoalTarget] = []
        for index in 0..<weeks {
            if constraints.deloadWeeks.contains(index) {
                var rung = target
                write(&rung, value)
                out.append(rung)
                continue
            }
            sinceStep += 1
            if sinceStep >= max(1, everyWeeks) {
                value = min(finish, value + step)
                sinceStep = 0
            }
            var rung = target
            write(&rung, value)
            out.append(rung)
        }
        if var last = out.last { write(&last, finish); out[out.count - 1] = last }
        return out
    }
}

/// Body composition: the implied weekly rate, clamped into the evidence band
/// for its direction.
struct RateOfChangeLadderRule: LadderRule {
    /// Losing: 0.5–1.0 % of body weight a week. Gaining: 0.25–0.5 %.
    static let lossBand = (min: 0.005, max: 0.010)
    static let gainBand = (min: 0.0025, max: 0.005)

    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget] {
        guard weeks > 0 else { return [] }
        let start = double(current.bodyWeightLbs)
        let finish = double(target.bodyWeightLbs)
        guard start > 0, finish > 0, start != finish else {
            return Array(repeating: target, count: weeks)
        }
        let losing = finish < start
        let band = losing ? Self.lossBand : Self.gainBand
        let impliedPerWeek = abs(finish - start) / start / Double(weeks)
        let rate = Swift.min(Swift.max(impliedPerWeek, band.min), band.max)

        var value = start
        var out: [GoalTarget] = []
        for index in 0..<weeks {
            if !constraints.deloadWeeks.contains(index) {
                value = losing ? value * (1 - rate) : value * (1 + rate)
                value = losing ? Swift.max(value, finish) : Swift.min(value, finish)
            }
            var rung = target
            rung.bodyWeightLbs = Decimal((value * 10).rounded() / 10)
            rung.bodyWeightRatePercent = (losing ? -rate : rate) * 100
            out.append(rung)
        }
        return out
    }

    private func double(_ value: Decimal?) -> Double {
        value.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
    }
}

/// Cumulative volume: the TONNAGE-TO-DATE each week should end on, climbing to
/// the milestone.
///
/// **THE RUNGS ARE CUMULATIVE, AND `cumulativeVolume` IS THE ONLY METRIC IN THE
/// REGISTRY WHOSE MILESTONE IS PER-BLOCK RATHER THAN PER-WEEK** (controller
/// ruling, fix round 1). Every other rung answers "what should this week be";
/// this one answers "where should the block stand by the end of this week",
/// because the milestone it climbs to — 100,000 lb moved — is a total and not a
/// rate. Rungs on the same scale as the milestone are what lets standing
/// compare the last rung against it and get an honest answer; per-week rungs
/// made every dated Volume goal report itself as falling short from day one.
///
/// `current.volumeLbs` IS THE TONNAGE ALREADY BANKED, so only what is LEFT gets
/// spread: a 100,000 lb block sitting at 40,000 with five weeks to go asks for
/// 60,000 over those five, not another 100,000. Re-laddering therefore does not
/// re-ask for work the athlete has already done.
///
/// A deload week takes HALF A SHARE of what remains (the generator's own
/// `deloadVolumeMultiplier` reasoning) and the other weeks carry what it gave
/// up, so the block still arrives.
///
/// The WEEK'S OWN share — the number the strip asks for — is the step up from
/// the week before, and `LadderMath.weeklyGoal(from:…:previousRung:)` is where
/// that subtraction happens. It is not stored on the rung, because
/// `GoalTarget` is the frozen Task 0 shape and a second volume field would be
/// two numbers for one fact.
struct CumulativeLadderRule: LadderRule {
    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget] {
        guard weeks > 0, let total = target.volumeLbs, total > 0 else {
            return Array(repeating: target, count: Swift.max(0, weeks))
        }
        // Clamped at both ends: a block already past its milestone asks for
        // nothing more, and a negative reading cannot inflate what is left.
        let done = Swift.min(Swift.max(0, current.volumeLbs ?? 0), total)
        let remaining = total - done

        let weights = (0..<weeks).map { constraints.deloadWeeks.contains($0) ? 0.5 : 1.0 }
        let denominator = weights.reduce(0, +)
        guard denominator > 0 else { return Array(repeating: target, count: weeks) }

        var running = done
        var out: [GoalTarget] = []
        for weight in weights {
            running += remaining * weight / denominator
            var rung = target
            rung.volumeLbs = (running / 100).rounded() * 100
            out.append(rung)
        }
        // The last rung IS the milestone, for the reason the ramps force theirs:
        // rounding to the hundred must not make the final week a miss by
        // arithmetic.
        if var last = out.last { last.volumeLbs = total; out[out.count - 1] = last }
        return out
    }
}

/// Benchmark time descends linearly from the measured current time to the
/// target. A deload week holds the week before it.
struct DescendingLadderRule: LadderRule {
    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget] {
        guard weeks > 0 else { return [] }
        guard let start = current.targetSeconds, let finish = target.targetSeconds,
              start > finish else {
            return Array(repeating: target, count: weeks)
        }
        var out: [GoalTarget] = []
        var previous = start
        for index in 0..<weeks {
            var rung = target
            if constraints.deloadWeeks.contains(index) {
                rung.targetSeconds = previous
            } else {
                let progress = Double(index + 1) / Double(weeks)
                previous = start - Int((Double(start - finish) * progress).rounded())
                rung.targetSeconds = previous
            }
            out.append(rung)
        }
        return out
    }
}

extension LadderRules {
    /// The eight ramp-driven metrics. `liftOneRepMax`, `liftRepsAtLoad` and
    /// `weeklyMuscleSets` are absent BY DESIGN: their rungs are read off
    /// `Program.weeks` (task A8), never ramped.
    static func rampRule(for metric: GoalMetric) -> (any LadderRule)? {
        switch metric {
        case .weeklyDistance:
            return PercentRampLadderRule(
                step: 0.10, downWeekEvery: 4, downFactor: 0.7,
                read: { $0.distance }, write: { $0.distance = $1 })
        case .trainingDaysPerWeek:
            return StepEveryNWeeksLadderRule(
                step: 1, everyWeeks: 2,
                read: { $0.days }, write: { $0.days = $1 })
        case .sessionsOfTypePerWeek:
            return StepEveryNWeeksLadderRule(
                step: 1, everyWeeks: 2,
                read: { $0.sessions }, write: { $0.sessions = $1 })
        case .lissMinutesPerWeek, .stretchingExercisesPerWeek:
            return HoldLadderRule()
        case .bodyWeight:      return RateOfChangeLadderRule()
        case .cumulativeVolume: return CumulativeLadderRule()
        case .benchmarkTime:   return DescendingLadderRule()
        case .liftOneRepMax, .liftRepsAtLoad, .weeklyMuscleSets:
            return nil
        }
    }
}
