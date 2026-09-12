import XCTest
@testable import GymSync

/// Spec §1's card, as the strings it prints. The view is a layout of these.
final class PumpPostCardCopyTests: XCTestCase {

    func testTheTrajectoryLineIsOneSentenceWithThreeParts() {
        let trajectory = PostTrajectory(goalLine: "Bench 225 by Oct 18", weekNumber: 3,
                                        weekCount: 8, standing: .behind, chips: [])
        XCTAssertEqual(trajectory.line.components(separatedBy: " · ").count, 3)
        XCTAssertTrue(trajectory.line.hasSuffix("behind"),
                      "spec §1: no per-post hide — `behind` is said in the open")
    }

    func testAnOldRowKeepsItsBinaryLateTag() {
        let posted = Date(timeIntervalSince1970: 1_788_696_000)
        XCTAssertNil(PostLateness.tag(completedAt: nil, postedAt: posted),
                     "no completion means the card falls back to `is_late`")
    }

    /// Line 1's two tags, as the card composes them: the retake count above
    /// zero, and the precise lateness in place of the binary chip.
    func testTheAuthorRowsTwoTags() {
        let completed = Date(timeIntervalSince1970: 1_788_696_000)
        let posted = completed.addingTimeInterval(47 * 60)
        XCTAssertEqual(PostLateness.tag(completedAt: completed, postedAt: posted),
                       "posted 47 min after")
        XCTAssertEqual(PostLateness.retakeTag(2), "2 retakes")
        XCTAssertNil(PostLateness.retakeTag(0),
                     "a clean first take says nothing — \"0 retakes\" is a boast")
    }

    /// Line 4, rendered in the viewer's unit rather than frozen at post time.
    func testTheHighlightLineIsRenderedNotStored() {
        let highlight = PostHighlight(kind: .pr, text: "PR — Back Squat",
                                      weightLbs: 235, reps: 3)
        XCTAssertEqual(HighlightText.line(highlight, unit: .lbs),
                       "PR — Back Squat 235 lbs × 3")
        XCTAssertTrue(HighlightText.line(highlight, unit: .kg).contains("kg"))
    }
}
