import Foundation

// MARK: - The card's lines 2 and 3, computed once, at post time
//
// Spec §1. Plan task S2.4. PURE: everything here takes resolved values and
// returns a value. No repository, no clock, no view.

enum PostTrajectoryMath {

    /// Which of spec §1's three words the card prints.
    ///
    /// THE CARD AGREES WITH THE LADDER PAGE, and that is the whole rule.
    /// `LadderPageModel.coachLine` says "On track" whenever the ladder still
    /// `reachesMilestone`, so a standing derived from anything else puts two
    /// verdicts on one block: the page telling the athlete they are on track
    /// and their own post telling their crew they are behind.
    ///
    /// ORDERED: an outcome the block already recorded beats a ladder still
    /// being re-derived; a last rung already met beats everything ahead of
    /// it; otherwise the ladder's own reach decides.
    ///
    /// NO MISSED-RUNG BRANCH (review fix 1 — supersedes the plan's S2.4
    /// snippet). It used to read `if page.rows.contains { $0.status == .missed
    /// } { return .behind }`, which pinned the card to `behind` for the rest
    /// of the block after one bad week even while the ladder had re-derived
    /// and still reached the date. A missed week that the ladder has already
    /// absorbed is history, not standing.
    static func standing(goal: BlockGoal, page: LadderPageModel) -> PostTrajectory.Standing {
        if goal.outcome == .met { return .met }
        if let last = page.rows.last, last.status == .met, page.reachesMilestone { return .met }
        return page.reachesMilestone ? .onTrack : .behind
    }

    /// This week's rung, as the chips the card draws — at most four, which is
    /// the number the Home strip's row is built for.
    ///
    /// THREE FAMILIES, and the split is what keeps the card honest:
    ///
    ///   * `muscleSets` carries DISPLAY chips and its `chips` array IS the
    ///     strip's reading — four muscle groups, four chips, same numbers.
    ///   * `recovery` also carries chips that pass straight through (both of
    ///     them: stretches beside LISS minutes). It is NOT the same claim,
    ///     though — the strip itself renders recovery as a meter plus two
    ///     lines, not as a chip row, so these are the strip's FACTS in the
    ///     card's own shape rather than a copy of the strip's layout
    ///     (review fix 3 — the plan's S2.4 comment claimed the stronger thing
    ///     for the whole family).
    ///   * `days` carries SEVEN weekday chips, and those must not pass
    ///     through. `prefix(4)` of them is Monday-to-Thursday, so a lifter
    ///     who trains Thursday to Saturday posted `0/0 · 0/0 · 0/0 · 0/0` —
    ///     four empty chips under a line claiming a rung (review fix 2 —
    ///     supersedes the plan's S2.4 snippet). One chip, `DAYS`, carrying
    ///     the strip's own reading.
    ///   * every other kind carries ONE SUBJECT chip, whose `done`/`target`
    ///     are the meter's geometry and not the numbers the strip prints —
    ///     for `lift`, `bodyWeight` and `benchmark` that geometry is measured
    ///     from where the BLOCK started (`WeeklyGoalProgressMath` lines
    ///     502-508). So the chip prints `progress.value / progress.target`,
    ///     which is what the strip's own reading prints, and carries the
    ///     subject chip's fraction as `fill`.
    ///
    /// EXHAUSTIVE, no `default:` — this is the fourteenth such switch in the
    /// app and the reason `WeeklyGoalKind`'s doc comment counts them: a tenth
    /// kind must be a compile error here rather than a card that silently
    /// stops showing a rung.
    static func chips(kind: WeeklyGoalKind,
                      progress: WeeklyGoalProgress) -> [PostTrajectory.Chip] {
        switch kind {
        case .muscleSets, .recovery:
            return progress.chips.prefix(4).map {
                PostTrajectory.Chip(name: $0.name, done: $0.done,
                                    target: $0.target, fill: nil)
            }
        case .days:
            // The strip's own reading — "3 of 4 days" — not four of the seven
            // weekday states behind it. No `fill`: days done over days asked
            // for IS the meter's fraction.
            return [PostTrajectory.Chip(name: "DAYS",
                                        done: progress.value,
                                        target: progress.target,
                                        fill: nil)]
        case .distance, .sessionsOfType, .lift, .bodyWeight, .volume, .benchmark:
            guard let subject = progress.chips.first else { return [] }
            let fill = subject.target > 0
                ? min(max(subject.done / subject.target, 0), 1)
                : 0
            return [PostTrajectory.Chip(name: subject.name,
                                        done: progress.value,
                                        target: progress.target,
                                        fill: fill)]
        }
    }

    /// The whole snapshot.
    ///
    /// `weeklyKind`/`weeklyProgress` are optional together: an athlete inside
    /// a block whose current week has no materialised rung yet gets line 2
    /// and no line 3, which is a legible state. An athlete with NO ACTIVE
    /// BLOCK never reaches this function at all — spec §1: "An athlete with
    /// no active block has no line 2 and no line 3; the card is lines 1, 4,
    /// 5, 6, 7" — and `PostTrajectoryResolver` (task S2.6) returns nil there.
    static func snapshot(goal: BlockGoal,
                         page: LadderPageModel,
                         weeklyKind: WeeklyGoalKind?,
                         weeklyProgress: WeeklyGoalProgress?) -> PostTrajectory {
        let rungChips: [PostTrajectory.Chip]
        if let weeklyKind, let weeklyProgress {
            rungChips = chips(kind: weeklyKind, progress: weeklyProgress)
        } else {
            rungChips = []
        }
        return PostTrajectory(goalLine: page.headline,
                              weekNumber: page.weekNumber,
                              weekCount: page.weekCount,
                              standing: standing(goal: goal, page: page),
                              chips: rungChips)
    }
}
