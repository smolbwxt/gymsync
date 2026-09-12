import Foundation

// MARK: - Resolving the trajectory, once, at post time
//
// Spec §1 lines 2-3, §6. Plan task S2.6.
//
// THE ONLY READS RLS PERMITS. `BlockGoalRepository` and
// `WeeklyGoalRepository` both answer for `auth.uid()` alone, so this runs as
// the AUTHOR, before the post exists, and the row carries the answer. A feed
// card never calls it.

enum PostTrajectoryResolver {

    /// What the composer needs to staple onto the post, or **nil when the
    /// athlete has no active block** — spec §1: "An athlete with no active
    /// block has no line 2 and no line 3".
    ///
    /// Best-effort throughout, like every other read on this path: a blip
    /// costs the post its trajectory, never the post itself.
    static func resolve(
        now: Date = .now,
        calendar: Calendar = .current,
        blockGoals: any BlockGoalRepository = LiveBlockGoalRepository(),
        weeklyGoals: any WeeklyGoalRepository = LiveWeeklyGoalRepository()
    ) async -> (trajectory: PostTrajectory, goalID: UUID, weekStartString: String)? {
        guard let goal = await blockGoals.activeGoal(),
              let page = await blockGoals.page(goalID: goal.id) else { return nil }

        // The DEVICE calendar's week, via WeekMath — the one definition of
        // "this week" on Home (`WeeklyGoal.swift`'s WeekMath note). Computing
        // a second one here would put the card's rung and the strip's rung in
        // different weeks for every user whose week does not start on Monday.
        let weekStart = WeekMath.weekStartString(now, calendar: calendar)

        var kind: WeeklyGoalKind?
        var progress: WeeklyGoalProgress?
        if let weekly = await weeklyGoals.goal(weekStart: weekStart) {
            kind = weekly.kind
            progress = await weeklyGoals.progress(for: weekly)
        }

        let trajectory = PostTrajectoryMath.snapshot(goal: goal, page: page,
                                                     weeklyKind: kind,
                                                     weeklyProgress: progress)
        return (trajectory, goal.id, weekStart)
    }
}
