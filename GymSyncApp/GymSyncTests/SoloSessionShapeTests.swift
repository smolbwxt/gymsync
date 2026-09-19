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

    // MARK: - isSoloByConstruction — the session row alone, no roster

    func testAnAdHocRowIsSoloByConstruction() {
        XCTAssertTrue(SoloSessionShape.isSoloByConstruction(
            groupID: nil, roomCode: nil, scheduledFor: nil))
    }

    func testAScheduledSOLOSessionIsNOTSoloByConstruction() {
        // It IS solo, and `SessionShape.isSolo` says so once a roster is in
        // hand. But at the session row a scheduled solo session and a
        // scheduled `.friends` session are byte-identical — both leave
        // `group_id` and `room_code` nil — so this law, which has no roster,
        // must not claim to tell them apart.
        XCTAssertTrue(SessionShape.isSolo(participantCount: 1, roomCode: nil))
        XCTAssertFalse(SoloSessionShape.isSoloByConstruction(
            groupID: nil, roomCode: nil, scheduledFor: Self.date(2099, 1, 1)))
    }

    func testARoomCodeSessionIsNotSoloByConstruction() {
        XCTAssertFalse(SoloSessionShape.isSoloByConstruction(
            groupID: nil, roomCode: "PX4K9Z", scheduledFor: nil))
    }

    func testAGroupSessionIsNotSoloByConstruction() {
        XCTAssertFalse(SoloSessionShape.isSoloByConstruction(
            groupID: UUID(), roomCode: nil, scheduledFor: nil))
    }

    func testEachDiscriminatorRulesItOutONITSOWN() {
        // Three signals, any one of which is sufficient — so the predicate
        // must not accidentally be read as needing all three.
        let group = UUID()
        XCTAssertFalse(SoloSessionShape.isSoloByConstruction(
            groupID: group, roomCode: "PX4K9Z", scheduledFor: Self.date(2099, 6, 2)))
        XCTAssertFalse(SoloSessionShape.isSoloByConstruction(
            groupID: group, roomCode: nil, scheduledFor: nil))
        XCTAssertFalse(SoloSessionShape.isSoloByConstruction(
            groupID: nil, roomCode: "PX4K9Z", scheduledFor: nil))
        XCTAssertFalse(SoloSessionShape.isSoloByConstruction(
            groupID: nil, roomCode: nil, scheduledFor: Self.date(2099, 6, 2)))
    }

    // MARK: - The two laws answer different questions

    func testAScheduledSoloSessionHidesTheFurnitureWITHOUTBeingSoloByConstruction() {
        // The one case that would collapse if these were the same predicate.
        // A lifter who booked a solo slot must still not see a talk dock once
        // the roster proves they are alone — and must still get Home's
        // ordinary push, because the row alone cannot prove it.
        let scheduled = Self.date(2099, 3, 14)
        XCTAssertTrue(SoloSessionShape.hidesCrewFurniture(participantCount: 1))
        XCTAssertFalse(SoloSessionShape.isSoloByConstruction(
            groupID: nil, roomCode: nil, scheduledFor: scheduled))
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
