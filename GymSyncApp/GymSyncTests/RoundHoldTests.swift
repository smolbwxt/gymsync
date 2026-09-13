import XCTest
@testable import GymSync

/// The hold threshold and the rest measure it reads — plan task S1
/// (spec §9a, owner decision 11).
///
/// Every number the crew is held by lives in `RoundHold` and nowhere else.
/// These assertions are the reason: a threshold inlined at a call site is a
/// threshold that can be 90 s on one screen and 120 s on another, and the
/// crew experiences the difference as the app being wrong about who is late.
final class RoundHoldTests: XCTestCase {

    // MARK: - The four constants, by their owner-pinned values

    func testTheConstantsAreTheOwnersNumbers() {
        XCTAssertEqual(RoundHold.floorSeconds, 90)
        XCTAssertEqual(RoundHold.multiplier, 1.5)
        XCTAssertEqual(RoundHold.capSeconds, 180)
        XCTAssertEqual(RoundHold.extensionSeconds, 60)
    }

    // MARK: - threshold(medianRestSeconds:) = min(max(90, 1.5 x median), 180)

    /// A crew resting 40 s between sets is not a crew that should be offered
    /// a skip after 60 s. The floor wins.
    func testAShortRestIsHeldUpByTheFloor() {
        XCTAssertEqual(RoundHold.threshold(medianRestSeconds: 40), 90)
    }

    /// Between the floor and the cap the multiplier is the whole rule: a
    /// lifter is "still resting" at half again their own normal rest.
    func testAMiddlingRestScalesByTheMultiplier() {
        XCTAssertEqual(RoundHold.threshold(medianRestSeconds: 80), 120)
    }

    /// Three minutes is the most a crew waits, whatever the median says.
    func testALongRestIsCutOffByTheCap() {
        XCTAssertEqual(RoundHold.threshold(medianRestSeconds: 200), 180)
    }

    /// The boundaries themselves, so a future edit to the formula cannot
    /// quietly move where the floor stops applying and the cap starts.
    func testTheBoundariesSitExactlyOnTheFloorAndTheCap() {
        XCTAssertEqual(RoundHold.threshold(medianRestSeconds: 60), 90)   // 1.5 x 60 == the floor
        XCTAssertEqual(RoundHold.threshold(medianRestSeconds: 120), 180) // 1.5 x 120 == the cap
        XCTAssertEqual(RoundHold.threshold(medianRestSeconds: 0), 90)
    }

    // MARK: - The extension applies once (owner decision 11)

    func testOneExtensionAddsOneMinute() {
        XCTAssertEqual(RoundHold.threshold(medianRestSeconds: 80, extensionsTaken: 0), 120)
        XCTAssertEqual(RoundHold.threshold(medianRestSeconds: 80, extensionsTaken: 1), 180)
    }

    /// "I need a minute" is a minute, not a minute per tap. A second, third
    /// or hundredth extension buys nothing — the cap on the crew's patience
    /// is 180 + 60, full stop.
    func testASecondExtensionBuysNothing() {
        let once = RoundHold.threshold(medianRestSeconds: 200, extensionsTaken: 1)
        XCTAssertEqual(once, 240)
        XCTAssertEqual(RoundHold.threshold(medianRestSeconds: 200, extensionsTaken: 2), once)
        XCTAssertEqual(RoundHold.threshold(medianRestSeconds: 200, extensionsTaken: 99), once)
        XCTAssertEqual(RoundHold.threshold(medianRestSeconds: 200, extensionsTaken: -1),
                       RoundHold.threshold(medianRestSeconds: 200))
    }

    // MARK: - RestMeasure.medians(from:since:)

    private let sam = UUID()
    private let dana = UUID()
    private let session = UUID()
    private let lift = UUID()

    /// The round opened here. Every fixture time below is an offset from it.
    private var roundStart: Date {
        var components = DateComponents()
        components.year = 2099; components.month = 1; components.day = 1
        components.hour = 18; components.minute = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: components)!
    }

    private func log(_ user: UUID, at offset: TimeInterval) -> SetLog {
        SetLog(id: UUID(), userID: user, sessionID: session, exerciseID: lift,
               setIndex: 1, reps: 8, weight: 100, rpe: nil,
               isFailed: false, isPenalty: false, note: nil,
               loggedAt: roundStart.addingTimeInterval(offset))
    }

    /// A rest is the gap between two consecutive logs. Three logs are two
    /// gaps, and the median of [60, 60] is 60.
    func testTheMedianIsTakenOverTheGapsBetweenConsecutiveLogs() {
        let medians = RestMeasure.medians(
            from: [log(sam, at: 0), log(sam, at: 60), log(sam, at: 120)],
            since: roundStart
        )
        XCTAssertEqual(medians[sam], 60)
    }

    /// One log is one moment, and a moment has no duration. There is no
    /// median to report — and reporting 0 would put the floor's 90 s on a
    /// lifter nobody has measured yet.
    func testOneLogYieldsNoMedian() {
        let medians = RestMeasure.medians(from: [log(sam, at: 0)], since: roundStart)
        XCTAssertNil(medians[sam])
        XCTAssertTrue(medians.isEmpty)
    }

    func testAnEvenNumberOfGapsAveragesTheMiddleTwo() {
        // gaps: 30, 60, 90 ... plus one more -> 30, 60, 90, 150 -> (60+90)/2
        let medians = RestMeasure.medians(
            from: [log(sam, at: 0), log(sam, at: 30), log(sam, at: 90),
                   log(sam, at: 180), log(sam, at: 330)],
            since: roundStart
        )
        XCTAssertEqual(medians[sam], 75)
    }

    /// Each lifter is measured against themselves. Interleaved logs from two
    /// people are two separate rest histories, never one.
    func testEachLifterIsMeasuredSeparately() {
        let medians = RestMeasure.medians(
            from: [log(sam, at: 0), log(dana, at: 10), log(sam, at: 40),
                   log(dana, at: 130), log(sam, at: 80)],
            since: roundStart
        )
        XCTAssertEqual(medians[sam], 40)
        XCTAssertEqual(medians[dana], 120)
    }

    /// Order in is not order logged: the array the live body holds is sorted
    /// by `logged_at`, but the measure must not depend on that.
    func testTheInputNeedNotArriveInOrder() {
        let ordered = RestMeasure.medians(
            from: [log(sam, at: 0), log(sam, at: 45), log(sam, at: 90)],
            since: roundStart
        )
        let shuffled = RestMeasure.medians(
            from: [log(sam, at: 90), log(sam, at: 0), log(sam, at: 45)],
            since: roundStart
        )
        XCTAssertEqual(ordered[sam], 45)
        XCTAssertEqual(shuffled[sam], ordered[sam])
    }

    /// `since` is the round's own start. A rest that began before the round
    /// opened is not this round's rest — and the gap ACROSS the boundary is
    /// not one either, which is why the earlier log is dropped rather than
    /// kept as the first endpoint.
    func testLogsBeforeSinceAreNotMeasured() {
        let medians = RestMeasure.medians(
            from: [log(sam, at: -600), log(sam, at: 0), log(sam, at: 50), log(sam, at: 100)],
            since: roundStart
        )
        XCTAssertEqual(medians[sam], 50)
    }

    /// Nothing to measure is an empty answer, not a zero.
    func testNoLogsYieldNoMedians() {
        XCTAssertTrue(RestMeasure.medians(from: [], since: roundStart).isEmpty)
    }

    // MARK: - holdStartedAt(roundLogTimes:presentCount:) — plan task S7
    //
    // The threshold starts when the SECOND-TO-LAST lifter of the round logs,
    // derived from the logs and never from a timer that starts when a view
    // appears. A view timer measures how long a phone has been on a screen;
    // the crew is held from the moment everybody but one is done.

    private func at(_ offset: TimeInterval) -> Date { roundStart.addingTimeInterval(offset) }

    /// Four present, three logged: the crew began waiting at the most recent
    /// of those three, which is the second-to-last lifter's own log.
    func testTheWaitStartsAtTheSecondToLastLog() {
        XCTAssertEqual(
            RoundHold.holdStartedAt(roundLogTimes: [at(10), at(150), at(70)], presentCount: 4),
            at(150))
    }

    /// Two lifters out is not one lifter holding the crew, and there is
    /// nobody to name in the offer.
    func testTwoLiftersOutIsNotAHold() {
        XCTAssertNil(RoundHold.holdStartedAt(roundLogTimes: [at(10), at(70)], presentCount: 4))
    }

    /// Everybody has logged: the round closes on its own and no skip is
    /// needed.
    func testAFinishedRoundIsNotAHold() {
        XCTAssertNil(
            RoundHold.holdStartedAt(roundLogTimes: [at(10), at(70), at(150), at(160)],
                                    presentCount: 4))
    }

    /// A LIFTER WHO ARRIVES MID-ROUND JOINS THE PRESENT SET (ruling R-B7), so
    /// the round LENGTHENS rather than closing — and the wait must stop
    /// reading as a hold on whoever was nearly last. Three logs held a crew of
    /// four; a fifth arrival makes the same three logs two-out again.
    func testAMidRoundArrivalEndsTheHold() {
        let logs = [at(10), at(70), at(150)]
        XCTAssertEqual(RoundHold.holdStartedAt(roundLogTimes: logs, presentCount: 4), at(150))
        XCTAssertNil(RoundHold.holdStartedAt(roundLogTimes: logs, presentCount: 5))
    }

    /// A crew of one has nobody to be held by, and an empty round has nobody
    /// to wait on.
    func testASoloRotationIsNeverHeld() {
        XCTAssertNil(RoundHold.holdStartedAt(roundLogTimes: [], presentCount: 1))
        XCTAssertNil(RoundHold.holdStartedAt(roundLogTimes: [], presentCount: 0))
    }

    /// A crew of two with one logged IS a hold — the smallest one there is.
    func testACrewOfTwoCanBeHeld() {
        XCTAssertEqual(RoundHold.holdStartedAt(roundLogTimes: [at(45)], presentCount: 2), at(45))
    }

    // MARK: - isHeld(since:now:medianRestSeconds:extensionsTaken:)

    /// AT the threshold, not a second after it.
    func testTheOfferAppearsExactlyAtTheThreshold() {
        // 1.5 x 96 = 144, between the floor and the cap.
        XCTAssertFalse(RoundHold.isHeld(since: roundStart, now: at(143),
                                        medianRestSeconds: 96, extensionsTaken: 0))
        XCTAssertTrue(RoundHold.isHeld(since: roundStart, now: at(144),
                                       medianRestSeconds: 96, extensionsTaken: 0))
    }

    /// "I need a minute" pushes the offer out by exactly one minute, and a
    /// second tap pushes it no further.
    func testAMinutePushesTheOfferOutOnce() {
        XCTAssertFalse(RoundHold.isHeld(since: roundStart, now: at(144),
                                        medianRestSeconds: 96, extensionsTaken: 1))
        XCTAssertTrue(RoundHold.isHeld(since: roundStart, now: at(204),
                                       medianRestSeconds: 96, extensionsTaken: 1))
        XCTAssertTrue(RoundHold.isHeld(since: roundStart, now: at(204),
                                       medianRestSeconds: 96, extensionsTaken: 7))
    }

    /// No wait, no offer — and a clock that has gone backwards is not a wait
    /// either.
    func testNothingIsHeldWithoutAStartOrWithANegativeWait() {
        XCTAssertFalse(RoundHold.isHeld(since: nil, now: at(600),
                                        medianRestSeconds: 96, extensionsTaken: 0))
        XCTAssertFalse(RoundHold.isHeld(since: roundStart, now: at(-10),
                                        medianRestSeconds: 96, extensionsTaken: 0))
    }

    /// The cap still caps: a crew whose median is five minutes is offered the
    /// skip at three, not at seven and a half.
    func testALongRestingCrewIsStillOfferedTheSkipAtTheCap() {
        XCTAssertTrue(RoundHold.isHeld(since: roundStart, now: at(180),
                                       medianRestSeconds: 300, extensionsTaken: 0))
    }
}
