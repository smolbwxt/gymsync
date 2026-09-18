import XCTest
@testable import GymSync

/// The Phase A deferral both session plan cards carried in their own comments,
/// pinned: the block's rung reaches the lobby and the warm-up, and falls back
/// to the routine's name exactly as those screens behaved when there is no
/// block.
final class SessionRungLineTests: XCTestCase {

    private func row(_ week: Int, _ target: String, implication: String? = nil)
        -> LadderRow {
        LadderRow(weekNumber: week,
                  weekStartString: "2026-09-14",
                  targetText: target,
                  implication: implication,
                  status: .current,
                  isDeload: false,
                  note: nil)
    }

    private func page(weekNumber: Int, rows: [LadderRow]) -> LadderPageModel {
        var model = LadderPageModel()
        model.headline = "Bench 225 by Oct 18"
        model.weekNumber = weekNumber
        model.weekCount = 8
        model.rows = rows
        return model
    }

    func testTheRungIsTheRowForThePagesOwnWeek() {
        let resolved = SessionRungLine.resolve(
            page: page(weekNumber: 3, rows: [row(1, "3 × 5 at 170"),
                                             row(2, "3 × 5 at 180"),
                                             row(3, "3 × 5 at 190")]),
            routineName: "Push day")
        XCTAssertEqual(resolved.line, "Week 3 · 3 × 5 at 190")
    }

    func testTheImplicationIsTheDetail() {
        let resolved = SessionRungLine.resolve(
            page: page(weekNumber: 3, rows: [row(3, "3 × 5 at 190",
                                                 implication: "≈ 214 e1RM")]),
            routineName: "Push day")
        XCTAssertEqual(resolved.detail, "≈ 214 e1RM")
    }

    func testARungWithNoImplicationHasNoDetail() {
        let resolved = SessionRungLine.resolve(
            page: page(weekNumber: 3, rows: [row(3, "12 chest sets")]),
            routineName: "Push day")
        XCTAssertEqual(resolved.line, "Week 3 · 12 chest sets")
        XCTAssertEqual(resolved.detail, "")
    }

    func testAPageWithNoRowForItsOwnWeekFallsBackToTheRoutine() {
        // The ladder was re-derived shorter than the page's week number — the
        // screens print what they printed before the rung existed rather than
        // a half-line about a rung nobody has.
        let resolved = SessionRungLine.resolve(
            page: page(weekNumber: 9, rows: [row(1, "3 × 5 at 170")]),
            routineName: "Push day")
        XCTAssertEqual(resolved.line, "Push day")
        XCTAssertEqual(resolved.detail, "")
    }

    func testNoPageIsTheRoutinesOwnName() {
        let resolved = SessionRungLine.resolve(page: nil, routineName: "Push day")
        XCTAssertEqual(resolved.line, "Push day")
        XCTAssertEqual(resolved.detail, "")
    }

    func testNoPageAndNoRoutineIsTheEmptyLineBothCardsAlreadyHide() {
        let resolved = SessionRungLine.resolve(page: nil, routineName: "")
        XCTAssertEqual(resolved.line, "")
        XCTAssertEqual(resolved.detail, "")
    }
}
