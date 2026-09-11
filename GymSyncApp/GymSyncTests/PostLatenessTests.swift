import XCTest
@testable import GymSync

/// Spec §2's precise lateness: elapsed from the session's COMPLETION to the
/// post, on three scales, with the binary `is_late` derived from the same two
/// timestamps.
final class PostLatenessTests: XCTestCase {

    private let completed = Date(timeIntervalSince1970: 1_788_696_000)
    private func posted(after seconds: TimeInterval) -> Date {
        completed.addingTimeInterval(seconds)
    }

    func testInsideTheWindowIsNotLateAndWearsNoTag() {
        XCTAssertFalse(PostLateness.isLate(completedAt: completed,
                                           postedAt: posted(after: 45), fallback: true))
        XCTAssertNil(PostLateness.tag(completedAt: completed, postedAt: posted(after: 45)))
    }

    func testTheSpecsOwnExample() {
        XCTAssertEqual(PostLateness.tag(completedAt: completed,
                                        postedAt: posted(after: 47 * 60)),
                       "posted 47 min after")
        XCTAssertTrue(PostLateness.isLate(completedAt: completed,
                                          postedAt: posted(after: 47 * 60), fallback: false))
    }

    func testTheThreeScales() {
        XCTAssertEqual(PostLateness.tag(completedAt: completed,
                                        postedAt: posted(after: 89 * 60)),
                       "posted 89 min after")
        XCTAssertEqual(PostLateness.tag(completedAt: completed,
                                        postedAt: posted(after: 90 * 60)),
                       "posted 1 hr after")
        XCTAssertEqual(PostLateness.tag(completedAt: completed,
                                        postedAt: posted(after: 50 * 3600)),
                       "posted 2 days after")
    }

    func testJustPastTheWindowStillReadsAsAMinuteNotAsZero() {
        XCTAssertEqual(PostLateness.tag(completedAt: completed,
                                        postedAt: posted(after: 61)),
                       "posted 1 min after")
    }

    func testNoCompletionFallsBackToTheCaptureFlagRatherThanGuessing() {
        XCTAssertTrue(PostLateness.isLate(completedAt: nil, postedAt: completed, fallback: true))
        XCTAssertFalse(PostLateness.isLate(completedAt: nil, postedAt: completed, fallback: false))
        XCTAssertNil(PostLateness.tag(completedAt: nil, postedAt: completed))
    }

    func testRetakesAreSilentAtZero() {
        XCTAssertNil(PostLateness.retakeTag(0))
        XCTAssertEqual(PostLateness.retakeTag(1), "1 retake")
        XCTAssertEqual(PostLateness.retakeTag(2), "2 retakes")
    }
}
