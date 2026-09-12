import XCTest
@testable import GymSync

/// Spec §2's precise lateness: elapsed from the session's COMPLETION to the
/// post, on three scales.
///
/// THE BINARY `is_late` IS NOT TESTED HERE ANY MORE. It was, while the client
/// derived it; review fix 6 moved that derivation into a BEFORE INSERT trigger
/// (`20260912000002_workout_posts_is_late_trigger.sql`) so the flag and the
/// `created_at` the tag is measured against come from one clock, and
/// `PostLateness.isLate` was deleted with its last caller. Its three rules —
/// late past the window, not late inside it, and the client's own flag kept
/// when there is no completion to measure from — are asserted in
/// `supabase/tests/workout_posts_test.sql` (9h, 9i, 9j), against the clock
/// that actually decides them.
final class PostLatenessTests: XCTestCase {

    private let completed = Date(timeIntervalSince1970: 1_788_696_000)
    private func posted(after seconds: TimeInterval) -> Date {
        completed.addingTimeInterval(seconds)
    }

    func testInsideTheWindowWearsNoTag() {
        XCTAssertNil(PostLateness.tag(completedAt: completed, postedAt: posted(after: 45)),
                     "a prompt post wears no tag at all")
    }

    func testTheSpecsOwnExample() {
        XCTAssertEqual(PostLateness.tag(completedAt: completed,
                                        postedAt: posted(after: 47 * 60)),
                       "posted 47 min after")
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

    /// No completion is an ABSENCE, never a zero: the card prints no elapsed
    /// tag and falls back to the row's own `is_late`. (What that boolean
    /// should be in this case is the trigger's business now — pgTAP 9j.)
    func testNoCompletionMeansNoTagRatherThanZeroMinutes() {
        XCTAssertNil(PostLateness.elapsed(completedAt: nil, postedAt: completed))
        XCTAssertNil(PostLateness.tag(completedAt: nil, postedAt: completed))
    }

    func testRetakesAreSilentAtZero() {
        XCTAssertNil(PostLateness.retakeTag(0))
        XCTAssertEqual(PostLateness.retakeTag(1), "1 retake")
        XCTAssertEqual(PostLateness.retakeTag(2), "2 retakes")
    }
}
