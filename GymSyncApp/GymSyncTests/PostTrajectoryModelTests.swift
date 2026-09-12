import XCTest
@testable import GymSync

/// The snapshot's wire contract. `workout_posts.highlight` and `.trajectory`
/// are jsonb with CAMELCASE keys and no `keyEncodingStrategy` (global
/// constraint 11), and a field a highlight does not use must be ABSENT rather
/// than null — the same round trip `WeeklyGoalModelTests` proves for
/// `weekly_goals.params`.
final class PostTrajectoryModelTests: XCTestCase {

    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testHighlightEncodesOnlyTheFieldsItUses() throws {
        let milestone = PostHighlight(kind: .milestone, text: "Lifetime total crossed",
                                      weightLbs: 1_000_000, reps: nil)
        XCTAssertEqual(try json(milestone).keys.sorted(), ["kind", "text", "weightLbs"])

        let pr = PostHighlight(kind: .pr, text: "PR — Back Squat",
                               weightLbs: 235, reps: 3)
        XCTAssertEqual(try json(pr).keys.sorted(), ["kind", "reps", "text", "weightLbs"])
        XCTAssertEqual(try json(pr)["kind"] as? String, "pr")
    }

    func testTopSetKindIsCamelCaseOnTheWire() throws {
        let top = PostHighlight(kind: .topSet, text: "Top set — Back Squat",
                                weightLbs: 225, reps: 5)
        XCTAssertEqual(try json(top)["kind"] as? String, "topSet")
    }

    func testTrajectoryRoundTrips() throws {
        let trajectory = PostTrajectory(
            goalLine: "Bench 225 by Oct 18", weekNumber: 3, weekCount: 8,
            standing: .onTrack,
            chips: [.init(name: "CHEST", done: 8, target: 12, fill: nil),
                    .init(name: "BENCH PRESS", done: 205, target: 225, fill: 0.25)])
        let data = try JSONEncoder().encode(trajectory)
        XCTAssertEqual(try JSONDecoder().decode(PostTrajectory.self, from: data), trajectory)
        XCTAssertEqual(try json(trajectory).keys.sorted(),
                       ["chips", "goalLine", "standing", "weekCount", "weekNumber"])
    }

    func testTheTrajectoryLineIsTheSpecsLine() {
        let trajectory = PostTrajectory(goalLine: "Bench 225 by Oct 18", weekNumber: 3,
                                        weekCount: 8, standing: .onTrack, chips: [])
        XCTAssertEqual(trajectory.line, "Bench 225 by Oct 18 · week 3 of 8 · on track")
    }

    func testBehindIsSaidPlainly() {
        let trajectory = PostTrajectory(goalLine: "Bench 225 by Oct 18", weekNumber: 5,
                                        weekCount: 8, standing: .behind, chips: [])
        XCTAssertEqual(trajectory.line, "Bench 225 by Oct 18 · week 5 of 8 · behind")
    }
}
