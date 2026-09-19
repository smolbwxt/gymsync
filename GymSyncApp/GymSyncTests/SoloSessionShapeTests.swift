import XCTest
@testable import GymSync

/// THE SOLO SHAPE, ON EVERY BRANCH (plan task S4, decision 6 / brief item 7).
///
/// Two laws with different questions, and the tests are here rather than in a
/// view because that is the whole reason `SoloSessionShape` exists: four
/// inline `participants.count <= 1` tests in a 5,500-line body are four
/// places for the answer to drift, and none of them is reachable from a test.
final class SoloSessionShapeTests: XCTestCase {

    // MARK: - crew(…) — the three-valued law the view actually reads
    //
    // Exercised through `hidesCrewFurniture(groupID:roomCode:scheduledFor:
    // loadedParticipantCount:)`, the SAME function `SessionLiveView.crewShape`
    // calls, rather than through a predicate nothing calls (fix round 1 / N7).

    /// The bug N1 names, pinned: a CREW whose roster has not arrived must NOT
    /// be shown the solo shape. Before the fix this answered true for every
    /// session on the first render pass, and went on answering true for as
    /// long as `reload()` kept failing — which silently denied a whole crew
    /// its voice dock on a bad connection.
    func testACrewSessionWithNoRosterYetKeepsTheCrewsFurniture() {
        XCTAssertEqual(
            SoloSessionShape.crew(groupID: UUID(), roomCode: nil,
                                  scheduledFor: Self.date(2099, 4, 1),
                                  loadedParticipantCount: nil),
            .unknown)
        XCTAssertFalse(SoloSessionShape.hidesCrewFurniture(
            groupID: UUID(), roomCode: nil,
            scheduledFor: Self.date(2099, 4, 1), loadedParticipantCount: nil))
    }

    func testAScheduledSessionWithNoRosterYetIsUNKNOWNNotSolo() {
        // The `.friends` / scheduled-solo pair: indistinguishable at the row,
        // so neither may be assumed solo before the roster proves it.
        XCTAssertFalse(SoloSessionShape.hidesCrewFurniture(
            groupID: nil, roomCode: nil,
            scheduledFor: Self.date(2099, 4, 1), loadedParticipantCount: nil))
    }

    func testAnAdHocSessionIsSOLOBEFOREAnyRosterArrives() {
        // The other half of the same rule: construction is available before
        // any fetch, and the cover is raised the instant `startSolo` returns.
        // An ad-hoc lifter must never see one frame of crew chrome either.
        XCTAssertEqual(
            SoloSessionShape.crew(groupID: nil, roomCode: nil,
                                  scheduledFor: nil, loadedParticipantCount: nil),
            .solo)
        XCTAssertTrue(SoloSessionShape.hidesCrewFurniture(
            groupID: nil, roomCode: nil, scheduledFor: nil,
            loadedParticipantCount: nil))
    }

    func testALOADEDRosterOfOneIsSoloWhateverTheRowSays() {
        // A scheduled solo session gets the solo shape the moment its roster
        // of one arrives — item 2's "gate on the roster, and on nothing else,
        // so a scheduled solo session gets the same treatment".
        XCTAssertEqual(
            SoloSessionShape.crew(groupID: nil, roomCode: nil,
                                  scheduledFor: Self.date(2099, 4, 1),
                                  loadedParticipantCount: 1),
            .solo)
        XCTAssertTrue(SoloSessionShape.hidesCrewFurniture(
            groupID: nil, roomCode: nil,
            scheduledFor: Self.date(2099, 4, 1), loadedParticipantCount: 1))
    }

    func testALOADEDRosterOfTwoOrMoreIsCrew() {
        for count in [2, 6] {
            XCTAssertEqual(
                SoloSessionShape.crew(groupID: UUID(), roomCode: nil,
                                      scheduledFor: Self.date(2099, 4, 1),
                                      loadedParticipantCount: count),
                .crew, "a roster of \(count) is a crew")
            XCTAssertFalse(SoloSessionShape.hidesCrewFurniture(
                groupID: UUID(), roomCode: nil,
                scheduledFor: Self.date(2099, 4, 1), loadedParticipantCount: count))
        }
    }

    func testZEROIsNotAROSTERAndCannotReachThisLawAsALoadedCount() {
        // The view maps an empty array to nil rather than 0 — a real session
        // always holds at least the viewer — but if a caller ever did pass 0
        // for a crew session, "nobody is here" must not read as "you are
        // alone with the crew's controls hidden": it is <= 1, so it answers
        // solo, and this is the case that records the view's obligation.
        XCTAssertEqual(
            SoloSessionShape.crew(groupID: UUID(), roomCode: nil,
                                  scheduledFor: Self.date(2099, 4, 1),
                                  loadedParticipantCount: 0),
            .solo)
    }

    func testOnlyAPROVEDPartyOfOneHidesTheFurniture() {
        XCTAssertTrue(SoloSessionShape.hidesCrewFurniture(.solo))
        XCTAssertFalse(SoloSessionShape.hidesCrewFurniture(.crew))
        XCTAssertFalse(SoloSessionShape.hidesCrewFurniture(.unknown),
                       "an unknown keeps the crew's shipped behaviour")
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
