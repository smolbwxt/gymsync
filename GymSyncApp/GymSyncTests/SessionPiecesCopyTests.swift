import XCTest
@testable import GymSync

/// Every literal the production session pieces print — plan task S4.
///
/// Copy that lives in a view body is copy nobody can review. Each string is
/// hoisted into `SessionCopy` and asserted here, so the owner can read what
/// the lobby and the warm-up screen say without opening a view file, and so an
/// edit to one surface cannot silently change another's words.
final class SessionPiecesCopyTests: XCTestCase {

    // MARK: - The arrival track

    /// The three columns, in the order the track draws them. They live on
    /// `ArrivalStage` (plan task S3) because the law and the label are one
    /// fact; the track prints them and nothing else does.
    func testTheArrivalTracksThreeColumns() {
        XCTAssertEqual(ArrivalStage.allCases.map(\.caps),
                       ["ON THE WAY", "AT THE GYM", "CHECKED IN"])
    }

    // MARK: - The plan

    func testThePlanCardsKicker() {
        XCTAssertEqual(SessionCopy.theSession, "THE SESSION")
    }

    /// Flat furniture on a raised card (rule 1), and one word, because the
    /// chip has a row's worth of space.
    func testTheSwapChip() {
        XCTAssertEqual(SessionCopy.swap, "Swap")
    }

    // MARK: - The crew's energy

    func testTheEnergyCardsKickerAndAsk() {
        XCTAssertEqual(SessionCopy.howTheCrewFeels, "HOW THE CREW FEELS")
        XCTAssertEqual(SessionCopy.howAreYouFeeling, "How are you feeling?")
    }

    /// An absence, never a zero: a lifter who has not answered has not
    /// reported energy 0, and a meter drawn empty would say they had.
    func testAnUnansweredMeterSaysNotYet() {
        XCTAssertEqual(SessionCopy.notYet, "not yet")
    }

    // MARK: - The block and the clock

    func testTheBlockStripAndClockKickers() {
        XCTAssertEqual(SessionCopy.whereYouAre, "WHERE YOU ARE")
        XCTAssertEqual(SessionCopy.warmingUp, "WARMING UP")
    }

    /// Spec §6's "warm-up is a phase, not a number", said to the athlete.
    func testTheClockHasNoTarget() {
        XCTAssertEqual(SessionCopy.noTargetGoWhenReady,
                       "No target. Go when you're ready.")
    }

    // MARK: - The crew warm-up

    func testTheReadinessKicker() {
        XCTAssertEqual(SessionCopy.whosWarm, "WHO'S WARM")
    }

    // MARK: - Coach

    /// Spec §3.2: a crew screen that shows a Coach line without saying so
    /// reads as a broadcast.
    func testThePrivacyNote() {
        XCTAssertEqual(SessionCopy.onlyYouSeeThis, "Only you see this.")
    }

    /// **THE SAME TWO WORDS `GSConsentCard` USES** (plan task S2), asserted
    /// against that enum rather than against two literals — so a suggestion
    /// answers the same way everywhere in the app, and a later edit to one
    /// surface cannot diverge from the other.
    func testTheSuggestionAnswersWithTheConsentCardsWords() {
        XCTAssertEqual(SessionCopy.accept, "Accept")
        XCTAssertEqual(SessionCopy.decline, "Not today")
        XCTAssertEqual(SessionCopy.accept, GSConsentCopy.accept)
        XCTAssertEqual(SessionCopy.decline, GSConsentCopy.decline)
    }

    func testCoachsDoor() {
        XCTAssertEqual(SessionCopy.talkToCoach, "Talk to Coach")
        XCTAssertEqual(SessionCopy.talkToCoachDetail,
                       "This session's focus · form questions · demo videos")
    }

    // MARK: - The column name

    /// A lifter reads the row to find themselves in it, so their own column
    /// says "You" and everyone else's says a first name — a full name wraps a
    /// 40 pt column.
    func testAColumnNamesYouAsYouAndEveryoneElseByFirstName() {
        let you = ArrivalRow(id: UUID(), name: "Jordan Reyes", avatarURL: nil,
                             stage: .checkedIn, energy: 4, isYou: true, isLate: false)
        let them = ArrivalRow(id: UUID(), name: "Alex Nakamura", avatarURL: nil,
                              stage: .onTheWay, energy: nil, isYou: false, isLate: false)
        XCTAssertEqual(SessionCopy.columnName(you), "You")
        XCTAssertEqual(SessionCopy.columnName(them), "Alex")
        XCTAssertEqual(SessionCopy.firstName("Alex"), "Alex")
        XCTAssertEqual(SessionCopy.firstName(""), "")
    }
}
