import Foundation

// MARK: - SetProgression
//
// Next-set weight prefill from the set just completed (user 2026-08-01:
// "after completing a set, the next set should either be the same weight,
// or some progression for that exercise based off the weight that was
// completed and RPE" — never a static routine default once real work
// exists this session; a logged 355×5 @7 must not prefill 225).
//
// The gate is deliberately conservative auto-regulation: RPE ≤ 7 means
// reps in the tank → one step up; RPE 8–10 (or no RPE) holds; a failed
// set holds (the lifter decides the deload, the app never volunteers one).
//
// Step sizing (research audit 2026-08, replacing the flat +5 lb): ~2.5%
// of the load for upper-body lifts, ~5% for lower-body (ACSM's 2–10%
// band, split per coaching convention), computed in the LIFTER'S UNIT and
// floored to that unit's loadable increment — the old flat step handed kg
// users a +2.27 kg suggestion no plate pair can build. Floor (not
// nearest) keeps jumps conservative; the minimum step is one increment,
// which reproduces the old +5 lb behavior at typical upper-body loads.
// Canonical-pounds domain in and out, matching every stored weight.
enum SetProgression {

    private static let upperBodyStepFraction = Decimal(0.025)
    private static let lowerBodyStepFraction = Decimal(0.05)

    static func nextWeight(
        afterPounds pounds: Decimal,
        rpe: Decimal?,
        isFailed: Bool,
        isLowerBody: Bool = false,
        unit: WeightUnit = .lbs
    ) -> Decimal {
        guard !isFailed, let rpe, rpe <= 7, pounds > 0 else { return pounds }
        let fraction = isLowerBody ? lowerBodyStepFraction : upperBodyStepFraction
        let unitLoad = Units.fromPounds(pounds, to: unit)
        let increment = unit.displayIncrement
        let rawStep = unitLoad * fraction
        let flooredSteps = max(1, Int(NSDecimalNumber(decimal: rawStep / increment).doubleValue.rounded(.down)))
        let step = Decimal(flooredSteps) * increment
        let next = Units.roundToIncrement(unitLoad + step, step: increment)
        return Units.toPounds(next, from: unit)
    }
}