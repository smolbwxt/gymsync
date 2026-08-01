import Foundation

// MARK: - SetProgression
//
// Next-set weight prefill from the set just completed (user 2026-08-01:
// "after completing a set, the next set should either be the same weight,
// or some progression for that exercise based off the weight that was
// completed and RPE" — never a static routine default once real work
// exists this session; a logged 355×5 @7 must not prefill 225).
//
// The rule is deliberately conservative auto-regulation: RPE ≤ 7 means
// reps in the tank → one loadable step up; RPE 8–10 (or no RPE) holds;
// a failed set holds (the lifter decides the deload, the app never
// volunteers one). Canonical-pounds domain, matching every stored weight.
enum SetProgression {

    static func nextWeight(
        afterPounds pounds: Decimal,
        rpe: Decimal?,
        isFailed: Bool,
        stepPounds: Decimal = 5
    ) -> Decimal {
        guard !isFailed, let rpe, rpe <= 7 else { return pounds }
        return pounds + stepPounds
    }
}
