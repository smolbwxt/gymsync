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
    /// The BLOCK-relative week index that local index 0 sits on.
    ///
    /// **THE CADENCE ANCHOR** (round 2, item O2). `deloadWeeks` and `taperWeeks`
    /// are translated into the window a rule is about to iterate
    /// (`LadderMath.windowed`), but a rule with a cadence of its OWN —
    /// `PercentRampLadderRule`'s "every fourth week is a down week" — counts
    /// from the start of whatever it is handed. On a re-ladder that is the
    /// window, not the block, so the down week re-phased on every refresh: an
    /// eight-week endurance block's weeks 4 and 8 became weeks 6 and 10 of
    /// nothing after two weeks closed.
    ///
    /// With the origin the rule can ask what BLOCK week a local index is, and
    /// anchor its cadence there. 0 for a fresh derivation, which is what every
    /// call site that does not re-ladder means.
    ///
    /// Assumes the window is contiguous, which it is except when an athlete has
    /// overridden a future week; the deload SET is exact either way, and a
    /// down-week cadence off by one on a holed ladder is a smaller wrong than
    /// the one this replaces.
    var phaseOriginWeekIndex: Int = 0
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
