import XCTest
@testable import GymSync

/// Plan: docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md,
/// task D4. The windowing is pure and it is the only thing in the card that
/// can be wrong in a way a capture would not show — a card that quietly drew
/// weeks 1–3 of an eight-week block for an athlete in week six looks
/// perfectly well made.
final class LadderCardTests: XCTestCase {

    private func rows(_ count: Int, currentAt: Int) -> [LadderRow] {
        (0..<count).map { index in
            .init(weekNumber: index + 1, weekStartString: "2026-09-06",
                  targetText: "3 × 5 at \(190 + index * 5)", implication: nil,
                  status: index == currentAt ? .current
                        : (index < currentAt ? .met : .ahead),
                  isDeload: false, note: nil)
        }
    }

    func testTheWindowIsTheCurrentRungAndTheOneEitherSide() {
        let window = LadderCard.window(rows(8, currentAt: 3))
        XCTAssertEqual(window.map(\.weekNumber), [3, 4, 5])
    }

    func testTheWindowClampsAtBothEnds() {
        XCTAssertEqual(LadderCard.window(rows(8, currentAt: 0)).map(\.weekNumber),
                       [1, 2, 3])
        XCTAssertEqual(LadderCard.window(rows(8, currentAt: 7)).map(\.weekNumber),
                       [6, 7, 8])
    }

    func testAOneWeekLadderRendersOneRowAndDoesNotCrash() {
        XCTAssertEqual(LadderCard.window(rows(1, currentAt: 0)).count, 1)
        XCTAssertTrue(LadderCard.window([]).isEmpty)
    }

    func testALadderWithNoCurrentRungWindowsFromTheStart() {
        // Every rung ahead — a block booked but not yet begun.
        let allAhead = rows(8, currentAt: 0).map { row in
            LadderRow(weekNumber: row.weekNumber, weekStartString: row.weekStartString,
                      targetText: row.targetText, implication: row.implication,
                      status: .ahead, isDeload: row.isDeload, note: row.note)
        }
        XCTAssertEqual(LadderCard.window(allAhead).map(\.weekNumber), [1, 2, 3])
    }

    /// A ladder of exactly three is already its own window, and one of two
    /// must not be padded into three.
    func testAShortLadderIsItsOwnWindow() {
        XCTAssertEqual(LadderCard.window(rows(3, currentAt: 1)).map(\.weekNumber), [1, 2, 3])
        XCTAssertEqual(LadderCard.window(rows(2, currentAt: 1)).map(\.weekNumber), [1, 2])
    }

    /// The block the whole catalog renders: week 3 of 8, so the card shows
    /// weeks 2, 3 and 4 — the met week behind, the current rung, the one
    /// coming.
    func testTheFixtureBlockWindowsAroundItsCurrentRung() {
        let window = LadderCard.window(StubBlockGoalRepository.fixturePage.rows)
        XCTAssertEqual(window.map(\.weekNumber), [2, 3, 4])
        XCTAssertEqual(window[1].status, .current)
    }
}
