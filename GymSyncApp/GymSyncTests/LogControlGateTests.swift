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
