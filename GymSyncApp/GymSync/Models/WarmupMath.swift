import Foundation

// MARK: - WarmupMath
//
// Design: docs/superpowers/specs/2026-07-26-lifting-quality-design.md,
// Phase W. The app used to prescribe 3×5 @ 225 and expect the lifter to
// walk up and do it; this produces the ladder that gets them there.
//
// Pure and testable (the StatMath / PlateMath / ProgramMath idiom). No
// repository, no view, no network.
//
// WARM-UPS ARE NOT SETS. Nothing here is logged: they never touch volume,
// PRs, streaks, program progress, or leaderboards. Logging them would
// corrupt every downstream number in the app — a 5-rung ramp would inflate
// session volume by a third and could fabricate a "PR" on the top rung.
// This is a checklist, and it stays one.
enum WarmupMath {

    struct Step: Equatable, Identifiable {
        /// Load in canonical POUNDS (see Units — storage is always lbs).
        let pounds: Decimal
        let reps: Int
        /// True for the empty-bar rung, which is always first.
        let isBar: Bool
        var id: String { "\(pounds)-\(reps)" }
    }

    /// Conventional ramp: empty bar, then ~55/70/85/95% of the working
    /// weight for descending reps. Percentages are the common
    /// strength-training ladder rather than anything derived — the app is
    /// not claiming science it doesn't have, it's saving arithmetic.
    private static let rungs: [(percent: Decimal, reps: Int)] = [
        (0.55, 5), (0.70, 3), (0.85, 2), (0.95, 1)
    ]

    /// Builds the ladder for `workingPounds`.
    ///
    /// - Every rung is rounded to what can actually be LOADED in the user's
    ///   unit, because a warm-up you can't assemble is worse than none.
    /// - Rungs at or above the working weight are dropped: a 95 lb working
    ///   set doesn't need a five-step ramp, and a "warm-up" heavier than
    ///   the work is nonsense.
    /// - Rounding collapses neighbouring rungs onto the same load fairly
    ///   often at light weights; duplicates are removed so the lifter never
    ///   sees "95 lb ×3" twice.
    /// - Returns [] when the working weight is at or below the bar — there
    ///   is nothing to ramp toward.
    static func ramp(workingPounds: Decimal,
                     barPounds: Decimal,
                     unit: WeightUnit) -> [Step] {
        guard workingPounds > barPounds else { return [] }

        var steps: [Step] = [Step(pounds: barPounds, reps: 5, isBar: true)]

        for rung in rungs {
            let raw = workingPounds * rung.percent
            // Round in the USER'S unit, then convert back — rounding in
            // pounds would produce loads a kg lifter can't build.
            let inUnit = Units.fromPounds(raw, to: unit)
            let snapped = Units.roundToIncrement(inUnit, unit: unit)
            let pounds = Units.toPounds(snapped, from: unit)

            guard pounds > barPounds, pounds < workingPounds else { continue }
            guard !steps.contains(where: { $0.pounds == pounds }) else { continue }
            steps.append(Step(pounds: pounds, reps: rung.reps, isBar: false))
        }

        return steps
    }
}
