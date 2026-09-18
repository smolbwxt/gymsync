import XCTest
@testable import GymSync

/// `LogControlGate.isMine(style:isMyTurn:)` — the pure predicate behind
/// `SessionLiveView.logControlIsMine` (plan task S5), extracted for fix
/// round 4 / finding 1 (ruling R-B21): Together and Freestyle mounted a log
/// control that could never enable, because the entry that fills it was
/// still gated on a turn those two styles never have. This is the one law
/// every prefill call site and the log foot's `isDisabled` now share, so a
/// regression here would strand every lifter in either style the same way
/// again.
final class LogControlGateTests: XCTestCase {

    /// Rounds is a rotation — the entry belongs to whoever holds the turn,
    /// and nobody else's.
    func testRoundsGatesOnTheTurn() {
        XCTAssertTrue(LogControlGate.isMine(style: .rounds, isMyTurn: true))
        XCTAssertFalse(LogControlGate.isMine(style: .rounds, isMyTurn: false))
    }

    /// Together and Freestyle have no turn at all (spec §3.3) — the
    /// predicate answers `true` for every lifter regardless of whatever
    /// `isMyTurn` happens to read, which is exactly what "never turn-gated"
    /// means.
    func testTogetherAndFreestyleAreNeverTurnGated() {
        for style: SessionStyle in [.together, .freestyle] {
            XCTAssertTrue(LogControlGate.isMine(style: style, isMyTurn: true))
            XCTAssertTrue(LogControlGate.isMine(style: style, isMyTurn: false))
        }
    }
}

/// `LogFollowUp.calls(for:)` — which RPCs a PERSISTED set runs, by style
/// (ruling R-B22, fix round 5). The final whole-branch review found the log
/// path calling `advance_turn` in all three styles: in Together and Freestyle
/// every lifter who was neither the current turn holder nor the organizer got
/// a P0001 raise on a set that was already in the database, an entry card that
/// stayed up, and a second tap's worth of duplicate. The style rule lives here
/// so the log path cannot quietly regrow a condition of its own.
final class LogFollowUpTests: XCTestCase {

    /// Rounds runs both, in this order: the turn moves first, so the round
    /// that may close behind it already points at the next lifter.
    func testRoundsAdvancesTheTurnThenOffersTheRound() {
        XCTAssertEqual(LogFollowUp.calls(for: .rounds), [.advanceTurn, .advanceRound])
    }

    /// Together and Freestyle have no turns and no rounds (spec §3.3) — the
    /// insert is the whole transaction, and there is nothing to call after it.
    func testTogetherAndFreestyleRunNothingAfterTheInsert() {
        XCTAssertEqual(LogFollowUp.calls(for: .together), [])
        XCTAssertEqual(LogFollowUp.calls(for: .freestyle), [])
    }

    /// The offline path records a DEFERRED `advance_turn`, so it asks this
    /// same question rather than carrying a second copy of the rule — a
    /// Together lifter's queued set must not fire a rotation call on
    /// reconnect.
    func testOnlyRoundsEverRecordsADeferredTurnAdvance() {
        XCTAssertTrue(LogFollowUp.calls(for: .rounds).contains(.advanceTurn))
        for style: SessionStyle in [.together, .freestyle] {
            XCTAssertFalse(LogFollowUp.calls(for: style).contains(.advanceTurn))
        }
    }

    /// Every style is answered — a fourth one added later fails here rather
    /// than silently inheriting the rotation's calls.
    func testEveryStyleHasAnAnswer() {
        for style in SessionStyle.allCases {
            let calls = LogFollowUp.calls(for: style)
            XCTAssertEqual(calls.isEmpty, style != .rounds,
                           "\(style.rawValue) needs its own ruling before it can log")
        }
    }
}
