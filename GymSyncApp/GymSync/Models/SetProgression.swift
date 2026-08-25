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
        return steppedPounds(fromPounds: pounds, isLowerBody: isLowerBody, unit: unit)
    }

    /// The rep-scaling base for the next-set prefill: project the last
    /// set's load onto today's rep target — with a strain asymmetry
    /// (owner 2026-08-25: "if strength is the target and I'm low on
    /// reps, I don't want the weight lighter — lower the reps, keep the
    /// weight"). Scaling UP always fires (a rep blowout raises the next
    /// set). Scaling DOWN fires only when the low-rep set was NOT a
    /// strain (RPE <= 8 or unlogged): that's a deliberate heavy single
    /// or a prescription change — the original 405x1 -> set-of-5
    /// hazard. A grind (RPE >= 9) under target is fatigue, and fatigue
    /// HOLDS the load; volunteering a lighter bar mid-fatigue is the
    /// same volunteered deload the failed-set rule already refuses.
    static func rescaledBase(
        lastPounds: Decimal,
        lastReps: Int?,
        lastRPE: Decimal?,
        targetReps: Int?
    ) -> Decimal {
        guard let targetReps, targetReps > 0,
              let lastReps, lastReps > 0, lastReps != targetReps,
              let scaled = StatMath.projectedWeight(prWeight: lastPounds,
                                                    prReps: lastReps,
                                                    targetReps: targetReps)
        else { return lastPounds }
        let scaledPounds = Decimal(scaled)
        if scaledPounds >= lastPounds { return scaledPounds }
        let strained = lastRPE.map { $0 >= 9 } ?? false
        return strained ? lastPounds : scaledPounds
    }

    /// One progression step from `pounds`: the percent fraction computed in
    /// the LIFTER'S UNIT and floored to that unit's loadable increment,
    /// minimum one increment. Shared by the within-session prefill above
    /// (which gates on RPE) and `BlockProgression`'s session-to-session
    /// advance (which gates on topping the rep range) so the two can never
    /// disagree on step math.
    static func steppedPounds(
        fromPounds pounds: Decimal,
        isLowerBody: Bool,
        unit: WeightUnit
    ) -> Decimal {
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