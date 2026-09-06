import Foundation

// MARK: - WeeklyGoalWriteRule
//
// Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
// -goal-design.md §B, OWNER ANSWER 3: "Propose only: Coach never overwrites
// a user-set goal; it proposes through the Coach line, and the user accepts
// in the editor." Plan: Stream A task A11.
//
// WHY THIS IS CODE AND NOT A TRIGGER. Coach has no server identity in this
// app. Every Coach write — `WeekBooker.book`, `ProgramBuilder.build` — runs
// through the app's own Supabase client on the ATHLETE'S OWN JWT, so a
// database trigger could not tell a Coach-originated UPDATE from a
// user-originated one: both arrive as `auth.uid()`. The distinction lives in
// the `source` column and in this one function that consults it before
// writing. `20260906000001_weekly_goals.sql`'s header says the same thing
// from the other side.
//
// One function, so both write paths cannot drift, and pure, so the rule is
// three unit tests rather than an integration story.

enum WeeklyGoalWriteRule {

    /// May Coach write `detected` over `existing`?
    ///
    /// - no row yet → **yes**. A week with no goal is the state detection
    ///   exists to fill.
    /// - a `coach` row → **yes**. Coach's own earlier reading, superseded by
    ///   a newer one — a re-booked week or a rebuilt block should re-derive.
    /// - a `user` row → **NO**, and this is the whole of owner answer 3. The
    ///   athlete has spoken for this week. Coach's recourse is
    ///   `LiveWeeklyGoalRepository.propose(weekStart:)`, which returns the
    ///   would-be goal for the Coach tile's line and writes nothing.
    ///
    /// `detected` is taken as a parameter it does not read, deliberately:
    /// the rule is about PROVENANCE, not about content, and a future
    /// temptation to add "…unless the new one is better" has to come through
    /// this signature and get argued for.
    static func shouldOverwrite(existing: WeeklyGoal?, detected: WeeklyGoal) -> Bool {
        guard let existing else { return true }
        return existing.source == .coach
    }
}
