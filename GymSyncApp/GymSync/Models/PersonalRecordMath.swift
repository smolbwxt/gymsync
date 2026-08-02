import Foundation

// MARK: - PersonalRecordMath
//
// What counts as a personal record, and what a lifter's one-rep max IS.
//
// Owner's definition (2026-08-02): "PRs should just be what you've
// accomplished, and a one rep max should be estimated if you've never logged
// a max." Two distinct ideas that the app previously collapsed into one:
//
//   • A PR is a REAL achievement, judged against the rep count it happened at.
//     A heavy single and a hard set of ten are separate accomplishments and
//     must not compete — the old rule (heaviest weight ever, reps ignored)
//     meant a 12-rep set at your 10-rep weight celebrated nothing, while any
//     near-max single always celebrated.
//
//   • A one-rep max is MEASURED if you have ever actually done a single, and
//     ESTIMATED from your best work otherwise. The app already computes the
//     estimate to drive weight suggestions; this makes the distinction
//     explicit so the number can be shown honestly.
enum PersonalRecordMath {

    /// The heaviest weight already lifted for **at least** `reps` reps.
    ///
    /// "At least" is the load-bearing part. If you have done 8 × 225, then
    /// 5 × 225 is not an achievement — you have demonstrably done harder work
    /// at that weight — so the comparison for a 5-rep set must include your
    /// 8-rep sets. Conversely a 12-rep set is measured only against your other
    /// 12+ rep sets, which is what lets volume PRs exist at all.
    static func bestWeight(atLeastReps reps: Int, in basis: [(weight: Decimal, reps: Int)]) -> Decimal {
        basis
            .filter { $0.reps >= reps }
            .map(\.weight)
            .max() ?? 0
    }

    /// Is this set a personal record?
    ///
    /// Requires a rep count: without one there is nothing to judge the weight
    /// against, and inventing a comparison is how the old rule went wrong.
    /// Strictly greater — matching your best is not beating it.
    static func isPR(weight: Decimal, reps: Int?, basis: [(weight: Decimal, reps: Int)]) -> Bool {
        guard let reps, reps > 0, weight > 0 else { return false }
        return weight > bestWeight(atLeastReps: reps, in: basis)
    }

    /// A lifter's one-rep max for an exercise: what they have actually done if
    /// they have ever done a single, otherwise the best estimate their history
    /// supports.
    ///
    /// `nil` when there is no qualifying history at all — callers show nothing
    /// rather than a fabricated number.
    static func oneRepMax(from basis: [(weight: Decimal, reps: Int)]) -> OneRepMax? {
        guard !basis.isEmpty else { return nil }

        // A logged single is ground truth and outranks any estimate, even a
        // larger one: a formula extrapolating 420 from a 5-rep set does not
        // override the 405 this person actually stood up with.
        if let measured = basis.filter({ $0.reps == 1 }).map(\.weight).max(), measured > 0 {
            return OneRepMax(pounds: measured, isMeasured: true)
        }

        // Otherwise: the highest Epley estimate across their qualifying work,
        // the same formula and set-selection the weight suggestions use, so
        // the displayed max and the suggested loads can never disagree.
        var best: Decimal = 0
        for set in basis where set.reps > 0 && set.weight > 0 {
            let estimate = StatMath.estimatedOneRepMax(weight: set.weight, reps: set.reps)
            if estimate > best { best = estimate }
        }
        return best > 0 ? OneRepMax(pounds: best, isMeasured: false) : nil
    }

    /// A one-rep max plus whether it was actually lifted or inferred.
    struct OneRepMax: Equatable, Sendable {
        let pounds: Decimal
        /// True when the lifter has logged an actual single at this weight.
        let isMeasured: Bool
    }
}
