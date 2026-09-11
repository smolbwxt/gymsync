import XCTest
@testable import GymSync

// MARK: - GoalDoorReadingTests
//
// ROUND 2, ITEM 1. The door reads where the athlete actually is, so spec §5.2's
// Coach line ("You're at 205 now; that's about 6 weeks of work") and spec §3.2's
// reach sentence are real in production rather than branches nothing reaches —
// which is what the final review's F4 was, and why it could not be closed by
// passing `reach:` alone.
final class GoalDoorReadingTests: XCTestCase {

    /// A fixed calendar and clock, so "four weeks out" is four weeks out in
    /// every runner timezone and the month names are the ones pinned below.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func day(_ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month,
                                           day: dayOfMonth, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// The spec's own athlete: a 205 lb bench e1RM.
    private let reading = GoalTarget(targetWeightLbs: 205)

    // MARK: - Coach's line is a reading, not a shrug

    /// The line spec §5.2 gives verbatim. Before the reader existed this said
    /// "I haven't got a reading for this yet" to every athlete alive.
    func testAReadingGivesCoachTheLineTheSpecWrote() {
        let draft = GoalMilestoneCopy.draft(preset: .strength, current: reading,
                                            today: day(9, 7), unit: .lbs,
                                            weeks: 6, calendar: calendar)
        XCTAssertEqual(
            GoalMilestoneCopy.coachLine(preset: .strength, current: reading,
                                        draft: draft, weeks: 6, unit: .lbs,
                                        subject: "Bench", calendar: calendar),
            "You're at 205 now; that's about 6 weeks of work.")
    }

    /// And with no reading it still says the honest thing rather than a zero.
    func testNoReadingStillNeverPrintsAZero() {
        let draft = GoalMilestoneCopy.draft(preset: .strength, current: GoalTarget(),
                                            today: day(9, 7), unit: .lbs,
                                            weeks: 6, calendar: calendar)
        let line = GoalMilestoneCopy.coachLine(preset: .strength,
                                               current: GoalTarget(), draft: draft,
                                               weeks: 6, unit: .lbs,
                                               subject: "Bench", calendar: calendar)
        XCTAssertEqual(line, "I haven't got a reading for this yet — I'll build to it over 6 weeks of work.")
        XCTAssertFalse(line.contains("0 "))
    }

    // MARK: - The reach, and spec §3.2's sentence

    /// **THE SPEC'S OWN EXAMPLE, END TO END.** 205 now, 225 asked for, a date
    /// four weeks out: the card's own model is "a strength block asks for about
    /// ten percent" over a default eight weeks, so four weeks buys 5 % — 215.25,
    /// short of 225 — and the shortfall at that rate is four more weeks, which
    /// is Nov 15.
    func testAnUnreachableDateGivesSpec32sSentenceVerbatim() {
        var draft = GoalMilestoneCopy.draft(preset: .strength, current: reading,
                                            today: day(9, 20), unit: .lbs,
                                            weeks: 4, calendar: calendar)
        draft.target.targetWeightLbs = 225
        draft.byDate = day(10, 18)

        let reach = GoalMilestoneCopy.reach(preset: .strength, current: reading,
                                            draft: draft, weeks: 4, unit: .lbs,
                                            today: day(9, 20), calendar: calendar)
        XCTAssertNotNil(reach)
        XCTAssertEqual(reach?.reaches, false)

        XCTAssertEqual(
            GoalMilestoneCopy.coachLine(preset: .strength, current: reading,
                                        draft: draft, weeks: 4, unit: .lbs,
                                        reach: reach, subject: "Bench",
                                        calendar: calendar),
            "Bench 225 by Oct 18 needs more than this block can safely give; "
            + "Nov 15 is the date I can build to.",
            "spec §3.2, verbatim, from the door rather than from a test fixture")
    }

    /// A block of the DEFAULT length reaches the milestone the card seeded, so
    /// the sentence does not fire. The seed and the reach are one model: ten
    /// percent over eight weeks is what `raisedLoad` asks for and what
    /// `strengthProjection` says is available.
    func testTheCardsOwnSeedIsReachableAtTheDefaultLength() {
        let draft = GoalMilestoneCopy.draft(preset: .strength, current: reading,
                                            today: day(9, 7), unit: .lbs,
                                            weeks: GoalBlockLength.defaultWeeks,
                                            calendar: calendar)
        XCTAssertNil(GoalMilestoneCopy.reach(preset: .strength, current: reading,
                                             draft: draft,
                                             weeks: GoalBlockLength.defaultWeeks,
                                             unit: .lbs, today: day(9, 7),
                                             calendar: calendar),
                     "a card that proposed something its own block cannot reach would be arguing with itself")
    }

    /// No reading, no reach — never a claim that a block reaches something
    /// nobody measured.
    func testNoReadingMeansNoReachClaim() {
        var draft = GoalMilestoneCopy.draft(preset: .strength, current: GoalTarget(),
                                            today: day(9, 20), unit: .lbs, weeks: 4,
                                            calendar: calendar)
        draft.byDate = day(10, 18)
        XCTAssertNil(GoalMilestoneCopy.reach(preset: .strength, current: GoalTarget(),
                                             draft: draft, weeks: 4, unit: .lbs,
                                             today: day(9, 20), calendar: calendar))
    }

    /// Endurance answers through `LadderMath.rampCeiling` — the SAME function
    /// the ladder page's standing uses — and takes no invented date, because a
    /// compounding climb cannot be inverted by the linear arithmetic that names
    /// one.
    func testAForcedEnduranceRampSaysSoWithoutInventingADate() {
        var draft = GoalMilestoneCopy.draft(preset: .endurance,
                                            current: GoalTarget(activity: "run",
                                                                distance: 10),
                                            today: day(9, 20), unit: .lbs, weeks: 4,
                                            calendar: calendar)
        draft.target.distance = 40
        draft.byDate = day(10, 18)

        let reach = GoalMilestoneCopy.reach(
            preset: .endurance,
            current: GoalTarget(activity: "run", distance: 10),
            draft: draft, weeks: 4, unit: .lbs, today: day(9, 20), calendar: calendar)
        XCTAssertEqual(reach?.reaches, false)
        XCTAssertNil(reach?.achievableDate)
        XCTAssertEqual(reach?.projected.distance,
                       LadderMath.rampCeiling(metric: .weeklyDistance,
                                              current: GoalTarget(activity: "run",
                                                                  distance: 10),
                                              milestone: draft.target,
                                              weeks: 4)?.distance,
                       "the door quotes the ladder page's own ceiling, not a second one")
    }

    /// Held presets name no date in the sentence (ruling 14): Consistency's
    /// `byDate` carries the block LENGTH, not a deadline.
    func testAHeldPresetsSentenceNamesNoDate() {
        var draft = GoalMilestoneCopy.draft(preset: .consistency,
                                            current: GoalTarget(days: 2),
                                            today: day(9, 20), unit: .lbs, weeks: 4,
                                            calendar: calendar)
        draft.target.days = 6
        let reach = GoalMilestoneCopy.reach(preset: .consistency,
                                            current: GoalTarget(days: 2),
                                            draft: draft, weeks: 4, unit: .lbs,
                                            today: day(9, 20), calendar: calendar)
        let line = GoalMilestoneCopy.coachLine(preset: .consistency,
                                               current: GoalTarget(days: 2),
                                               draft: draft, weeks: 4, unit: .lbs,
                                               reach: reach, calendar: calendar)
        XCTAssertTrue(line.hasSuffix("needs more than this block can safely give."), line)
        XCTAssertFalse(line.contains(" by "), "a held block has no deadline to quote")
    }

    // MARK: - The re-seed: a reading may fill a default in, never overwrite a typed one

    private func seed(_ preset: GoalPreset, current: GoalTarget,
                      weeks: Int = GoalBlockLength.defaultWeeks) -> BlockGoalDraft {
        GoalMilestoneCopy.draft(preset: preset, current: current, today: day(9, 7),
                                unit: .lbs, weeks: weeks, calendar: calendar)
    }

    /// The card opens on a default (185 → 205 asked for), the reading lands at
    /// 205, and the untouched draft becomes the one that reading implies.
    func testAnUntouchedDraftTakesTheReading() {
        let opened = seed(.strength, current: GoalTarget())
        let next = GoalMilestoneCopy.reseeded(draft: opened, openedOn: opened,
                                              preset: .strength, reading: reading,
                                              today: day(9, 7), unit: .lbs,
                                              weeks: GoalBlockLength.defaultWeeks,
                                              calendar: calendar)
        XCTAssertEqual(next.draft.target.targetWeightLbs,
                       GoalMilestoneCopy.raisedLoad(from: 205, unit: .lbs))
        XCTAssertEqual(next.draft, next.seed)
    }

    /// A draft the athlete has stepped is theirs. The seed still advances, so
    /// the NEXT reading compares against the right thing.
    func testATypedDraftIsNeverOverwritten() {
        let opened = seed(.strength, current: GoalTarget())
        var typed = opened
        typed.target.targetWeightLbs = 315

        let next = GoalMilestoneCopy.reseeded(draft: typed, openedOn: opened,
                                              preset: .strength, reading: reading,
                                              today: day(9, 7), unit: .lbs,
                                              weeks: GoalBlockLength.defaultWeeks,
                                              calendar: calendar)
        XCTAssertEqual(next.draft.target.targetWeightLbs, 315)
        XCTAssertEqual(next.seed.target.targetWeightLbs,
                       GoalMilestoneCopy.raisedLoad(from: 205, unit: .lbs))
    }

    /// **PICKING A LIFT IS NOT TYPING.** It is choosing what the question is
    /// about — and it is the act that makes a strength reading possible at all,
    /// so a card that treated it as an edit could never take the reading it
    /// just unlocked.
    func testPickingTheLiftStillLetsTheReadingSeedTheTarget() {
        let opened = seed(.strength, current: GoalTarget())
        var picked = opened
        picked.target.exerciseID = WeeklyGoalFixtures.benchPressID

        let next = GoalMilestoneCopy.reseeded(draft: picked, openedOn: opened,
                                              preset: .strength, reading: reading,
                                              today: day(9, 7), unit: .lbs,
                                              weeks: GoalBlockLength.defaultWeeks,
                                              calendar: calendar)
        XCTAssertEqual(next.draft.target.exerciseID, WeeklyGoalFixtures.benchPressID,
                       "the lift the athlete picked survives the re-seed")
        XCTAssertEqual(next.draft.target.targetWeightLbs,
                       GoalMilestoneCopy.raisedLoad(from: 205, unit: .lbs))
    }

    // MARK: - The reduction: the ladder's weeks folded into one "now"

    private func weekly(_ values: [(String, GoalTarget)]) -> [String: GoalTarget] {
        Dictionary(uniqueKeysWithValues: values)
    }

    /// A capacity takes its BEST week — one light week is not evidence the
    /// athlete got weaker.
    func testALiftReadingIsTheBestOfTheWindow() {
        let out = GoalCurrentReading.reduce(metric: .liftOneRepMax, weekly: weekly([
            ("2026-08-23", GoalTarget(targetWeightLbs: 200)),
            ("2026-08-30", GoalTarget(targetWeightLbs: 205)),
            ("2026-09-06", GoalTarget(targetWeightLbs: 190)),
        ]))
        XCTAssertEqual(out.targetWeightLbs, 205)
    }

    /// A benchmark is beaten by going DOWN, so its best is its fastest.
    func testABenchmarkReadingIsTheFastestOfTheWindow() {
        let out = GoalCurrentReading.reduce(metric: .benchmarkTime, weekly: weekly([
            ("2026-08-23", GoalTarget(targetSeconds: 3_000)),
            ("2026-08-30", GoalTarget(targetSeconds: 2_700)),
        ]))
        XCTAssertEqual(out.targetSeconds, 2_700)
    }

    /// A scale reading is a LEVEL: the latest week, not the best one.
    func testABodyWeightReadingIsTheLatestNotTheLightest() {
        let out = GoalCurrentReading.reduce(metric: .bodyWeight, weekly: weekly([
            ("2026-08-23", GoalTarget(bodyWeightLbs: 180)),
            ("2026-09-06", GoalTarget(bodyWeightLbs: 186)),
            ("2026-08-30", GoalTarget(bodyWeightLbs: 183)),
        ]))
        XCTAssertEqual(out.bodyWeightLbs, 186, "yyyy-MM-dd sorts chronologically")
    }

    /// Volume is deliberately unread: `volumeLbs` means "banked in this block"
    /// to the ladder and "the block's total" to the door's seed, and a number
    /// that means two things is worse than no number.
    func testVolumeIsDeliberatelyUnread() {
        let out = GoalCurrentReading.reduce(metric: .cumulativeVolume, weekly: weekly([
            ("2026-08-23", GoalTarget(volumeLbs: 40_000)),
        ]))
        XCTAssertNil(out.volumeLbs)
    }

    /// An empty window is an empty reading — never a zero.
    func testAnEmptyWindowReadsAsNothing() {
        XCTAssertNil(GoalCurrentReading.reduce(metric: .liftOneRepMax,
                                               weekly: [:]).targetWeightLbs)
        XCTAssertNil(GoalCurrentReading.reduce(metric: .trainingDaysPerWeek,
                                               weekly: weekly([
            ("2026-08-23", GoalTarget(days: 0)),
        ])).days, "a week with nothing logged is no reading, not a reading of zero")
    }

    // MARK: - The wiring (the defect this whole round is about)

    /// The catalog cannot reach a repository: no reader, by default.
    func testTheDefaultCardHasNoReader() {
        let card = GoalMilestoneView(preset: .strength, current: GoalTarget(),
                                     onBuild: { _ in })
        XCTAssertNil(card.reader)
    }

    /// And the door's does, and it is the ladder's own.
    func testTheDoorsCardReadsThroughTheLaddersRepository() {
        let card = GoalMilestoneView(preset: .strength, current: GoalTarget(),
                                     reader: LiveBlockGoalRepository(),
                                     onBuild: { _ in })
        XCTAssertTrue(card.reader is LiveBlockGoalRepository)
    }
}
