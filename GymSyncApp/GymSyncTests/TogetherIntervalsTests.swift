import XCTest
@testable import GymSync

/// Together's interval plan and its clock — plan task S9 (spec §3.3, owner
/// decisions 1 and 13).
///
/// The screen is value-in over these two pure functions, which is what lets
/// frame 140 render the shipping view. What the frame cannot prove is what
/// the plan does with a routine that prescribes nothing, or with a zone that
/// prescribes no minutes — the two shapes real routines actually have.
final class TogetherIntervalsTests: XCTestCase {

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    private func row(_ id: UUID, _ name: String,
                     zone: Int?, minutes: Int?) -> (id: UUID, name: String,
                                                    cardioZone: Int?, cardioMinutes: Int?) {
        (id: id, name: name, cardioZone: zone, cardioMinutes: minutes)
    }

    // MARK: - plan(from:)

    func testCardioRowsBecomeIntervalsInOrder() {
        let plan = TogetherIntervals.plan(from: [
            row(a, "Assault bike", zone: 4, minutes: 1),
            row(b, "Easy spin", zone: 2, minutes: 1),
        ])
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan.map(\.id), [a, b])
        XCTAssertEqual(plan[0].detail, "Z4 · 1 min")
        XCTAssertEqual(plan[1].zone, 2)
    }

    /// A ROW WITHOUT MINUTES IS NOT AN INTERVAL. `cardio_zone` alone
    /// prescribes an effort and no duration, and a clock cannot count down an
    /// effort — the row is skipped rather than given a made-up length.
    func testAZoneWithNoMinutesIsSkipped() {
        let plan = TogetherIntervals.plan(from: [
            row(a, "Assault bike", zone: 4, minutes: 2),
            row(b, "Row", zone: 3, minutes: nil),
            row(c, "Back squat", zone: nil, minutes: nil),
        ])
        XCTAssertEqual(plan.map(\.id), [a])
    }

    /// Zero minutes is not a duration either.
    func testAZeroMinuteRowIsSkipped() {
        let plan = TogetherIntervals.plan(from: [row(a, "Row", zone: 3, minutes: 0)])
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].id, TogetherIntervals.openIntervalID)
    }

    /// A routine with no cardio at all renders ONE OPEN INTERVAL — the honest
    /// shape of "we are all working until somebody says stop" — rather than a
    /// structure nobody prescribed.
    func testARoutineWithNoCardioIsOneOpenInterval() {
        let plan = TogetherIntervals.plan(from: [
            row(a, "Back squat", zone: nil, minutes: nil),
            row(b, "Romanian deadlift", zone: nil, minutes: nil),
        ])
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].id, TogetherIntervals.openIntervalID)
        XCTAssertEqual(plan[0].name, "Work")
        XCTAssertNil(plan[0].minutes)
        XCTAssertEqual(plan[0].detail, "")
    }

    func testAnEmptyRoutineIsAlsoOneOpenInterval() {
        XCTAssertEqual(TogetherIntervals.plan(from: []).count, 1)
    }

    /// The open interval's id is FIXED, so a re-render is the same interval
    /// and not a new one that would reset the crew's timeline.
    func testTheOpenIntervalsIdIsStable() {
        let first = TogetherIntervals.plan(from: [])
        let second = TogetherIntervals.plan(from: [])
        XCTAssertEqual(first[0].id, second[0].id)
    }

    // MARK: - position(in:elapsed:)

    private var twelveOneMinuteIntervals: [TogetherIntervals.Interval] {
        (0..<12).map {
            TogetherIntervals.Interval(id: UUID(), name: "Interval \($0)",
                                       zone: 3, minutes: 1)
        }
    }

    func testThePositionWalksTheIntervalsByTheirOwnLengths() {
        let plan = twelveOneMinuteIntervals
        XCTAssertEqual(TogetherIntervals.position(in: plan, elapsed: 0)?.index, 0)
        XCTAssertEqual(TogetherIntervals.position(in: plan, elapsed: 59)?.index, 0)
        XCTAssertEqual(TogetherIntervals.position(in: plan, elapsed: 60)?.index, 1)
        XCTAssertEqual(TogetherIntervals.position(in: plan, elapsed: 330)?.index, 5)
    }

    func testTheRemainderAndTheProgressAgree() {
        let plan = twelveOneMinuteIntervals
        let at42 = TogetherIntervals.position(in: plan, elapsed: 42)
        XCTAssertEqual(at42?.remaining, 18)
        XCTAssertEqual(at42?.elapsedInInterval, 42)
        XCTAssertEqual(at42?.progress ?? 0, 42.0 / 60.0, accuracy: 0.0001)
    }

    /// PAST THE END, the crew is on the LAST interval with nothing left. A
    /// session that overruns its plan has not started a thirteenth interval.
    func testPastTheEndTheClockStopsRatherThanWraps() {
        let plan = twelveOneMinuteIntervals
        let over = TogetherIntervals.position(in: plan, elapsed: 60 * 60)
        XCTAssertEqual(over?.index, 11)
        XCTAssertEqual(over?.remaining, 0)
        XCTAssertEqual(over?.progress, 1)
    }

    /// An OPEN interval swallows the rest of the clock and counts UP: it has
    /// no end to count down to, and a zero would claim one.
    func testAnOpenIntervalCountsUpForever() {
        let plan = TogetherIntervals.plan(from: [])
        let position = TogetherIntervals.position(in: plan, elapsed: 400)
        XCTAssertEqual(position?.index, 0)
        XCTAssertNil(position?.remaining)
        XCTAssertEqual(position?.elapsedInInterval, 400)
        XCTAssertEqual(position?.progress, 0)
    }

    /// A clock that has gone backwards has not run backwards.
    func testANegativeElapsedIsTheStartOfTheFirstInterval() {
        let plan = twelveOneMinuteIntervals
        XCTAssertEqual(TogetherIntervals.position(in: plan, elapsed: -30)?.index, 0)
        XCTAssertEqual(TogetherIntervals.position(in: plan, elapsed: -30)?.elapsedInInterval, 0)
    }

    func testNoIntervalsIsNoPosition() {
        XCTAssertNil(TogetherIntervals.position(in: [], elapsed: 10))
    }

    // MARK: - TogetherTrace

    private func sample(_ bpm: Int, _ zone: HeartRateZone? = nil) -> TogetherTrace.Sample {
        TogetherTrace.Sample(bpm: bpm, zone: zone)
    }

    /// Last writer wins within an interval: the bar says where a lifter's
    /// heart was by the END of it, which is the number a reader compares.
    func testTheLastReadingOfAnIntervalIsTheOneKept() {
        var trace = TogetherTrace()
        trace.record(userID: a, bpm: 120, zone: .moderate, interval: 0)
        trace.record(userID: a, bpm: 148, zone: .hard, interval: 0)
        trace.record(userID: a, bpm: 155, zone: .hard, interval: 1)
        XCTAssertEqual(trace.trace(for: a, count: 3),
                       [sample(148, .hard), sample(155, .hard), .empty])
    }

    /// A slot with no reading is `.empty`, which the timeline draws as an
    /// EMPTY slot — the axis has to keep its shape for the intervals still
    /// to come.
    func testAnUnrecordedSlotIsEmptyAndTheLengthIsTheAxis() {
        var trace = TogetherTrace()
        trace.record(userID: a, bpm: 130, zone: .moderate, interval: 2)
        XCTAssertEqual(trace.trace(for: a, count: 5),
                       [.empty, .empty, sample(130, .moderate), .empty, .empty])
        XCTAssertEqual(trace.trace(for: b, count: 4), [.empty, .empty, .empty, .empty])
        XCTAssertEqual(trace.trace(for: a, count: 0), [])
    }

    /// Nonsense in is nothing recorded — a zero bpm and a negative interval
    /// are both refused rather than stored and drawn.
    func testNonsenseIsRefused() {
        var trace = TogetherTrace()
        trace.record(userID: a, bpm: 0, zone: .hard, interval: 0)
        trace.record(userID: a, bpm: -5, zone: .hard, interval: 0)
        trace.record(userID: a, bpm: 140, zone: .hard, interval: -1)
        XCTAssertEqual(trace.trace(for: a, count: 2), [.empty, .empty])
    }

    /// Each lifter's lane is their own.
    func testLanesDoNotBleedIntoEachOther() {
        var trace = TogetherTrace()
        trace.record(userID: a, bpm: 140, zone: .hard, interval: 0)
        trace.record(userID: b, bpm: 110, zone: .moderate, interval: 0)
        XCTAssertEqual(trace.trace(for: a, count: 1), [sample(140, .hard)])
        XCTAssertEqual(trace.trace(for: b, count: 1), [sample(110, .moderate)])
    }

    /// A reading is stored with the ZONE IT ARRIVED WITH — never
    /// recomputed from `bpm` (fix round 3 / F7). A trace can hold two
    /// samples with the SAME bpm but DIFFERENT zones (two different
    /// senders' own max-HR estimates), and the trace keeps them apart.
    func testTheZoneIsCarriedNotRecomputed() {
        var trace = TogetherTrace()
        trace.record(userID: a, bpm: 150, zone: .hard, interval: 0)
        trace.record(userID: b, bpm: 150, zone: .max, interval: 0)
        XCTAssertEqual(trace.trace(for: a, count: 1).first?.zone, .hard)
        XCTAssertEqual(trace.trace(for: b, count: 1).first?.zone, .max)
    }

    /// A broadcast that carried no zone stores `nil` — never a locally
    /// guessed one.
    func testANilZoneIsStoredAsNil() {
        var trace = TogetherTrace()
        trace.record(userID: a, bpm: 150, zone: nil, interval: 0)
        XCTAssertNil(trace.trace(for: a, count: 1).first?.zone)
    }

    // MARK: - The frame's world (frame 140)

    /// Interval 6 of 12, 18 s left of its 60 s length — EVERY number below
    /// is derived through `TogetherIntervals.position(in:elapsed:)`
    /// (`LiveFixtures.togetherIntervalPlan`/`togetherElapsed`), so this
    /// test asserts the CONSISTENCY RULE (progress agrees with the
    /// interval's own length and the elapsed time), not a literal a future
    /// edit could quietly contradict (fix round 3 / F8).
    func testTheTogetherWorld() throws {
        let world = LiveFixtures.together
        let position = TogetherIntervals.position(in: LiveFixtures.togetherIntervalPlan,
                                                  elapsed: LiveFixtures.togetherElapsed)
        let expected = try XCTUnwrap(position)
        XCTAssertEqual(world.intervalKicker,
                       RoundCopy.intervalKicker(index: expected.index,
                                                count: LiveFixtures.togetherIntervalPlan.count))
        XCTAssertEqual(world.readout, RoundCopy.clock(expected.remaining ?? expected.elapsedInInterval))
        XCTAssertEqual(world.progress, expected.progress, accuracy: 0.0001)
        // The fixture's own chosen numbers, pinned so a future edit to
        // `togetherIntervalPlan`/`togetherElapsed` cannot silently drift
        // frame 140 without this test noticing.
        XCTAssertEqual(world.intervalKicker, "INTERVAL 6 OF 12")
        XCTAssertEqual(world.readout, "0:18")
        XCTAssertEqual(world.phase, "WORK")
        XCTAssertEqual(world.phaseDetail, "Z4 · 1 min")
        XCTAssertEqual(world.nextLine, "Next: Z2 · 1 min")
        XCTAssertEqual(world.axisStart, "INTERVAL 1 OF 12")
        XCTAssertEqual(world.axisEnd, "INTERVAL 12 OF 12")
        XCTAssertEqual(world.lanes.count, 4)
    }

    /// A 60 s interval with 18 s left is 42/60 through it — the exact
    /// arithmetic finding 4 (fix round 3) flagged the old fixture for
    /// contradicting.
    func testTheWorldsProgressAgreesWithItsOwnInterval() {
        XCTAssertEqual(LiveFixtures.together.progress, 42.0 / 60.0, accuracy: 0.0001)
    }

    /// Four lanes on ONE axis: every trace is the same length, or they stop
    /// lining up. Six intervals recorded, six still empty.
    func testEveryLaneShareOneAxis() {
        let lanes = LiveFixtures.together.lanes
        XCTAssertEqual(Set(lanes.map(\.trace.count)), [12])
        for lane in lanes {
            XCTAssertEqual(lane.trace.filter { $0.bpm > 0 }.count, 6, lane.name)
        }
    }

    /// A lane's live reading is the last slot it recorded, and its zone is
    /// derived from that — a lane cannot disagree with its own trace. Every
    /// recorded sample's own zone agrees with its own bpm too (fix round 3
    /// / F7's fixture-side derivation).
    func testALanesReadingAgreesWithItsTrace() {
        for lane in LiveFixtures.together.lanes {
            XCTAssertEqual(lane.bpm, lane.trace.last(where: { $0.bpm > 0 })?.bpm, lane.name)
            XCTAssertEqual(lane.zone, lane.bpm.map { HeartRateZone.zone(bpm: $0) }, lane.name)
            for sample in lane.trace where sample.bpm > 0 {
                XCTAssertEqual(sample.zone, HeartRateZone.zone(bpm: sample.bpm), lane.name)
            }
        }
    }

    // MARK: - The copy

    func testTheIntervalKickerCountsFromOne() {
        XCTAssertEqual(RoundCopy.intervalKicker(index: 0, count: 12), "INTERVAL 1 OF 12")
        XCTAssertEqual(RoundCopy.intervalKicker(index: 11, count: 12), "INTERVAL 12 OF 12")
    }

    /// The end of the run is named, not left blank.
    func testTheNextLineNamesTheEnd() {
        XCTAssertEqual(RoundCopy.nextInterval("Z2 · 3 min"), "Next: Z2 · 3 min")
        XCTAssertEqual(RoundCopy.nextInterval(nil), "Last interval")
        XCTAssertEqual(RoundCopy.nextInterval(""), "Last interval")
    }

    func testTogethersOwnStrings() {
        XCTAssertEqual(RoundCopy.togetherNoTurn, "Everyone runs this clock. There is no turn.")
        XCTAssertEqual(RoundCopy.crewOneTimeline, "THE CREW · ONE TIMELINE")
        XCTAssertEqual(RoundCopy.endSession, "End")
    }

    // MARK: - The log control (fix round 3 / F6, ruling R-B17)

    /// `TogetherClockView.logControl`'s default is the button `turnChrome`
    /// has always drawn for Rounds/Freestyle: `LOG SET & PASS`, no
    /// readback line, not failed, not disabled — the shape `logControlFoot`
    /// (`SessionLiveView`, private) builds from live state, unset here only
    /// because this default exists for the type to be constructible at
    /// all. Before this fix Together mounted no log control whatsoever;
    /// this test at least proves the parameter exists with a sane default
    /// rather than an empty/blank button.
    func testLogControlFootDefaultsToTheOrdinaryButton() {
        let foot = LogControlFoot()
        XCTAssertEqual(foot.title, "LOG SET & PASS")
        XCTAssertNil(foot.readback)
        XCTAssertFalse(foot.isFailed)
        XCTAssertFalse(foot.isDisabled)
    }

    /// `TogetherClockView` accepts a `LogControlFoot` and stores it — a
    /// compile-time proof the two mounts (`turnChrome`'s and Together's)
    /// share one type, so they cannot drift into two different shapes.
    func testTogetherClockViewAcceptsALogControl() {
        var tapped = false
        let foot = LogControlFoot(title: "LOGGING…", readback: nil,
                                  isFailed: true, isDisabled: true,
                                  onTap: { tapped = true })
        let view = TogetherClockView(
            kicker: "PUSH CREW · TOGETHER", title: "HIIT",
            intervalKicker: "INTERVAL 1 OF 1", phase: "WORK", phaseDetail: "",
            readout: "0:00", progress: 0, nextLine: "Last interval",
            lanes: [], axisStart: "INTERVAL 1 OF 1", axisEnd: "INTERVAL 1 OF 1",
            logControl: foot)
        XCTAssertEqual(view.logControl.title, "LOGGING…")
        XCTAssertTrue(view.logControl.isFailed)
        view.logControl.onTap()
        XCTAssertTrue(tapped)
    }
}
