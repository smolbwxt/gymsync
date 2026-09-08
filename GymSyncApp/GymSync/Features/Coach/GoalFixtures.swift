import SwiftUI

// MARK: - The goal-first fixture world
//
// Plan: docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md,
// tasks C5 and D7. **SHARED FILE, BUILT IN TWO PLACES** — Stream C creates it
// for the door's frames, Stream D extends it for the ladder's; integration
// task I1 resolves the collision by concatenating the two halves. Everything
// below is Stream D's half, and it adds no type of its own so the merge is a
// paste rather than a reconciliation.
//
// HERMETIC, for the reason `HomeV2Fixtures.swift:1-10` gives: a catalog
// capture must be identical on every run, so there is no `AppState`, no
// repository, no `Date.now` and no network anywhere below. Every ladder here
// is DERIVED from `StubBlockGoalRepository.fixturePage` — controller ruling
// 3's one world — rather than retyped, so the three ladder frames and every
// other surface that renders the stub describe one block.

enum LadderFixtures {

    /// `ladder-behind` — the same eight-week bench block, gone wrong.
    ///
    /// Week 1 the athlete set themselves (`overridden`), week 2 they missed,
    /// week 3 is where they are. That is a coherent story rather than a
    /// sampler: the override and the miss are WHY the re-derived ladder now
    /// falls short, which is why Coach is proposing a new date at all (spec
    /// §3.5).
    ///
    /// Coach's line is the spec's own words, verbatim, and
    /// `reachesMilestone: false` is what turns it accent — an invitation to
    /// act, which is one of accent's jobs (design rule 2).
    static let behind: LadderPageModel = {
        var page = StubBlockGoalRepository.fixturePage
        page.coachLine = "This ladder reaches 218 — move the date?"
        page.reachesMilestone = false
        page.rows = page.rows.map { row in
            switch row.weekNumber {
            case 1: return row.with(status: .overridden)
            case 2: return row.with(status: .missed)
            default: return row
            }
        }
        return page
    }()

    /// `ladder-met` — the block finished and the milestone landed.
    ///
    /// Every rung `met`, so the page is one column of green; the week is 8 of
    /// 8, because a ladder whose every rung is met is not sitting in week 3.
    /// The date line stays the milestone's own — the ladder does not rewrite
    /// history once it is history.
    static let met: LadderPageModel = {
        var page = StubBlockGoalRepository.fixturePage
        page.coachLine = "Met — you hit 225 on October 11."
        page.weekNumber = page.weekCount
        page.rows = page.rows.map { $0.with(status: .met) }
        return page
    }()
}

extension LadderRow {
    /// The same row with a different standing. `LadderRow` is Task 0's frozen
    /// surface and every field is `let`, so a fixture that wants one status
    /// changed has to rebuild the row — this keeps that rebuild in one place
    /// instead of five, and it is `fileprivate`-adjacent by intent: only the
    /// fixtures above use it.
    func with(status: RungStatus) -> LadderRow {
        LadderRow(weekNumber: weekNumber, weekStartString: weekStartString,
                  targetText: targetText, implication: implication,
                  status: status, isDeload: isDeload, note: note)
    }
}

enum GoalStripFixtures {

    /// `home-goal-strip-block` — the shipped muscle-sets strip with the
    /// BLOCK kicker.
    ///
    /// DERIVED from `WeeklyGoalFixtures.muscleSets` and changing exactly one
    /// field, so this frame and `home-goal-strip-muscle-sets` differ **only**
    /// in the kicker — which is the whole of what spec §6 changes about the
    /// strip ("unchanged shape; it renders the current rung. The kicker gains
    /// the block context"). Retyping the four chips would have let the two
    /// frames drift and turned a one-line change into a redesign nobody
    /// asked for.
    ///
    /// The kicker string is A14's job in production
    /// (`LiveWeeklyGoalRepository.progress(for:)` computes it); this is the
    /// literal that shows what it will read, and Stream D renders whatever
    /// `progress.kicker` holds without computing any of it.
    static let block: WeeklyGoalProgress = {
        var progress = WeeklyGoalFixtures.muscleSets
        progress.kicker = "WEEK 3 OF 8 · COACH'S GOAL"
        return progress
    }()
}
