import XCTest
@testable import GymSync

/// THE SOLO SHAPE, ON EVERY BRANCH (plan task S4, decision 6 / brief item 7).
///
/// Two laws with different questions, and the tests are here rather than in a
/// view because that is the whole reason `SoloSessionShape` exists: four
/// inline `participants.count <= 1` tests in a 5,500-line body are four
/// places for the answer to drift, and none of them is reachable from a test.
final class SoloSessionShapeTests: XCTestCase {

    // MARK: - hidesCrewFurniture — the roster, and only the roster

    func testAPartyOfOneHidesTheCrewsFurniture() {
        XCTAssertTrue(SoloSessionShape.hidesCrewFurniture(participantCount: 1))
    }

    func testAnEmptyRosterHidesItToo() {
        // Not a real session, but it IS a real render: the live body's roster
        // arrives asynchronously, and a talk dock that flashes on for one
        // frame before the fetch lands is exactly the furniture this gate is
        // meant to keep off a solo screen.
        XCTAssertTrue(SoloSessionShape.hidesCrewFurniture(participantCount: 0))
    }

    func testTwoLiftersKeepIt() {
        XCTAssertFalse(SoloSessionShape.hidesCrewFurniture(participantCount: 2))
    }

    func testAFullCrewKeepsIt() {
        XCTAssertFalse(SoloSessionShape.hidesCrewFurniture(participantCount: 6))
    }

    func testItAsksNothingAboutTheSCHEDULE() {
        // Item 2's rule, verbatim: gate on the roster "and on nothing else,
        // so a scheduled solo session gets the same treatment, which is
        // correct". The signature is the proof — there is no date to pass —
        // and this case is the statement of intent a later reader needs.
        XCTAssertEqual(SoloSessionShape.hidesCrewFurniture(participantCount: 1),
                       SoloSessionShape.hidesCrewFurniture(participantCount: 1),
                       "the answer depends on the roster alone")
        XCTAssertTrue(SoloSessionShape.hidesCrewFurniture(participantCount: 1))
    }

    // MARK: - isAdHocSolo — a party of one, no code, no clock

    func testAnAdHocSoloSessionIsOne() {
        XCTAssertTrue(SoloSessionShape.isAdHocSolo(
            participantCount: 1, roomCode: nil, scheduledFor: nil))
    }

    func testAScheduledSoloSessionIsNOTAdHoc() {
        // It is solo — `SessionShape.isSolo` says so — but it was booked, so
        // it is reached through Home's button as a navigation push with a
        // back button of its own, and needs no MINIMISE built for it.
        XCTAssertTrue(SessionShape.isSolo(participantCount: 1, roomCode: nil))
        XCTAssertFalse(SoloSessionShape.isAdHocSolo(
            participantCount: 1, roomCode: nil,
            scheduledFor: Self.date(2099, 1, 1)))
    }

    func testARoomCodeSessionIsNotSoloEvenWithOneRowSoFar() {
        // The crew has not arrived yet; the code says they are coming.
        // `SessionShape.isSolo`'s own doc carries this reasoning — `group_id`
        // is not the signal, because `.friends` and `.code` both leave it nil.
        XCTAssertFalse(SoloSessionShape.isAdHocSolo(
            participantCount: 1, roomCode: "PX4K9Z", scheduledFor: nil))
    }

    func testACrewIsNotAdHocSolo() {
        XCTAssertFalse(SoloSessionShape.isAdHocSolo(
            participantCount: 4, roomCode: nil, scheduledFor: nil))
    }

    func testNeitherACodeNORAClockIsNeededToRuleItOut() {
        // Both discriminators at once — each is sufficient on its own, so the
        // pair must not accidentally be read as a conjunction.
        XCTAssertFalse(SoloSessionShape.isAdHocSolo(
            participantCount: 1, roomCode: "PX4K9Z",
            scheduledFor: Self.date(2099, 6, 2)))
    }

    func testAnEmptyRosterCountsAsAPartyOfOne() {
        // `SessionShape.isSolo` is `<= 1`, not `== 1`, and this inherits it:
        // the ad-hoc cover must offer MINIMISE on the very first frame, while
        // the roster fetch is still in flight.
        XCTAssertTrue(SoloSessionShape.isAdHocSolo(
            participantCount: 0, roomCode: nil, scheduledFor: nil))
    }

    // MARK: - The two laws answer different questions

    func testAScheduledSoloSessionHidesTheFurnitureWITHOUTBeingAdHoc() {
        // The one case that would collapse if these were the same predicate.
        // A lifter who booked a solo slot must still not see a talk dock —
        // and must still get Home's ordinary push, not a cover.
        let scheduled = Self.date(2099, 3, 14)
        XCTAssertTrue(SoloSessionShape.hidesCrewFurniture(participantCount: 1))
        XCTAssertFalse(SoloSessionShape.isAdHocSolo(
            participantCount: 1, roomCode: nil, scheduledFor: scheduled))
    }

    // MARK: - Helper

    /// Built from components, never `Date()` — a test that reads the clock
    /// answers a different question tomorrow.
    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
