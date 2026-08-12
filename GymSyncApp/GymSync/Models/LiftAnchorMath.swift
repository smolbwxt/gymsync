import Foundation

// MARK: - LiftAnchorMath
//
// Getting-started seeds (owner 2026-08-12): the lifter states confident
// 5-rep weights for the primary barbell compounds during onboarding; this
// module turns those anchors into starting-weight seeds — for the anchor
// lifts themselves and for a small set of ratio-derived barbell variants.
//
// Honesty rules (science audit 2026-08):
// - Ratio tables are coaching convention with ±20% person-to-person
//   variance — fine as a starting prior, poison as a record. Seeds feed
//   ONLY WorkingWeight's `.seeded` rung (below `.lastSet`, so any real
//   logged set outranks them) and never enter set_logs, PR math, or
//   volume.
// - Derived seeds multiply by a 0.9 conservatism factor: a light first
//   session costs one workout; a heavy one costs form and trust. Anchor
//   lifts themselves seed at face value — the lifter stated them.
// - Barbell-only v1: dumbbell/machine ratios vary too much to guess.
enum LiftAnchorMath {

    /// The four anchor lifts, by their seeded catalog slugs
    /// (supabase/migrations/20260709000003_seed_exercises.sql).
    static let anchorSlugs = ["back-squat", "bench-press", "deadlift", "ohp"]

    /// slug → (anchor slug, ratio of the anchor's weight). Convention
    /// values from common strength-ratio tables; deliberately short.
    private static let derivedRatios: [String: (anchor: String, ratio: Decimal)] = [
        "front-squat":         ("back-squat",  Decimal(0.85)),
        "goblet-squat":        ("back-squat",  Decimal(0.45)),
        "incline-bench-press": ("bench-press", Decimal(0.80)),
        "rdl":                 ("deadlift",    Decimal(0.85)),
        "sumo-deadlift":       ("deadlift",    Decimal(0.95)),
    ]

    private static let derivedConservatism = Decimal(0.9)

    /// The seed weight (canonical POUNDS) for `slug` given the lifter's
    /// stated anchors — the anchor itself at face value, a mapped variant
    /// at ratio × 0.9, `nil` for anything else (no fake confidence).
    /// Rounded to the 5-lb pair grid like every other derived suggestion
    /// (`StatMath.projectedWeight` precedent).
    static func seedPounds(for slug: String, anchors: [String: Decimal]?) -> Decimal? {
        guard let anchors, !anchors.isEmpty else { return nil }
        let raw: Decimal?
        if let anchor = anchors[slug], anchor > 0 {
            raw = anchor
        } else if let mapping = derivedRatios[slug],
                  let anchor = anchors[mapping.anchor], anchor > 0 {
            raw = anchor * mapping.ratio * derivedConservatism
        } else {
            raw = nil
        }
        guard let raw else { return nil }
        let rounded = Units.roundToIncrement(raw, step: 5)
        return rounded > 0 ? rounded : nil
    }
}