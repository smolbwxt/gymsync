import Foundation

// MARK: - Coach's highlight proposals
//
// Spec §1 line 4. Plan task S2.5. PURE and FETCH-FREE: every proposal comes
// out of the post's own summary, which the composer already holds.

enum HighlightMath {

    /// The proposals Coach offers, in spec §1's own order: the best top set,
    /// then the PR. **Two, not three, in this release.**
    ///
    /// THE MILESTONE PROPOSAL IS NOT HERE, and deliberately has no private
    /// ladder standing in for it. The You milestone-hero spec
    /// (`docs/superpowers/specs/2026-09-06-you-milestone-hero-design.md`)
    /// defines the ONE catalog — `MilestoneCatalog.swift`, thirty rungs with
    /// sources, one currency (plates from pounds). A local array of round
    /// numbers here would be a second accounting of the same pounds, and the
    /// second accounting is the one that rots. When the hero ships, the third
    /// proposal is `MilestoneCatalog`'s own "which rung did this session
    /// cross" read, `PostHighlightKind.milestone` is already in this enum and
    /// already in `workout_posts.highlight`'s CHECK, and nothing here changes
    /// shape — only this function grows an arm.
    ///
    /// THE PR SUPPRESSES THE TOP SET WHEN THEY ARE THE SAME SET. Otherwise
    /// the picker offers "Top set — Back Squat 235 × 3" above "PR — Back
    /// Squat 235 × 3", which is one fact twice and makes the lifter choose
    /// between two spellings of it.
    static func propose(summary: PostSummary) -> [PostHighlight] {
        var proposals: [PostHighlight] = []

        let best = bestSet(in: summary)
        let pr = prSet(in: summary)
        var prIsTheTopSet = false
        if let best, let pr {
            prIsTheTopSet = best.exercise == pr.exercise
                && best.set.weightLbs == pr.set.weightLbs
                && best.set.reps == pr.set.reps
        }

        if let best, !prIsTheTopSet {
            proposals.append(PostHighlight(kind: .topSet,
                                           text: "Top set — \(best.exercise)",
                                           weightLbs: best.set.weightLbs,
                                           reps: best.set.reps))
        }
        if let pr {
            proposals.append(PostHighlight(kind: .pr,
                                           text: "PR — \(pr.exercise)",
                                           weightLbs: pr.set.weightLbs,
                                           reps: pr.set.reps))
        }
        // The cap stays at three: the milestone arm lands inside it, and a
        // `prefix` that already fits is what keeps that a one-line change.
        return Array(proposals.prefix(3))
    }

    /// The highest estimated one-rep max of the session's non-failed, weighted
    /// sets — "best" by what it implies, not by what is on the bar, so a heavy
    /// single and a lighter set of eight are compared fairly.
    /// `StatMath.estimatedOneRepMax` is the app's own formula
    /// (`StatMath.swift:125`); this does not invent a second one.
    static func bestSet(in summary: PostSummary)
        -> (exercise: String, set: PostSummary.ExerciseEntry.SetEntry)? {
        var best: (exercise: String, set: PostSummary.ExerciseEntry.SetEntry, e1rm: Decimal)?
        for exercise in summary.exercises {
            for set in exercise.sets where !set.isFailed {
                guard let weight = set.weightLbs, weight > 0,
                      let reps = set.reps, reps > 0 else { continue }
                let e1rm = StatMath.estimatedOneRepMax(weight: weight, reps: reps)
                if best == nil || e1rm > best!.e1rm {
                    best = (exercise.name, set, e1rm)
                }
            }
        }
        return best.map { ($0.exercise, $0.set) }
    }

    /// The session's PR, if it flagged one. `isPR` is stamped into the
    /// snapshot at post time by the recap's own PR read — this does not
    /// re-derive it.
    static func prSet(in summary: PostSummary)
        -> (exercise: String, set: PostSummary.ExerciseEntry.SetEntry)? {
        for exercise in summary.exercises {
            for set in exercise.sets where set.isPR && !set.isFailed {
                return (exercise.name, set)
            }
        }
        return nil
    }

}

/// The card's one highlight line, IN THE VIEWER'S UNIT.
///
/// Separate from `HighlightMath` because it is a rendering rule where those
/// are a training one, and because the composer (which proposes) and the feed
/// (which renders) sit on opposite sides of the wire.
enum HighlightText {
    static func line(_ highlight: PostHighlight, unit: WeightUnit) -> String {
        switch highlight.kind {
        case .topSet, .pr:
            guard let weightLbs = highlight.weightLbs, let reps = highlight.reps else {
                return highlight.text
            }
            let weight = Units.format(pounds: weightLbs, unit: unit,
                                      rounded: false, includeUnit: true)
            return "\(highlight.text) \(weight) × \(reps)"
        case .milestone:
            // NOT PROPOSED IN THIS RELEASE (see `propose`), but rendered
            // anyway: the kind is in the column's domain, a row could carry
            // one from a later build, and a card that met an unknown kind and
            // drew nothing would be a blank line where a milestone was.
            guard let weightLbs = highlight.weightLbs else { return highlight.text }
            let total = StatMath.compactNumber(Units.fromPounds(weightLbs, to: unit))
            return "\(highlight.text) — \(total) \(unit.label)"
        }
    }
}
