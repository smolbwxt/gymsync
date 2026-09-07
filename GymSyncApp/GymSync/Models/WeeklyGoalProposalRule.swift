import Foundation

// MARK: - WeeklyGoalProposalRule
//
// Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
// -goal-design.md §B, OWNER ANSWER 3 — "Propose only: Coach never overwrites
// a user-set goal; it proposes through the Coach line, and the user accepts
// in the editor." Final review finding 2.
//
// `WeeklyGoalWriteRule` is the enforcement half and it shipped first. This is
// the ASKING half: once a week's row says `source = user`, Coach's only
// recourse is a sentence on the Coach tile and an ACCEPT in the editor, and
// something has to decide whether there is anything worth saying.
//
// STATELESS BY RULING. Nothing here is stored, nothing is dismissed, nothing
// remembers that it asked: Home recomputes the answer from the row it just
// read and what `propose(weekStart:)` derives, on every refresh. A proposal
// the athlete ignores simply keeps being true until one of the two changes.

enum WeeklyGoalProposalRule {

    /// A muscle group whose target moved by this many sets or more is worth
    /// mentioning. One set is inside the noise of how a week gets written
    /// down; two is a different week.
    static let muscleSetDelta = 2.0

    /// Distance and lift targets are continuous, so theirs is a proportion
    /// of what the athlete set rather than an absolute: 10 % of 15 mi is a
    /// mile and a half, 10 % of 225 lb is 22.5 lb, and both are the point at
    /// which a suggestion stops being a rounding difference.
    static let relativeDelta = 0.10

    /// Is Coach's reading different enough from the athlete's own goal to be
    /// worth a sentence?
    ///
    /// **The whole definition of "meaningfully", in one place** (controller
    /// ruling, final review finding 2):
    ///
    ///   * a different KIND — the strongest signal there is, because the two
    ///     goals are not even about the same thing;
    ///   * `muscleSets`: any group whose target differs by ≥ 2 sets, taken
    ///     over the UNION of both goals' groups, so a group Coach adds or
    ///     drops counts as a difference of its whole target;
    ///   * `distance` and `lift`: the target differing by ≥ 10 % of the
    ///     athlete's own. An athlete's target of zero or none is treated as
    ///     "any target Coach has is a difference" rather than divided by.
    ///
    /// `days` and `sessionsOfType` have no same-kind threshold, deliberately.
    /// The ruling names three tests and these are not among them, and both
    /// kinds' numbers are ones the athlete states directly — `days` is
    /// literally `profiles.weekly_session_goal`, which Coach does not get a
    /// second opinion about. So for those two, a proposal is only ever "a
    /// different kind entirely".
    static func isMeaningful(user: WeeklyGoal, coach: WeeklyGoal) -> Bool {
        guard user.kind == coach.kind else { return true }

        switch user.kind {
        case .muscleSets:
            let mine = user.params.muscleTargets ?? [:]
            let theirs = coach.params.muscleTargets ?? [:]
            let groups = Set(mine.keys).union(theirs.keys)
            return groups.contains { group in
                let a = Double(mine[group] ?? 0)
                let b = Double(theirs[group] ?? 0)
                return abs(a - b) >= muscleSetDelta
            }

        case .distance:
            return differsRelatively(mine: user.params.distanceTarget,
                                     theirs: coach.params.distanceTarget)

        case .lift:
            // A different lift entirely is a different goal, whatever the
            // numbers say about it.
            if user.params.exerciseID != coach.params.exerciseID { return true }
            return differsRelatively(mine: user.params.targetWeightLbs.map { double($0) },
                                     theirs: coach.params.targetWeightLbs.map { double($0) })

        case .days, .sessionsOfType:
            return false
        }
    }

    /// Coach's own sentence, beginning "Coach suggests" — the editor's
    /// `Proposal.sentence` contract and the Coach tile's rung (a) read the
    /// same string, so there is one of it.
    ///
    /// `unit` is the athlete's display unit: `targetWeightLbs` is canonical
    /// pounds (`Models/Units.swift`) and must never be printed raw on a kg
    /// device, and the distance unit follows the same switch (owner answer
    /// 2 — mi with lb, km with kg).
    static func sentence(for coach: WeeklyGoal, unit: WeightUnit) -> String {
        switch coach.kind {
        case .muscleSets:
            let named = topTargets(coach.params.muscleTargets ?? [:])
            guard !named.isEmpty else {
                return "Coach suggests making this week about muscle sets."
            }
            return "Coach suggests a muscle-sets week — "
                + named.joined(separator: ", ") + "."

        case .distance:
            let target = number(coach.params.distanceTarget ?? 0)
            let label = WeeklyGoalProgressMath.distanceUnitLabel(unit)
            return "Coach suggests \(target) \(label) of \(gerund(coach.params.activity)) this week."

        case .sessionsOfType:
            let count = coach.params.count ?? 0
            let type = coach.params.sessionType ?? "training"
            return "Coach suggests \(count) \(type) \(count == 1 ? "session" : "sessions") this week."

        case .days:
            return "Coach suggests making this week about the days you train."

        case .lift:
            guard let lbs = coach.params.targetWeightLbs else {
                return "Coach suggests putting this week behind one lift."
            }
            let weight = number(double(Units.fromPounds(lbs, to: unit)))
            return "Coach suggests a lift target of \(weight) \(unit.label) this week."
        }
    }

    // MARK: - Helpers

    /// `run` reads as a noun in "15 mi of run". The four stored activities
    /// are the design's own (`WeeklyGoalParams.activity`), so this is a
    /// closed set rather than an English problem; anything else is printed
    /// as stored rather than guessed at.
    private static func gerund(_ activity: String?) -> String {
        guard let activity, !activity.isEmpty else { return "cardio" }
        switch activity {
        case "run":  return "running"
        case "bike": return "riding"
        case "row":  return "rowing"
        case "walk": return "walking"
        default:     return activity
        }
    }

    /// The three largest targets, `chest 12` style, ties broken by name so
    /// the sentence is the same sentence every time it is derived.
    private static func topTargets(_ targets: [String: Int]) -> [String] {
        targets
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(3)
            .map { "\($0.key) \($0.value)" }
    }

    /// ≥ 10 % apart, with "the athlete has no target at all" reading as a
    /// difference rather than as a division by zero.
    private static func differsRelatively(mine: Double?, theirs: Double?) -> Bool {
        let a = mine ?? 0
        let b = theirs ?? 0
        guard a > 0 else { return b > 0 }
        return abs(a - b) / a >= relativeDelta
    }

    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    /// `15` rather than `15.0`, `9.4` when the fraction is real — the same
    /// reading `HomeWeeklyGoalStrip` gives its own numbers.
    private static func number(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }
}
