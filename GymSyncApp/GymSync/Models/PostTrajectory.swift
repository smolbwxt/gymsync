import Foundation

// MARK: - What a pump-check post carries about the athlete's trajectory
//
// Spec: docs/superpowers/specs/2026-09-11-social-cards-design.md §1, §2, §6.
// Plan: docs/superpowers/plans/2026-09-11-social-cards-plan.md, task S2.0.
//
// A POST IS A SNAPSHOT, NOT A QUERY. `workout_posts.summary` has been an
// immutable snapshot since 2026-07 (WorkoutPost.swift:4-9) and everything
// here joins it, for two reasons that point the same way:
//
//   1. RLS. `block_goals` and `weekly_goals` are own-rows
//      (20260907000001:49-51, 20260906000001:54-56). A friend cannot read the
//      author's goal at all, so a card that resolved `goal_id` at render time
//      would show the trajectory to exactly one person: its author. Owner
//      decision 3 says the opposite.
//   2. Drift. Spec §6: snapshotted "so the card does not drift as the ladder
//      re-ladders". A ladder re-derives every week (goal-first spec §3.5); a
//      post is a moment.
//
// The author resolves these at POST time, through their own
// `BlockGoalRepository` and `WeeklyGoalRepository.progress(for:)` — the only
// reads RLS permits — and the row carries the answer.

/// What kind of thing Coach offered and the lifter picked (spec §1 line 4).
/// Raw values are the wire values of `workout_posts.highlight ->> 'kind'`.
enum PostHighlightKind: String, Codable, Sendable, Equatable {
    case topSet, pr, milestone
}

/// The one editorial line on the card (spec §1 line 4) — chosen by the
/// lifter from Coach's proposals, or absent. No free text: every field below
/// is computed by `HighlightMath` from the session's own snapshot.
///
/// `text` IS UNIT-FREE and the numbers ride beside it, which is spec §6's
/// `{kind, text}` plus the Units doctrine. A frozen string reading "235 lb"
/// would show pounds to a friend whose app is in kilos, and the whole point
/// of `summary`'s canonical pounds (WorkoutPost.swift:6-9) is that the FEED
/// converts. `HighlightText.line(_:unit:)` (task S2.5) is the one place that
/// composes the two halves.
struct PostHighlight: Codable, Sendable, Equatable {
    let kind: PostHighlightKind
    /// The noun phrase — "Top set — Back Squat", "PR — Back Squat",
    /// "Lifetime total crossed".
    let text: String
    /// CANONICAL POUNDS, rendered in the viewer's unit. nil for a highlight
    /// with no weight in it.
    let weightLbs: Decimal?
    let reps: Int?
}

/// Lines 2 and 3 of the card, resolved at post time.
struct PostTrajectory: Codable, Sendable, Equatable {

    /// The third segment of the trajectory line. Three words, no more: spec
    /// §1's table says `on track`, `behind`, `met`.
    enum Standing: String, Codable, Sendable, Equatable {
        case onTrack, behind, met

        /// Sentence case, because the line is a sentence (design rule 9).
        var word: String {
            switch self {
            case .onTrack: return "on track"
            case .behind:  return "behind"
            case .met:     return "met"
            }
        }
    }

    /// One rung chip, in the shape `GSGoalChip` renders (task S2.3).
    ///
    /// NO `isNext`. The Home strip rings the group furthest behind because
    /// that is an invitation to act this week (design rule 2's third job for
    /// accent); a finished post is not an invitation, so the card's chips
    /// carry no ring and the field does not exist to be set by mistake.
    struct Chip: Codable, Sendable, Equatable {
        let name: String
        let done: Double
        let target: Double
        /// The meter's fill, 0...1, when the fraction the NUMBERS print is
        /// not the fraction the METER draws — every span-above-a-floor kind
        /// (`lift`, `bodyWeight`, `benchmark`), where the strip prints
        /// `205 → 225` over a meter measured from where the block started.
        /// nil means `done / target`, the muscle-sets rule.
        let fill: Double?
    }

    /// The milestone as the ladder page words it — `Bench 225 by Oct 18`.
    /// Taken from `LadderPageModel.headline`, never re-worded here: two
    /// spellings of one milestone is two milestones.
    let goalLine: String
    let weekNumber: Int
    let weekCount: Int
    let standing: Standing
    /// This week's rung, as chips. Empty is legal and means the card draws no
    /// line 3.
    let chips: [Chip]

    /// Spec §1 line 2, verbatim: `Bench 225 by Oct 18 · week 3 of 8 · on track`.
    var line: String {
        "\(goalLine) · week \(weekNumber) of \(weekCount) · \(standing.word)"
    }
}

/// How late a post is, precisely (spec §2, borrowed from BeReal).
///
/// The shipped `is_late` was a BOOLEAN computed client-side from the CAPTURE
/// timestamp against a 60 s window (`PumpCheckComposer.swift:35-37, 75`).
/// Spec §2 keeps the column and changes what fills it: elapsed time from the
/// session's COMPLETION to the post. Old rows keep their boolean and the card
/// falls back to it.
///
/// THE BOOLEAN ITSELF IS NO LONGER COMPUTED HERE. `isLate(completedAt:
/// postedAt:fallback:)` lived on this type until review fix 6 moved the
/// derivation into a BEFORE INSERT trigger
/// (`20260912000002_workout_posts_is_late_trigger.sql`), so that the flag and
/// the `created_at` the card measures its tag against come from ONE clock.
/// With no production caller left it was deleted rather than kept alive by
/// its own tests — the same rule that removed `WorkoutPostRepository.unreact`
/// in task S2.8. What stays here is what the CARD needs: the elapsed time and
/// the two tags it prints.
enum PostLateness {

    /// The pump-check window, unchanged since 2026-07
    /// (`PumpCheckComposer.swift:49`). Read by the composer's countdown and
    /// by `tag` below.
    ///
    /// SPELLED TWICE, in two languages: `interval '60 seconds'` in
    /// `20260912000002_workout_posts_is_late_trigger.sql` is the same window
    /// on the server side of the wire, where `is_late` is now derived. There
    /// is no way to share one literal across that boundary; if the window
    /// moves, both move together.
    static let windowSeconds: TimeInterval = 60

    /// Seconds from the session's completion to the post, or **nil when there
    /// is no completion to measure from** — an absence, never a zero.
    static func elapsed(completedAt: Date?, postedAt: Date) -> TimeInterval? {
        guard let completedAt else { return nil }
        return max(0, postedAt.timeIntervalSince(completedAt))
    }

    /// The author row's tag — `posted 47 min after` — or **nil when the post
    /// is inside the window**, which is the on-time case and wears no tag at
    /// all (spec §5: the card's existing behaviour for a prompt post does not
    /// change).
    ///
    /// Three scales, so the tag is always two tokens wide: minutes below
    /// 90 min, hours below 48 h, days above.
    static func tag(completedAt: Date?, postedAt: Date) -> String? {
        guard let elapsed = elapsed(completedAt: completedAt, postedAt: postedAt),
              elapsed > windowSeconds else { return nil }
        let minutes = Int(elapsed / 60)
        if minutes < 90 { return "posted \(max(1, minutes)) min after" }
        let hours = Int(elapsed / 3600)
        if hours < 48 { return "posted \(hours) hr after" }
        return "posted \(Int(elapsed / 86_400)) days after"
    }

    /// `2 retakes` — or nil at zero, because "0 retakes" is a boast.
    static func retakeTag(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 retake" : "\(count) retakes"
    }
}
