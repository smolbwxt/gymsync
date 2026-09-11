import Foundation
import SwiftUI

// MARK: - The goal-first fixture world
//
// Plan: docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md,
// tasks C5 and D7. **SHARED FILE, BUILT IN TWO PLACES** — Stream C creates it
// for the door's frames, Stream D extends it for the ladder's; integration
// task I1 resolves the collision by concatenating the two halves. The two
// halves declare no symbols in common, so the merge is a paste rather than a
// reconciliation.
//
// HERMETIC, for the reason `HomeV2Fixtures.swift:1-10` and
// `WeeklyGoalFixtures.swift:1-14` both give: a catalog capture must be
// identical on every run, so there is no `AppState`, no repository, no
// `Date.now` and no network anywhere below. Global constraint 7 states it as a
// rule — "no `Date.now` and no live repository reachable from a catalog
// builder" — and these frames obey it by holding integers, strings and two
// dates that belong to `StubBlockGoalRepository`.
//
// ONE WORLD (controller ruling 3). The clock is the stub's own block start and
// the lifts are `WeeklyGoalFixtures.focusLifts`, whose bench press IS
// `StubBlockGoalRepository.fixtureExerciseID`. So the strength card's 205 → 225
// by Oct 18 and the ladder page's "Bench 225 by Oct 18" describe one block
// rather than two that read alike.

// MARK: - Stream C's half — the door (goal screen + three milestone cards)

enum GoalFixtures {

    /// THE CLOCK, and it is a fixture: `StubBlockGoalRepository
    /// .fixtureCreatedAt` — Monday 2026-08-24 at noon UTC, the day the
    /// fixture block starts. Noon rather than midnight is the stub's own
    /// hard-won detail: a device-local formatter in the Americas printed a
    /// midnight-UTC date as the day before.
    static let today = StubBlockGoalRepository.fixtureCreatedAt

    /// The display unit, pinned, so every frame reads `lbs` whatever unit the
    /// capturing simulator's account happens to carry — the same reason
    /// `WeeklyGoalFixtures.editorUnit` exists. `lbs`, not `lb`:
    /// `WeightUnit.label` is the raw value, and the frames print what it
    /// says.
    static let unit: WeightUnit = .lbs

    /// The picker's rows: the block's focus lifts, shared with the weekly
    /// goal editor's frames so a lift that reads as Bench Press on one
    /// capture reads as Bench Press on the other.
    static let lifts = WeeklyGoalFixtures.focusLifts

    // MARK: The three milestone cards' current state

    /// `goal-milestone-strength` — the athlete is at 205 on the bench.
    ///
    /// The card SEEDS 225 from it (ten percent, snapped to a loadable
    /// increment) and Oct 18 (the last day of an eight-week block that starts
    /// on `today`), which is the spec's own worked milestone and the stub's
    /// own fixture goal. Neither number is written here: a fixture that
    /// hard-coded the seed would capture a frame the code cannot produce.
    static let strengthCurrent = GoalTarget(
        exerciseID: WeeklyGoalFixtures.benchPressID, targetWeightLbs: 205)

    /// `goal-milestone-body-composition` — the athlete weighs 190.
    ///
    /// The card seeds the milestone from the SAFE RATE (0.75 %/wk, the
    /// midpoint of spec §2.3's 0.5-1 % band, compounded over the eight weeks
    /// and snapped to the pound a scale is read at), so the frame shows
    /// **179 lbs**, not a literal. The plan's C5 table describes this frame as
    /// "190 → 178"; 179 is what the documented rate actually produces, and the
    /// rate is the thing that must be right — a seed hard-coded to match prose
    /// would be a frame nobody could reproduce.
    static let bodyCompositionCurrent = GoalTarget(bodyWeightLbs: 190)

    /// `goal-milestone-recovery` — nothing measured, which is the honest
    /// state for a metric whose readers arrive with the watch (spec §2.2:
    /// LISS minutes and the stretching count are both NEW). The card seeds
    /// its two companion steppers from their own defaults and Coach says the
    /// block is HELD rather than printing a zero.
    static let recoveryCurrent = GoalTarget()

    /// SIX WEEKS, the plan's own number for this frame. Recovery's only
    /// milestone lever is the block length (spec §5.2), so this is the one
    /// input that makes the frame the frame.
    static let recoveryWeeks = 6

    // MARK: The benchmark picker's routines
    //
    // Values, never a fetch. `Routine`'s own memberwise initializer, with
    // fixed ids and the fixture clock, so a screenshot diff never trips on a
    // uuid or a timestamp.

    static let murphID = UUID(uuidString: "00000000-0000-0000-0000-0000000000d1") ?? UUID()
    static let fran5kID = UUID(uuidString: "00000000-0000-0000-0000-0000000000d2") ?? UUID()

    static let routines: [Routine] = [
        Routine(id: murphID, ownerID: StubBlockGoalRepository.fixtureUserID,
                name: "Murph", description: "Hero WOD",
                visibility: "private", createdAt: today, updatedAt: today),
        Routine(id: fran5kID, ownerID: StubBlockGoalRepository.fixtureUserID,
                name: "Benchmark 5K", description: "Time trial",
                visibility: "private", createdAt: today, updatedAt: today),
    ]
}

// MARK: - Stream D's half — the ladder page + the block strip

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
    /// **WHERE THIS LADDER ACTUALLY ARRIVES.** Coach's line and the last rung
    /// are one number stated twice, so they are one constant here (final
    /// review F6): the frame used to print "This ladder reaches 218" above a
    /// ladder whose last row visibly read `2 × 1 at 225 / ≈ 232 e1RM`, and the
    /// whole point of the reach sentence is that the number is where the ramp
    /// gets to. Production's wording is `LadderMath.page`'s and was always
    /// right; the fixture was the liar, and it is the artifact the owner reads
    /// as the product.
    static let behindReachesE1RM = 218

    static let behind: LadderPageModel = {
        var page = StubBlockGoalRepository.fixturePage
        page.coachLine = "This ladder reaches \(behindReachesE1RM) — move the date?"
        page.reachesMilestone = false
        // THE TAIL IS LOWER THAN THE BLOCK'S OWN, and that is the story rather
        // than a second fixture: week 1 was overridden and week 2 missed, so
        // the re-derived rungs start from ACTUALS (spec §3.5, "a missed week
        // does not leave a hole to catch up; the ladder moves") and top out
        // short of the 225 milestone. Week 6 is left alone — it is the wave's
        // deload, and a deload is the block's shape, not a rung that climbs.
        page.rows = page.rows.map { row in
            switch row.weekNumber {
            case 1: return row.with(status: .overridden)
            case 2: return row.with(status: .missed)
            case 4: return row.with(targetText: "4 × 3 at 190", implication: "≈ 207 e1RM")
            case 5: return row.with(targetText: "4 × 3 at 195", implication: "≈ 212 e1RM")
            case 7: return row.with(targetText: "3 × 2 at 205", implication: "≈ 216 e1RM")
            case 8: return row.with(targetText: "2 × 1 at \(behindReachesE1RM)",
                                    implication: "≈ \(behindReachesE1RM) e1RM")
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
    /// instead of five.
    ///
    /// **`fileprivate`, in the language rather than in a comment** (task
    /// review finding 8). It used to be internal, and therefore visible to
    /// every production file, while its own doc comment claimed to be
    /// fixture-only; both call sites are in this file. It also removes any
    /// chance of a duplicate-declaration collision when I1 concatenates
    /// Stream C's half of this file.
    fileprivate func with(status: RungStatus) -> LadderRow {
        LadderRow(weekNumber: weekNumber, weekStartString: weekStartString,
                  targetText: targetText, implication: implication,
                  status: status, isDeload: isDeload, note: note)
    }

    /// The same row prescribing something else — what a re-ladder from actuals
    /// does to a week still ahead (final review F6).
    fileprivate func with(targetText: String, implication: String?) -> LadderRow {
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
