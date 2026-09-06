import SwiftUI

// MARK: - The weekly goal's fixture world
//
// Plan: docs/superpowers/plans/2026-09-06-home-v3-production-plan.md, task
// C4. Nine catalog ids — seven strip states and two editor states — so the
// design round sees every kind the goal system can be in, rendered by CI,
// before any of it reaches a device.
//
// HERMETIC, for the reason `HomeV2Fixtures.swift:1-10` gives: a catalog
// capture must be identical on every run, so there is no `AppState`, no
// repository, no `Date.now` and no network anywhere below. Even the editor's
// clock is a fixture integer, because a by-date picker framed on the real
// clock drifts by a day every day and turns a screenshot diff into noise.

/// The page a goal-strip frame is judged on: the greeting header, then the
/// strip, on the page ground.
///
/// A strip floating alone on a blank screen is not a reviewable frame (the
/// plan says so). `HomeV3Frame` — the one the ten variations share — is
/// `private` to `HomeV3Variations.swift` and carries the one button and the
/// solo row with it; those belong to a COMPOSITION being judged, and these
/// seven frames judge a STRIP. So the page is the header, the strip, and
/// nothing else competing for the eye.
///
/// Geometry is the v3 page's: `HomeV2GreetingHeader` with its own 16 pt
/// margins, then 16 pt page margins and the 12 pt block gap
/// (`HomeV3Variations`' `homeV3Block()`), over `theme.bg`.
struct WeeklyGoalStripFrame: View {
    @Environment(\.gsTheme) private var theme

    let kind: WeeklyGoalKind?
    let progress: WeeklyGoalProgress

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HomeV2GreetingHeader(greeting: HomeV2Fixtures.greeting,
                                     dateLine: HomeV2Fixtures.dateLine,
                                     initials: HomeV2Fixtures.avatarInitials)

                HomeWeeklyGoalStrip(kind: kind, progress: progress)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
    }
}

enum WeeklyGoalFixtures {

    // MARK: - The strip

    /// `home-goal-strip-muscle-sets`.
    ///
    /// The chips are `HomeV2Fixtures.coachTargets` EXACTLY — the plan's
    /// requirement — so this capture and the approved 08a frame agree about
    /// the week rather than telling two stories about it. The KICKER is
    /// production's `COACH'S GOAL`, where 08a keeps the retired
    /// `COACH'S TARGETS` it was approved with (Task 0's review, finding 3,
    /// schedules that re-shoot for I1). This id is the one that shows what
    /// ships.
    static let muscleSets = WeeklyGoalProgress(
        chips: HomeV2Fixtures.coachTargets,
        rightHandRead: "1 SESSION LEFT",
        kicker: "THIS WEEK · COACH'S GOAL")

    /// `home-goal-strip-met` — the same four groups, at target.
    ///
    /// The right-hand read is EMPTY on purpose. The design's met kicker is
    /// `GOAL MET · {n} DAYS LEFT`, which has already said how much week is
    /// left; repeating it 200 pt to the right on a strip 24 pt tall would
    /// state one fact twice.
    static let met = WeeklyGoalProgress(
        chips: [
            .init(name: "CHEST", done: 12, target: 12, isNext: false),
            .init(name: "BACK", done: 12, target: 12, isNext: false),
            .init(name: "LEGS", done: 12, target: 12, isNext: false),
            .init(name: "ARMS", done: 8, target: 8, isNext: false),
        ],
        met: true,
        rightHandRead: "",
        kicker: "GOAL MET · 2 DAYS LEFT")

    /// `home-goal-strip-distance` — the design's own `9.4 / 15 mi`.
    ///
    /// The subject chip (`HomeWeeklyGoalStrip`'s "The subject chip" note)
    /// names the activity, which chooses `figure.run`, and gives the meter
    /// its fill. `unitLabel` is stamped rather than left to the strip's
    /// fallback, so this frame renders `mi` whatever unit the capturing
    /// simulator's account happens to be set to.
    static let distance = WeeklyGoalProgress(
        chips: [.init(name: "RUN", done: 9.4, target: 15, isNext: false)],
        value: 9.4,
        target: 15,
        unitLabel: "mi",
        rightHandRead: "3 DAYS LEFT",
        kicker: "THIS WEEK · COACH'S GOAL")

    /// `home-goal-strip-sessions` — `2 of 3 HIIT`, the design's line.
    static let sessions = WeeklyGoalProgress(
        chips: [.init(name: "HIIT", done: 2, target: 3, isNext: false)],
        value: 2,
        target: 3,
        rightHandRead: "3 DAYS LEFT",
        kicker: "THIS WEEK · COACH'S GOAL")

    /// `home-goal-strip-days` — the CREW NIGHT's own week, chip for chip
    /// (`HomeV2Fixtures.crewNight.weekDays`): Monday, Tuesday and Thursday
    /// trained, Friday today, three of four in the bank.
    ///
    /// Shared deliberately with that world rather than invented, because the
    /// artifact puts this frame beside 08a and the streak tile on 08a counts
    /// the same week. `done ≥ 1` is trained, `target ≥ 1` is booked, and the
    /// single `isNext` is today — the mapping `HomeWeeklyGoalStrip.dayState`
    /// documents.
    static let days = WeeklyGoalProgress(
        chips: [
            .init(name: "M", done: 1, target: 1, isNext: false),
            .init(name: "T", done: 1, target: 1, isNext: false),
            .init(name: "W", done: 0, target: 0, isNext: false),
            .init(name: "T", done: 1, target: 1, isNext: false),
            .init(name: "F", done: 0, target: 0, isNext: true),
            .init(name: "S", done: 0, target: 0, isNext: false),
            .init(name: "S", done: 0, target: 0, isNext: false),
        ],
        value: 3,
        target: 4,
        rightHandRead: "3 DAYS LEFT",
        kicker: "THIS WEEK · COACH'S GOAL")

    /// `home-goal-strip-lift` — the plan's own `205 → 225`, six weeks out.
    ///
    /// The subject chip carries the BLOCK-RELATIVE pair: the block opened at
    /// 185, so 205 is 20 of the 40 lb it asks for, and the meter reads half
    /// full. A raw 205 / 225 would draw 91 % on the first day of a block,
    /// which is the whole reason the plan's A5 measures a lift's meter from
    /// where the block started.
    ///
    /// The kicker says `YOUR GOAL`, so the seven strip frames carry both
    /// kicker branches between them.
    static let lift = WeeklyGoalProgress(
        chips: [.init(name: "BENCH PRESS", done: 20, target: 40, isNext: false)],
        value: 205,
        target: 225,
        unitLabel: "lb",
        rightHandRead: "6 WEEKS LEFT",
        kicker: "THIS WEEK · YOUR GOAL")

    // MARK: - The editor

    /// A fixed id, so `WeeklyGoal.id` is stable across runs and a screenshot
    /// diff never trips on it — `StubWeeklyGoalRepository.fixtureUserID`'s
    /// own reasoning, with a different literal so the two worlds stay
    /// distinguishable in a log.
    static let editorUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000c4") ?? UUID()

    /// 2026-09-06T12:00:00Z. A fixture, not a clock: it stamps `setAt` and
    /// frames the by-date picker, and a real clock would move the lift
    /// frame's date every day the suite runs.
    static let editorToday = Date(timeIntervalSince1970: 1_788_696_000)

    /// Six weeks past `editorToday`, the default a lift goal is written
    /// against.
    static let editorByDate = Date(timeIntervalSince1970: 1_788_696_000 + 6 * 7 * 24 * 60 * 60)

    /// The Monday of the fixture week, in the DATE column's own format.
    static let editorWeekStart = "2026-08-31"

    /// The profile's standing weekly session goal — the number the `days`
    /// stepper seeds from and edits. Four, matching `HomeV2Fixtures
    /// .crewNight.weeklyGoal`, so a frame showing the days lever and a frame
    /// showing the streak tile agree.
    static let editorWeeklySessionGoal = 4

    /// The display unit, pinned. Both editor frames render `MILES` and `lb`
    /// on any simulator rather than on whichever settings row the capturing
    /// account happens to carry — the last input that was a global read
    /// rather than a value.
    static let editorUnit: WeightUnit = .lbs

    static let benchPressID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b1") ?? UUID()
    static let backSquatID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b2") ?? UUID()
    static let deadliftID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b3") ?? UUID()

    /// The block's focus lifts, which the picker shows above the catalog.
    /// The frames pass `loadsCatalog: false`, so these three ARE the picker
    /// in a capture — which is the honest thing to show anyway: a design
    /// round judging a picker of 1,300 alphabetical rows learns nothing the
    /// first three do not tell it.
    static let focusLifts: [WeeklyGoalEditorSheet.LiftOption] = [
        .init(id: benchPressID, name: "Bench Press", detail: "FOCUS LIFT"),
        .init(id: backSquatID, name: "Back Squat", detail: "FOCUS LIFT"),
        .init(id: deadliftID, name: "Deadlift", detail: "FOCUS LIFT"),
    ]

    /// `home-goal-editor` — the muscle-sets editor on a goal COACH set, so
    /// the header carries the design's standing copy line ("Coach set this
    /// from your block…"). The targets are the same four the strip frames
    /// read, so the two ids describe one week.
    static let editorGoal = WeeklyGoal(
        userID: editorUserID,
        weekStartString: editorWeekStart,
        kind: .muscleSets,
        params: WeeklyGoalParams(muscleTargets: ["chest": 12, "back": 12,
                                                 "legs": 12, "arms": 8],
                                 targetSource: "routines"),
        source: .coach,
        setAt: editorToday)

    /// `home-goal-editor-lift` — the lift editor on a goal the PERSON set.
    ///
    /// `source = .user` is what makes this the frame that can carry a
    /// proposal: Coach may never overwrite a user goal (owner answer 3), so
    /// on a user goal it asks instead. The two editor ids therefore capture
    /// both header branches between them — the standing copy line on
    /// `home-goal-editor`, Coach's suggestion and its `ACCEPT` here.
    static let editorLiftGoal = WeeklyGoal(
        userID: editorUserID,
        weekStartString: editorWeekStart,
        kind: .lift,
        params: WeeklyGoalParams(exerciseID: benchPressID,
                                 targetWeightLbs: 225,
                                 byDate: editorByDate),
        source: .user,
        setAt: editorToday)

    /// Coach's standing suggestion. One sentence, and it names what it would
    /// switch the week to rather than gesturing at a change.
    ///
    /// It carries its LEVERS as well as its kind — the same four targets
    /// `editorGoal` holds, which are the same four every strip frame reads —
    /// so `ACCEPT` lands on a filled-in goal rather than on six rows reading
    /// zero. Nothing saves on accept: `ACCEPT` seeds, `SAVE THIS WEEK'S
    /// GOAL` commits (owner answer 3).
    static let editorProposal = WeeklyGoalEditorSheet.Proposal(
        kind: .muscleSets,
        sentence: "Coach suggests muscle sets this week — your block is asking for volume, not one lift.",
        params: WeeklyGoalParams(muscleTargets: ["chest": 12, "back": 12,
                                                 "legs": 12, "arms": 8]))
}
