import XCTest
@testable import GymSync

/// The lobby's two hardest facts — plan task S3.
///
/// PURE: no database, no clock, no view. Everything S4 to S11 builds types
/// against this file, so these are the assertions that stop a pixel from
/// depending on a rule nobody wrote down.
final class SessionArrivalTests: XCTestCase {

    // MARK: - ArrivalLaw: who is where

    /// The DB fact wins. `check_in_state == "ready"` is checked in, full stop
    /// — spec §3.1's "checked in is ready; there is no separate roster and no
    /// separate ready tick".
    func testReadyIsCheckedInWhateverThePresenceSays() {
        XCTAssertEqual(ArrivalLaw.stage(checkInState: "ready", publishedStage: nil),
                       .checkedIn)
        XCTAssertEqual(ArrivalLaw.stage(checkInState: "ready", publishedStage: "atTheGym"),
                       .checkedIn)
    }

    /// ON THE WAY is the honest default: a lifter whose device has published
    /// nothing has told us nothing about where they are.
    func testNoPublishedStageIsOnTheWay() {
        for state in [nil, "invited", "online", "late"] {
            XCTAssertEqual(ArrivalLaw.stage(checkInState: state, publishedStage: nil),
                           .onTheWay,
                           "check_in_state \(state ?? "nil") with no presence")
        }
    }

    /// The geofence is evaluated on each device and published for ITSELF —
    /// no column stores where somebody standing in the room is.
    func testAPublishedAtTheGymIsAtTheGym() {
        XCTAssertEqual(ArrivalLaw.stage(checkInState: "online", publishedStage: "atTheGym"),
                       .atTheGym)
    }

    /// **The case a naive `if presence` ordering gets wrong.** A lifter who
    /// checked in and then walked out of the geofence — or whose device
    /// published before the tap landed — is still checked in.
    func testReadyBeatsAStalePublishedOnTheWay() {
        XCTAssertEqual(ArrivalLaw.stage(checkInState: "ready", publishedStage: "onTheWay"),
                       .checkedIn)
    }

    /// A device may not publish itself INTO the DB fact: `checkedIn` is
    /// `session_participants.check_in_state`'s to say and nothing else's.
    func testADeviceCannotPublishItselfCheckedIn() {
        XCTAssertEqual(ArrivalLaw.stage(checkInState: "online", publishedStage: "checkedIn"),
                       .onTheWay)
    }

    func testTheLateLaneIsBothTerminalStates() {
        XCTAssertTrue(ArrivalLaw.isLate(checkInState: "late"))
        XCTAssertTrue(ArrivalLaw.isLate(checkInState: "no_show"))
        XCTAssertFalse(ArrivalLaw.isLate(checkInState: "ready"))
        XCTAssertFalse(ArrivalLaw.isLate(checkInState: nil))
    }

    // MARK: - SessionShape: what counts as solo

    func testOneParticipantAndNoRoomCodeIsSolo() {
        XCTAssertTrue(SessionShape.isSolo(participantCount: 1, roomCode: nil))
    }

    /// The `.friends` session `group_id == nil` would have called solo — and
    /// mis-routed straight past the lobby its two lifters need (context-map
    /// §6, crash report H4).
    func testTwoParticipantsWithNoRoomCodeIsNotSolo() {
        XCTAssertFalse(SessionShape.isSolo(participantCount: 2, roomCode: nil))
    }

    /// A room code is an invitation, so somebody is expected.
    func testARoomCodeIsNeverSolo() {
        XCTAssertFalse(SessionShape.isSolo(participantCount: 1, roomCode: "ABCD"))
    }

    // MARK: - LobbyCopy

    func testCheckedInCaptionCountsTheCheckedInColumn() {
        XCTAssertEqual(LobbyCopy.checkedInCaption(checkedIn: 2, total: 4),
                       "2 of 4 checked in")
    }

    func testEnergyReportedIsCaps() {
        XCTAssertEqual(LobbyCopy.energyReported(reported: 3, total: 4),
                       "3 OF 4 REPORTED")
    }

    /// The crewmate's caption says exactly what will happen — the organizer's
    /// client fires Start on its own once everyone is checked in (plan task
    /// S7), and a screen that only said "Waiting for Alex" would read as
    /// stalled.
    func testTheCrewmatesCaptionNamesTheLeaderAndTheAutoStart() {
        XCTAssertEqual(LobbyCopy.readyCrewmateCaption(leaderFirstName: "Alex"),
                       "Waiting for Alex — or it starts on its own")
    }

    func testTheOwnersSentenceIsVerbatim() {
        XCTAssertEqual(LobbyCopy.everyoneHere, "Everyone's here. Let's work.")
    }

    // MARK: - The stage's own words

    func testEveryStageHasACapsLabelAndAGlyph() {
        XCTAssertEqual(ArrivalStage.onTheWay.caps, "ON THE WAY")
        XCTAssertEqual(ArrivalStage.atTheGym.caps, "AT THE GYM")
        XCTAssertEqual(ArrivalStage.checkedIn.caps, "CHECKED IN")
        for stage in ArrivalStage.allCases {
            XCTAssertFalse(stage.glyph.isEmpty)
        }
    }
}
