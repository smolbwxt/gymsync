import XCTest
@testable import GymSync

/// `WorkoutPostRepository.create` against the real `workout_posts`, in the
/// repo's live-DB idiom.
///
/// CLEANUP IS THE LAW (TestSession.swift's header): the session comes from
/// `makeTempSoloSession()`, which pre-registers its own deletion, and the
/// post's deletion is registered BEFORE the write on top of that —
/// `workout_posts.session_id` is ON DELETE CASCADE
/// (20260731000001:22), so the post would go with the session anyway, and
/// belt-and-braces costs one line.
///
/// THE DATES THIS TEST CONTROLS ARE 2099. `created_at` is server-defaulted
/// and cannot be; the teardown is what keeps this account's feed clean.
final class WorkoutPostLiveRepositoryTests: XCTestCase {

    private let farFuture = Date(timeIntervalSince1970: 4_102_444_800) // 2100-01-01

    func testTheSnapshotColumnsRoundTrip() async throws {
        try await TestAuth.signInIfConfigured()
        let session = try await makeTempSoloSession()

        let trajectory = PostTrajectory(
            goalLine: "Bench 225 by Oct 18", weekNumber: 3, weekCount: 8,
            standing: .behind,
            chips: [.init(name: "CHEST", done: 8, target: 12, fill: nil)])
        let highlight = PostHighlight(kind: .pr, text: "PR — Back Squat",
                                      weightLbs: 235, reps: 3)
        let summary = PostSummary(durationSeconds: 2_520, totalVolumeLbs: 7_240,
                                  exercises: [], routineName: "Push day")

        var createdID: UUID?
        addTeardownBlock {
            if let createdID {
                try? await WorkoutPostRepository.delete(id: createdID, photoPath: nil)
            }
        }

        let post = try await WorkoutPostRepository.create(
            sessionID: session.id, summary: summary, photoJPEG: nil,
            includesHR: false, avgBpm: nil, maxBpm: nil,
            completedAt: farFuture.addingTimeInterval(-47 * 60),
            capturedLate: false, retakeCount: 2, highlight: highlight,
            trajectory: trajectory, goalID: nil, weekStartString: "2099-01-04",
            postedAt: farFuture)
        createdID = post.id

        XCTAssertEqual(post.retakeCount, 2)
        XCTAssertEqual(post.trajectory, trajectory)
        XCTAssertEqual(post.highlight, highlight)
        XCTAssertEqual(post.weekStartString, "2099-01-04")
        XCTAssertEqual(post.summary.routineName, "Push day")
        XCTAssertTrue(post.isLate, "47 minutes after the session is late, derived")

        // DEVIATION from the plan's draft, which measured the round-tripped
        // completion against `post.createdAt`. That assertion cannot hold:
        // `created_at` is server-defaulted to now() (2026) while every date
        // this test CONTROLS is 2099 (global constraint 6), so
        // `postedAt - completedAt` is negative, `elapsed` clamps to 0, and
        // `tag` correctly returns nil. Measured against the `postedAt` the
        // test actually passed, the assertion says the stronger true thing:
        // the column round-trips the instant precisely enough to re-derive
        // the spec's own 47-minute tag.
        let completedAt = post.completedAt
        let unwrapped = try XCTUnwrap(completedAt)   // bind, THEN unwrap
        XCTAssertEqual(PostLateness.tag(completedAt: unwrapped, postedAt: farFuture),
                       "posted 47 min after")
    }
}
