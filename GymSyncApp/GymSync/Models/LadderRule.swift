import Foundation

// MARK: - LadderRule
//
// Spec §3.4: "Each rule is a pure function (current, target, weeks) ->
// [target per week] with tests." The fourth parameter is the block's own
// shape — the deload and taper weeks the generator already decided — because
// a ramp that ignored the deload would put a peak week on top of the week the
// block halves the volume in.
//
// PURE, and the registry is a plain switch rather than a runtime table: the
// set of metrics is closed at compile time (`GoalMetric.allCases`), and a
// switch makes a new metric without a rule a compile error.

/// What the block already decided, handed to a ramp so it can respect it.
struct LadderConstraints: Equatable, Sendable {
    /// 0-based week indices the generator marked `isDeload`.
    var deloadWeeks: Set<Int> = []
    /// 0-based week indices carrying the strength taper (`Program.weeks`'
    /// final-week volume cut).
    var taperWeeks: Set<Int> = []
    /// The athlete's display unit. A ramp rounds in the unit the plates and
    /// the road signs are marked in, never in pounds and then converted —
    /// the doctrine `Units.roundToIncrement` and
    /// `WeeklyGoalDetector.liftTarget` both follow.
    var unit: WeightUnit = .lbs
}

/// One rung per week, from where the athlete is to where they said they want
/// to be.
protocol LadderRule: Sendable {
    /// Exactly `weeks` targets, 0-based by week index. `current` is the
    /// measured state (task A5's readers); `target` is the milestone.
    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget]
}

/// A ladder that holds one value for the whole block — Maintenance and
/// Recovery's shape (spec §2.3), and the honest fallback for any metric whose
/// milestone is "keep doing this".
struct HoldLadderRule: LadderRule {
    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget] {
        Array(repeating: target, count: max(0, weeks))
    }
}

/// Which rule builds which metric's ladder.
///
/// Stream A task A7 replaced every `HoldLadderRule` below with the metric's
/// real ramp, and A8 replaces the three the GENERATOR prescribes
/// (`liftOneRepMax`, `liftRepsAtLoad`, `weeklyMuscleSets`) with the read-out
/// — which is not a rule at all but a projection of `Program.weeks`, and is
/// why those three route through `LadderReadout` at the call site rather than
/// through here. The stub keeps every metric answerable from Task 0 onward.
enum LadderRules {
    /// **A7 re-pointed the BODY of this function; its signature is unchanged.**
    /// The eight ramp-driven metrics now answer with their real shape
    /// (`LadderRules+Ramps.swift`), and the three the generator prescribes
    /// answer `nil` there and fall through to `HoldLadderRule` here — a flat
    /// ladder is the honest placeholder for a metric whose rungs are READ OFF
    /// the block at the call site (`LadderReadout`, task A8), never ramped.
    ///
    /// Leaving the old all-`Hold` switch in place would have been the worse
    /// option: every caller would still compile and every ladder would still
    /// be flat, silently.
    static func rule(for metric: GoalMetric) -> any LadderRule {
        rampRule(for: metric) ?? HoldLadderRule()
    }
}
