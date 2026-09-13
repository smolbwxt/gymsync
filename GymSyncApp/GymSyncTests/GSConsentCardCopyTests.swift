import XCTest
@testable import GymSync

/// The consent card's words — plan task S2.
///
/// Copy that lives in a view body is copy nobody can review, and copy repeated
/// in two view bodies is copy that drifts. `GSConsentCopy` is the one place
/// these three strings exist; the ladder proposal on Home, the ladder
/// proposal on the ladder page, and the warm-up screen's Coach suggestion
/// (plan task S4) all read them from here, so an edit to one surface cannot
/// silently diverge from the others.
final class GSConsentCardCopyTests: XCTestCase {

    /// Spec §4's own sentence, in caps: "Coach proposes a new ladder: …".
    func testTheLadderProposalsKicker() {
        XCTAssertEqual(GSConsentCopy.ladderKicker, "COACH PROPOSES A NEW LADDER")
    }

    /// A button says exactly what happens (rule 9). Sentence case, not caps:
    /// these are two words in a card, not a screen's primary.
    func testTheTwoAnswers() {
        XCTAssertEqual(GSConsentCopy.accept, "Accept")
        XCTAssertEqual(GSConsentCopy.decline, "Not today")
    }

    /// The consequence line, which both surfaces pass as `detail:`. It says
    /// what does NOT change as well as what does — an athlete asked to accept
    /// "a new ladder" with no such assurance would reasonably read it as
    /// Coach moving the goalposts.
    func testTheConsequenceLineNamesTheSpanAndWhatItLeavesAlone() {
        let fixture = StubBlockGoalRepository.fixtureProposal
        XCTAssertEqual(LadderProposalMath.detail(fixture),
                       "5 remaining weeks change. Your milestone and its date don't.")
    }

    /// One rung needs no detail: the sentence has already said all of it, and
    /// a line that restates its own headline is furniture.
    func testASingleRungCarriesNoConsequenceLine() {
        let fixture = StubBlockGoalRepository.fixtureProposal
        let single = LadderProposal(goalID: fixture.goalID,
                                    current: fixture.current,
                                    proposed: fixture.proposed,
                                    changed: Array(fixture.changed.prefix(1)),
                                    derivedAt: fixture.derivedAt)
        XCTAssertNil(LadderProposalMath.detail(single))
    }
}
