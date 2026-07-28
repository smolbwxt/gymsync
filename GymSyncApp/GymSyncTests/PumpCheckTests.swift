import XCTest
@testable import GymSync

/// Pump Check P2 — the summary snapshot's JSON contract. The DB migration
/// (20260731000001) and the feed both read these exact snake_case keys; a
/// silent CodingKey drift would post snapshots the feed can't render.
final class PumpCheckTests: XCTestCase {

    private func makeSummary() -> PostSummary {
        PostSummary(
            durationSeconds: 2520,
            totalVolumeLbs: 7240,
            exercises: [
                .init(name: "Back Squat", equipment: "barbell", sets: [
                    .init(weightLbs: 225, reps: 5, isPR: true, isFailed: false),
                    .init(weightLbs: 225, reps: 5, isPR: true, isFailed: false),
                ]),
                .init(name: "Plank", equipment: "bodyweight", sets: [
                    .init(weightLbs: nil, reps: 1, isPR: false, isFailed: false),
                ]),
            ])
    }

    func testSummaryEncodesTheContractKeys() throws {
        let data = try JSONEncoder().encode(makeSummary())
        let json = String(decoding: data, as: UTF8.self)
        for key in ["duration_seconds", "total_volume_lbs", "exercises",
                    "weight_lbs", "reps", "is_pr", "is_failed",
                    "equipment", "name"] {
            XCTAssertTrue(json.contains("\"\(key)\""), "missing contract key \(key)")
        }
    }

    func testSummaryRoundTrips() throws {
        let original = makeSummary()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PostSummary.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// A server-shaped summary (numbers as JSON numbers, null weight for a
    /// bodyweight set) decodes — this is the exact shape the feed receives
    /// back from the jsonb column.
    func testServerShapedSummaryDecodes() throws {
        let json = """
        {"duration_seconds": 1800, "total_volume_lbs": 4500.5,
         "exercises": [{"name": "Bench Press", "equipment": "barbell",
                        "sets": [{"weight_lbs": 185, "reps": 8, "is_pr": false, "is_failed": false},
                                 {"weight_lbs": null, "reps": 10, "is_pr": false, "is_failed": true}]}]}
        """
        let summary = try JSONDecoder().decode(PostSummary.self, from: Data(json.utf8))
        XCTAssertEqual(summary.durationSeconds, 1800)
        XCTAssertEqual(summary.exercises.count, 1)
        XCTAssertEqual(summary.exercises[0].sets.count, 2)
        XCTAssertNil(summary.exercises[0].sets[1].weightLbs)
        XCTAssertTrue(summary.exercises[0].sets[1].isFailed)
    }
}
