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
// Two pure functions — may Coach WRITE over what is there, and may a READ
// trigger detection at all — so every write path consults one implementation
// and the rules are unit tests rather than an integration story.

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

    /// A LADDER WEEK IS NOT DETECTION'S TO FILL.
    ///
    /// `WeekBooker.book` calls `writeDetectedGoal` after every booking, and
    /// `WeeklyGoalWriteRule.shouldOverwrite` says yes to a `coach` row — which
    /// is right for a row Coach's own detector wrote and wrong for a row the
    /// block's LADDER materialised (task A10, also `source = coach`). Booking a
    /// week of an active block would otherwise replace week 3's prescribed rung
    /// with a freshly detected goal, and the strip and the ladder page would
    /// then disagree about the same seven days.
    ///
    /// One question, asked here rather than in `WeekBooker`, because
    /// `WeekBooker` has no business knowing what a ladder is.
    static func isLadderWeek(_ existing: WeeklyGoal?) -> Bool {
        existing?.params.goalID != nil
    }

    /// May a READ of `weekStart` trigger detection (final review finding 1)?
    ///
    /// The design's rule 3 says a week is "never empty", but until this
    /// existed nothing in the app ran detection except `WeekBooker.book` and
    /// `ProgramBuilder.build` — so an athlete with no active block who never
    /// booked a week saw the strip's invitation forever. Home's fetch asks
    /// this question when its read comes back empty.
    ///
    /// - a row already exists → **no**. Detection fills an absence; it does
    ///   not second-guess a row, and `shouldOverwrite` is the rule that
    ///   governs the row that IS there.
    /// - not the current week → **no**, and this is the half that is easy to
    ///   get wrong. Reading a week is not a reason to WRITE it: only the
    ///   week Home is actually rendering may be filled from a read, so a
    ///   future week stays `WeekBooker`'s to stamp at booking time and a
    ///   past week is never back-filled by someone scrolling to it.
    /// - otherwise → **yes**.
    ///
    /// Pure, and separate from the fetch that acts on it, so both halves of
    /// the rule are unit tests rather than an integration story.
    static func shouldDetectOnRead(existing: WeeklyGoal?,
                                   weekStart: String,
                                   currentWeekStart: String) -> Bool {
        guard existing == nil else { return false }
        return weekStart == currentWeekStart
    }
}

// MARK: - The seam Coach's write paths take

/// What `WeekBooker` and `ProgramBuilder` need from the goal repository, and
/// nothing else.
///
/// A protocol OF ITS OWN rather than the Task 0.2 `WeeklyGoalRepository`,
/// for two reasons. That protocol is the FROZEN interface three streams read
/// and this stream may not widen it — and `writeDetectedGoal` is not on it,
/// because detection is Stream A's concern and no UI stream calls it. So the
/// seam that restores testability is this one-method protocol, declared next
/// to the rule it enforces.
///
/// Without it, both Coach paths constructed `LiveWeeklyGoalRepository()`
/// inline: any future unit test of `book(...)` or `build(...)` would perform
/// six network fetches and a write, and the branch writes real
/// `weekly_goals` rows from these paths (integration has since swapped the read
/// binding off the stub.
protocol WeeklyGoalCoachWriter: Sendable {
    /// Detect this week's goal and persist it only if
    /// `WeeklyGoalWriteRule` allows. Returns the goal now in effect.
    @discardableResult
    func writeDetectedGoal(weekStart: String) async -> WeeklyGoal?
}

/// Writes nothing and answers nothing — what a test injects when it wants to
/// exercise a booking or a build without touching the network.
struct NoOpWeeklyGoalCoachWriter: WeeklyGoalCoachWriter {
    @discardableResult
    func writeDetectedGoal(weekStart: String) async -> WeeklyGoal? { nil }
}

// MARK: - The seam plan item 6's detect-on-read takes

/// What `LiveWeeklyGoalRepository.detectIfMissing` asks the BLOCK side before
/// it detects a goal of its own (controller ruling on plan item 6; final
/// review F1).
///
/// A protocol, and for the same two reasons `WeeklyGoalCoachWriter` above is
/// one. The live block repository is Supabase all the way down, so a direct
/// call would make the ruling's own test — "a user with an active goal, a
/// `weekly_goals` row for last week only, and a changed actual →
/// `detectIfMissing(thisWeek)` returns a `source = coach` row whose rung
/// moved" — an integration story rather than a unit test. And it keeps the
/// dependency pointing one way: the weekly repository knows a ladder may have
/// an answer, not how a ladder is built.
protocol LadderWeekSource: Sendable {
    /// The row this athlete's active block says `weekStart` is: re-laddered
    /// from actuals and materialised into `weekly_goals`, through
    /// `WeeklyGoalWriteRule` like every other Coach write.
    ///
    /// nil when there is no active block, no goal on it, or nothing could be
    /// written — and nil is what sends the caller to plain detection.
    func ladderWeek(weekStart: String) async -> WeeklyGoal?
}

/// Answers nothing — the binding for a repository with no ladder behind it,
/// and what a test injects to prove plain detection still runs untouched.
struct NoLadderWeekSource: LadderWeekSource {
    func ladderWeek(weekStart: String) async -> WeeklyGoal? { nil }
}
