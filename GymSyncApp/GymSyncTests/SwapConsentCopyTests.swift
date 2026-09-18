import XCTest
@testable import GymSync

/// Every string the crew's consent card prints, and the pip arithmetic —
/// plan task S1.
///
/// The card is a view and is proved by frame 142. What a screenshot cannot
/// prove is that the agreement line counts the same thing the pips count, or
/// that "Keep back squat" is one spelling rather than two. `SwapConsentCopy`
/// exists precisely so these assertions can.
final class SwapConsentCopyTests: XCTestCase {

    // MARK: - The header

    func testTheKickerNamesTheCrewsProposal() {
        XCTAssertEqual(SwapConsentCopy.kicker, "CREW PROPOSAL")
    }

    /// "for everyone" is the whole difference between this and the quiet
    /// self-scale (spec §3.4 mode 2), so the sentence says it out loud.
    func testTheProposalSentenceNamesTheProposerAndTheScope() {
        XCTAssertEqual(SwapConsentCopy.proposal(by: "Dana"),
                       "Dana proposes a change for everyone")
    }

    // MARK: - The two doors

    /// The kickers carry the direction the struck-through label used to.
    func testTheDoorKickers() {
        XCTAssertEqual(SwapConsentCopy.nowKicker, "NOW")
        XCTAssertEqual(SwapConsentCopy.proposedKicker, "PROPOSED")
    }

    // MARK: - The agreement line

    func testAgreementAtNone() {
        XCTAssertEqual(SwapConsentCopy.agreement(agreed: 0, crew: 4), "0 of 4 agree")
    }

    func testAgreementPartWay() {
        XCTAssertEqual(SwapConsentCopy.agreement(agreed: 2, crew: 4), "2 of 4 agree")
    }

    /// Unanimity is what applies the swap (`evaluateUnanimity`: every PRESENT
    /// lifter said yes), so the full house is a state the line must read
    /// correctly rather than a case that never arrives.
    func testAgreementUnanimous() {
        XCTAssertEqual(SwapConsentCopy.agreement(agreed: 4, crew: 4), "4 of 4 agree")
    }

    /// A crew of one is a sentence, not a plural bug.
    func testAgreementForACrewOfOne() {
        XCTAssertEqual(SwapConsentCopy.agreement(agreed: 1, crew: 1), "1 of 1 agree")
    }

    // MARK: - The consequence

    /// It says what does NOT change as well as what does — without that, a
    /// crewmate reads "a change for everyone" as their own set being altered
    /// the moment they tap.
    func testTheConsequenceLineSaysWhatItLeavesAlone() {
        XCTAssertEqual(
            SwapConsentCopy.consequence,
            "It applies to everyone the moment the crew agrees. Until then your set is unchanged.")
    }

    // MARK: - The answers

    /// Sentence case, not caps: two words in a card, not a screen's primary
    /// — and the same shape `GSConsentCopy.accept` carries.
    func testAgreeIsOneSpelling() {
        XCTAssertEqual(SwapConsentCopy.agree, "Agree")
    }

    /// Declining names the exercise the crew would keep, lowercased inside
    /// the sentence however the catalog capitalises it.
    func testKeepNamesTheExerciseLowercased() {
        XCTAssertEqual(SwapConsentCopy.keep("Back squat"), "Keep back squat")
        XCTAssertEqual(SwapConsentCopy.keep("BACK SQUAT"), "Keep back squat")
    }

    /// Once I have answered, the card says what happens next rather than
    /// leaving two live buttons over a decision I already made.
    func testWaitingSaysWhatHappensNext() {
        XCTAssertEqual(SwapConsentCopy.waiting, "Waiting on the crew")
    }

    // MARK: - The fixture the frame renders

    /// Frame 142's world, asserted here so the capture and the card agree
    /// about what it is showing: four present, two agreed, and I have not
    /// answered — which is the only state that draws the answers at all.
    func testTheCatalogWorldIsTheUnansweredTwoOfFour() {
        let model = LiveFixtures.swapConsent
        XCTAssertEqual(model.crewSize, 4)
        XCTAssertEqual(model.agreed, 2)
        XCTAssertEqual(model.agreedNames.count, 2)
        XCTAssertFalse(model.iHaveAnswered)
        XCTAssertTrue(model.from.opens)
        XCTAssertTrue(model.to.opens)
        XCTAssertNotEqual(model.from.exerciseID, model.to.exerciseID)
    }
}
