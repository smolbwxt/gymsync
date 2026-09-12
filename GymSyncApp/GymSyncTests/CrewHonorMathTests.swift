import XCTest
@testable import GymSync

/// Spec §3's crown: frequency, decaying, tie-broken to the earlier achiever.
final class CrewHonorMathTests: XCTestCase {

    private func row(_ username: String, _ sessions: Int,
                     daysAgo: Double) -> CrewHonorRow {
        CrewHonorRow(userID: UUID(), username: username, sessions: sessions,
                     reachedAt: Date(timeIntervalSince1970: 1_788_696_000
                                     - daysAgo * 86_400))
    }

    func testTheCrownIsTheMostSessions() {
        let crown = CrewHonorMath.crown([row("sam", 9, daysAgo: 1),
                                         row("dana", 4, daysAgo: 2)])
        XCTAssertEqual(crown, CrewHonor(username: "sam", sessions: 9))
    }

    func testATieGoesToTheEarlierAchiever() {
        // Dana reached 6 four days ago; Sam reached 6 yesterday.
        let crown = CrewHonorMath.crown([row("sam", 6, daysAgo: 1),
                                         row("dana", 6, daysAgo: 4)])
        XCTAssertEqual(crown?.username, "dana")
    }

    func testACrewAtRestHasNoCrown() {
        XCTAssertNil(CrewHonorMath.crown([]))
        XCTAssertNil(CrewHonorMath.crown([row("sam", 0, daysAgo: 1)]))
    }

    func testTheLineIsTheSpecsLine() {
        XCTAssertEqual(CrewHonorMath.line(CrewHonor(username: "sam", sessions: 9)),
                       "MOST CONSISTENT · SAM · 9 SESSIONS")
    }

    func testOneSessionIsSingular() {
        XCTAssertEqual(CrewHonorMath.line(CrewHonor(username: "dana", sessions: 1)),
                       "MOST CONSISTENT · DANA · 1 SESSION")
    }
}
