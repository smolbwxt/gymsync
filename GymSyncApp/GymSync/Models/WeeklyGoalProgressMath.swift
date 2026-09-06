import Foundation

// MARK: - WeeklyGoalProgressMath
//
// Plan: docs/superpowers/plans/2026-09-06-home-v3-production-plan.md.
// Stream A task A4 owns this type and fills in the per-kind progress
// resolution that produces `WeeklyGoalProgress`. Task **B1** seeds it with
// the ONE function the plan moved here up front:
//
//   > Also in this commit: move `daysThisWeek` (:950) into
//   > `WeeklyGoalProgressMath` (A4's requirement) and call it here, so the
//   > streak tile and the goal strip cannot drift.
//
// STREAM A: this file will collide with yours at integration I1. Keep A4's
// version and re-point `HomeView.daysThisWeek`'s call site at it — the body
// below is a verbatim move of `HomeView.daysThisWeek`, so there is no
// behaviour to preserve beyond the rule itself.
//
// THE WEEK IS THE DEVICE CALENDAR'S WEEK. `isDate(_:equalTo:toGranularity:
// .weekOfYear)` honours the user's own `firstWeekday`, which is the rule
// production has always used and the rule `WeekMath.startOfWeek` was written
// to agree with (`WeeklyGoalModelTests
// .testWeekAgreesWithHomeViewsWeekOfYearGranularity` pins that agreement for
// a year of dates under `firstWeekday` 1 and 2). The design's agreement law
// — the goal strip's right-hand read and the streak tile describe the same
// week — is only true while those two stay one rule.
enum WeeklyGoalProgressMath {

    /// DISTINCT training days in `now`'s week (solo included — they count
    /// toward streaks since 20260803000005). Days, not sessions (owner
    /// 2026-08-12: the goal line reads "1/4 days this week") — two sessions
    /// on the same day fill one slot.
    static func daysThisWeek(completed sessions: [WorkoutSession],
                             now: Date = .now,
                             calendar: Calendar = .current) -> Int {
        let days = sessions.compactMap { session -> Date? in
            guard let completedAt = session.completedAt,
                  calendar.isDate(completedAt, equalTo: now, toGranularity: .weekOfYear)
            else { return nil }
            return calendar.startOfDay(for: completedAt)
        }
        return Set(days).count
    }
}
