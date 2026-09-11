import Foundation

// MARK: - The card's lines 2 and 3, computed once, at post time
//
// Spec §1. Plan task S2.4. PURE: everything here takes resolved values and
// returns a value. No repository, no clock, no view.

enum PostTrajectoryMath {

    /// Which of spec §1's three words the card prints.
    ///
    /// ORDERED, and the order is the argument: an outcome the block already
    /// recorded beats a ladder still being re-derived; a milestone rung that
    /// is in beats everything still ahead of it; a ladder that can no longer
    /// reach the date is `behind` however tidy the weeks behind it look; and
    /// a single missed rung is `behind` too, because spec §1's visibility
    /// ruling exists precisely so a crew can see that.
    static func standing(goal: BlockGoal, page: LadderPageModel) -> PostTrajectory.Standing {
        if goal.outcome == .met { return .met }
        if let last = page.rows.last, last.status == .met { return .met }
        if !page.reachesMilestone { return .behind }
        if page.rows.contains(where: { $0.status == .missed }) { return .behind }
        return .onTrack
    }

    /// This week's rung, as the chips the card draws — at most four, which is
    /// the number the Home strip's row is built for.
    ///
    /// TWO FAMILIES, and the split is what keeps the card honest:
    ///
    ///   * `muscleSets`, `days` and `recovery` carry DISPLAY chips. Their
    ///     `chips` array IS the strip's reading (four groups; seven day
    ///     states; stretches beside LISS minutes), so it passes through.
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
        case .muscleSets, .days, .recovery:
            return progress.chips.prefix(4).map {
                PostTrajectory.Chip(name: $0.name, done: $0.done,
                                    target: $0.target, fill: nil)
            }
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
