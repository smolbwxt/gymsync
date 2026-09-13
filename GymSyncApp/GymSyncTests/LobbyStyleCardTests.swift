import XCTest
@testable import GymSync

/// The lobby's style card — plan task S2.
///
/// The card itself is a view and is proved by frame 136. What CANNOT be
/// proved by a screenshot is the one-shot default rule: whether the
/// organizer's client writes a derived style, and — far more importantly —
/// when it must not. That rule is extracted as a pure function precisely so
/// these assertions can exist.
final class LobbyStyleCardTests: XCTestCase {

    // MARK: - The kicker (design rule 3: caps for kickers)

    func testTheCardsKicker() {
        XCTAssertEqual(LobbyView.styleKicker, "HOW THIS SESSION MOVES")
    }

    // MARK: - shouldApplyDefault(current:derived:hasApplied:)

    /// The only case that writes: the row still carries the column's own
    /// default and the routine derives something else.
    func testAnUnchosenSessionTakesTheDerivedDefault() {
        XCTAssertTrue(LobbyView.shouldApplyDefault(current: .rounds,
                                                   derived: .together,
                                                   hasApplied: false))
    }

    /// One shot. `reload()` runs on every realtime echo and every 5 s poll;
    /// without this the lobby would re-PATCH the session forever.
    func testItNeverFiresTwice() {
        XCTAssertFalse(LobbyView.shouldApplyDefault(current: .rounds,
                                                    derived: .together,
                                                    hasApplied: true))
    }

    /// Nothing to write: the derived answer is already what the row says.
    func testARoundsRoutineWritesNothing() {
        XCTAssertFalse(LobbyView.shouldApplyDefault(current: .rounds,
                                                    derived: .rounds,
                                                    hasApplied: false))
    }

    /// A DERIVED DEFAULT NEVER OVERRIDES A DECISION. Once the row reads
    /// anything but `rounds`, somebody chose it — the column's default is
    /// `rounds`, so those two facts are the same fact — and the crew's choice
    /// stands even against a routine that would derive otherwise.
    func testAChosenStyleIsNeverOverwritten() {
        XCTAssertFalse(LobbyView.shouldApplyDefault(current: .together,
                                                    derived: .rounds,
                                                    hasApplied: false))
        XCTAssertFalse(LobbyView.shouldApplyDefault(current: .freestyle,
                                                    derived: .together,
                                                    hasApplied: false))
        XCTAssertFalse(LobbyView.shouldApplyDefault(current: .together,
                                                    derived: .together,
                                                    hasApplied: false))
    }

    /// Freestyle is never derived (owner decision 1), so it can never be
    /// what a default writes — whatever the routine looks like.
    func testFreestyleIsNeverWrittenByTheDefault() {
        for current in SessionStyle.allCases {
            XCTAssertFalse(LobbyView.shouldApplyDefault(current: current,
                                                        derived: .freestyle,
                                                        hasApplied: false),
                           "current \(current.rawValue)")
        }
    }

    // MARK: - The rule and the law, composed
    //
    // The lobby joins `routine_exercises` to `exercises` and hands the pair
    // to `SessionStyleDefault`; these two cases are that whole path, minus
    // the join.

    func testACardioRoutineOnAFreshSessionWrites() {
        let derived = SessionStyleDefault.style(forExercises: [
            (category: "cardio", cardioMinutes: nil),
            (category: "cardio", cardioMinutes: 20)
        ])
        XCTAssertEqual(derived, .together)
        XCTAssertTrue(LobbyView.shouldApplyDefault(current: .rounds,
                                                   derived: derived,
                                                   hasApplied: false))
    }

    func testAStrengthRoutineOnAFreshSessionWritesNothing() {
        let derived = SessionStyleDefault.style(forExercises: [
            (category: "compound", cardioMinutes: nil),
            (category: "isolation", cardioMinutes: nil)
        ])
        XCTAssertEqual(derived, .rounds)
        XCTAssertFalse(LobbyView.shouldApplyDefault(current: .rounds,
                                                    derived: derived,
                                                    hasApplied: false))
    }

    /// An unresolved exercise contributes an empty category, which is neither
    /// cardio nor mobility — so a half-loaded catalog can only ever answer
    /// `.rounds`, and can never auto-switch a crew to Together behind their
    /// backs. This is the join's failure mode, asserted.
    func testAnUnresolvedCatalogNeverWrites() {
        let derived = SessionStyleDefault.style(forExercises: [
            (category: "", cardioMinutes: nil),
            (category: "", cardioMinutes: nil)
        ])
        XCTAssertEqual(derived, .rounds)
        XCTAssertFalse(LobbyView.shouldApplyDefault(current: .rounds,
                                                    derived: derived,
                                                    hasApplied: false))
    }

    // MARK: - The frame's world

    /// Frame 136 renders Rounds selected with the other two readable, and it
    /// must render the card at all — which needs `liftingStartedAt` nil.
    func testTheWaitingWorldIsRoundsBeforeStart() {
        XCTAssertEqual(LobbyFixtures.waiting.session.style, .rounds)
        XCTAssertNil(LobbyFixtures.waiting.session.liftingStartedAt)
    }
}
