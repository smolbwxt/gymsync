import Foundation

/// Pure, testable plate-loading math for the log-set UI's "Plates" affordance
/// (Phase H Task 4). Master spec unit-test list names this case explicitly:
/// "Plate math (target weight + bar weight → plate stack)."
/// (`docs/superpowers/specs/2026-06-28-gymsync-design.md:1292`).
///
/// No repository/network/view dependency — same "pure derivation" idiom as
/// `StatMath` (Models/StatMath.swift): callers pass already-parsed values in,
/// this only does arithmetic.
enum PlateMath {

    /// Standard plate denominations (lbs), descending. This app is lbs-only
    /// in v1 — no unit-preference setting exists anywhere in `profiles`/
    /// `user_settings` (same finding `BodyWeightLogSheet.swift:23-28`
    /// recorded before hardcoding its own "lbs" default).
    static let standardPlates: [Decimal] = [45, 35, 25, 10, 5, 2.5]

    /// Default Olympic barbell weight (lbs) — matches the phase design's
    /// "bar=45 default" (`docs/superpowers/specs/2026-07-18-health-calendar-
    /// design.md:19`).
    static let defaultBarWeight: Decimal = 45

    /// A per-side plate breakdown for one `stack(for:barWeight:plates:)` call.
    struct Stack: Equatable {
        /// Plate count per denomination, for ONE side of the bar —
        /// index-aligned with the `plates` array passed to `stack(for:
        /// barWeight:plates:)` (so `zip(plates, platesPerSide)` pairs them
        /// up on the caller's side).
        let platesPerSide: [Decimal]

        /// Total weight actually achieved: `barWeight + 2 × Σ platesPerSide`.
        /// Equals `target` exactly when reachable. Otherwise the nearest
        /// weight achievable AT OR BELOW `target` with the plates on hand —
        /// EXCEPT when `target` is itself below `barWeight`, in which case
        /// `achievedWeight` is `barWeight` (there is no rack weight lighter
        /// than an empty bar, so "nearest below" degrades to "the bar").
        let achievedWeight: Decimal

        /// `abs(target - achievedWeight)`. `nil` when `achievedWeight`
        /// matches `target` exactly; otherwise the shortfall (or, in the
        /// below-bar edge case, how far below the bar `target` sits) — the
        /// UI's remainder note.
        let remainder: Decimal?
    }

    /// Greedy-descending plate breakdown for `target` total bar weight
    /// (bar + plates on both sides — NOT a per-side figure).
    ///
    /// - Parameters:
    ///   - target: desired TOTAL loaded weight, including the bar.
    ///   - barWeight: empty bar weight. Defaults to `defaultBarWeight` (45).
    ///   - plates: available plate denominations, descending. Defaults to
    ///     `standardPlates`. Non-positive entries are skipped defensively.
    /// - Returns: a `Stack` — per-side plate counts, the achieved total
    ///   weight, and an optional remainder when `target` isn't exactly
    ///   reachable with the given bar + plates.
    static func stack(
        for target: Decimal,
        barWeight: Decimal = defaultBarWeight,
        plates: [Decimal] = standardPlates
    ) -> Stack {
        // Unreachable case 1: target at or below the bar itself — there is
        // no achievable rack weight below an empty bar, so this clamps to
        // the bar with no plates on either side.
        guard target > barWeight else {
            let remainder = target == barWeight ? nil : abs(target - barWeight)
            return Stack(
                platesPerSide: Array(repeating: 0, count: plates.count),
                achievedWeight: barWeight,
                remainder: remainder
            )
        }

        // Weight to distribute across BOTH sides, halved to a per-side
        // greedy budget.
        var perSideBudget = (target - barWeight) / 2
        var counts = [Decimal](repeating: 0, count: plates.count)

        for (index, denomination) in plates.enumerated() where denomination > 0 {
            guard perSideBudget >= denomination else { continue }
            var quotient = perSideBudget / denomination
            var count = Decimal()
            // Floor via `.down` — same `NSDecimalRound` idiom `StatMath.
            // formattedBodyWeight`/`SoloRecapView`/etc. use for display
            // rounding elsewhere in this codebase, `.down` instead of
            // `.plain` here so the count never overshoots the budget.
            NSDecimalRound(&count, &quotient, 0, .down)
            guard count > 0 else { continue }
            counts[index] = count
            perSideBudget -= count * denomination
        }

        // Unreachable case 2: leftover per-side budget smaller than the
        // smallest available plate — `perSideBudget` above already carries
        // this forward implicitly (it's whatever no denomination could
        // consume), so `achievedWeight` naturally lands below `target`.
        let perSideAchieved = zip(counts, plates).reduce(Decimal(0)) { $0 + $1.0 * $1.1 }
        let achievedWeight = barWeight + 2 * perSideAchieved
        let remainder = achievedWeight == target ? nil : abs(target - achievedWeight)

        return Stack(platesPerSide: counts, achievedWeight: achievedWeight, remainder: remainder)
    }
}
