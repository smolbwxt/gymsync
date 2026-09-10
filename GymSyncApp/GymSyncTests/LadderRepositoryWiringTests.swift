import XCTest
@testable import GymSync

// MARK: - LadderRepositoryWiringTests
//
// Task review of Stream D, finding 2, and the controller's ruling on it: the
// ladder page must be pushed with the repository its PUSHER holds, not with a
// fresh `StubBlockGoalRepository()` picked up from a default argument.
//
// This is the defect shape these tests exist for. Today every side of the
// wiring is the stub, so a dropped injection looks perfectly correct — the
// fixture ladder renders and nothing errors. At I1, when `HomeView` is handed
// the live repository, Coach's line on Home would read the athlete's real
// ladder while the page one tap away rendered "Bench 225 by Oct 18" from the
// fixture. It fails silently, it fails with plausible data, and no capture
// would show it.
//
// A default argument cannot be asserted from the call site, so both hops were
// lifted into functions that RETURN the constructed view. The assertions below
// hold the view and look at the repository it is carrying.

/// A repository that answers nothing and exists only to be recognised.
///
/// Every read returns nil / false so that a test which accidentally rendered
/// a view holding one gets the empty state rather than fixture data — the
/// marker must never be mistakable for the stub it is checking against.
private struct MarkerBlockGoalRepository: BlockGoalRepository {
    func activeGoal() async -> BlockGoal? { nil }
    func ladder(goalID: UUID) async -> Ladder? { nil }
    func page(goalID: UUID) async -> LadderPageModel? { nil }
    @discardableResult func save(_ goal: BlockGoal) async -> Bool { false }
    func reLadder(goalID: UUID) async -> Ladder? { nil }
    @discardableResult
    func materialiseRung(goalID: UUID, weekStart: String) async -> WeeklyGoal? { nil }
}

final class LadderRepositoryWiringTests: XCTestCase {

    /// Home → the ladder page.
    func testTheLadderPageHomePushesCarriesHomesOwnRepository() {
        let home = HomeView(blockGoalRepository: MarkerBlockGoalRepository())
        let page = home.ladderPage(for: UUID())
        XCTAssertTrue(page.repository is MarkerBlockGoalRepository,
                      "the strip's destination must read the same block Coach's line does")
    }

    /// The ladder page → the block's schedule page.
    func testTheSchedulePageTheLadderPushesCarriesTheLaddersRepository() {
        let page = LadderPageView(goalID: UUID(), repository: MarkerBlockGoalRepository())
        XCTAssertTrue(page.blockSchedule().goalRepository is MarkerBlockGoalRepository,
                      "SEE THE BLOCK must not drop the repository the ladder was handed")
    }

    /// The block's schedule page → back to the ladder page. The third hop of
    /// the same loop, which was already right; pinned so it stays right.
    func testTheSchedulePagePushesTheLadderWithItsOwnRepository() {
        let schedule = ProgramScheduleView(goalRepository: MarkerBlockGoalRepository())
        XCTAssertTrue(schedule.ladderPage(for: UUID()).repository is MarkerBlockGoalRepository)
    }

    /// The whole loop in one assertion: Home → ladder → schedule → ladder.
    /// One repository, four hops, so I1 swaps them all by changing one
    /// default rather than by finding four call sites.
    func testOneRepositorySurvivesTheWholeLoop() {
        let home = HomeView(blockGoalRepository: MarkerBlockGoalRepository())
        let ladder = home.ladderPage(for: UUID())
        let schedule = ladder.blockSchedule()
        let ladderAgain = schedule.ladderPage(for: UUID())
        XCTAssertTrue(ladderAgain.repository is MarkerBlockGoalRepository)
    }

    /// The defaults are still the stub, so nothing that does not inject
    /// changed behaviour.
    func testTheUninjectedDefaultIsStillTheStub() {
        XCTAssertTrue(LadderPageView(goalID: UUID()).repository is StubBlockGoalRepository)
        XCTAssertTrue(ProgramScheduleView().goalRepository is StubBlockGoalRepository)
        XCTAssertTrue(HomeView().blockGoalRepository is StubBlockGoalRepository)
    }
}
