import Foundation

// MARK: - The door's fixture world
//
// Plan task C5. Four catalog ids — the goal screen and three milestone cards
// — so the design round sees the front door rendered by CI before any of it
// reaches a device.
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
