import XCTest
@testable import GymSync

/// The goal model's wire contract. `block_goals.target` is jsonb with
/// CAMELCASE keys and no `keyEncodingStrategy` (global constraint 11), and
/// absent fields must be ABSENT rather than null — the same round trip
/// `WeeklyGoalModelTests` proves for `weekly_goals.params`.
final class BlockGoalModelTests: XCTestCase {

    private func json(_ target: GoalTarget) throws -> [String: Any] {
        let data = try JSONEncoder().encode(target)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTargetEncodesOnlyTheFieldsAMetricUses() throws {
        let days = try json(GoalTarget(days: 4))
        XCTAssertEqual(days.keys.sorted(), ["days"])

        let lift = try json(GoalTarget(exerciseID: UUID(), targetWeightLbs: 225))
        XCTAssertEqual(lift.keys.sorted(), ["exerciseID", "targetWeightLbs"])

        let recovery = try json(GoalTarget(lissMinutes: 120, stretchingExercises: 6))
        XCTAssertEqual(recovery.keys.sorted(), ["lissMinutes", "stretchingExercises"])
    }

    func testTargetRoundTripsEveryField() throws {
        let full = GoalTarget(
            exerciseID: UUID(), targetWeightLbs: 225, targetReps: 10, loadLbs: 225,
            muscleTargets: ["chest": 12, "back": 12], activity: "run", distance: 15,
            days: 4, sessionType: "hiit", sessions: 3, lissMinutes: 120,
            stretchingExercises: 6, bodyWeightLbs: 180, bodyWeightRatePercent: -0.75,
            volumeLbs: 100_000, routineID: UUID(), targetSeconds: 2700)
        let data = try JSONEncoder().encode(full)
        XCTAssertEqual(try JSONDecoder().decode(GoalTarget.self, from: data), full)
    }

    func testEveryMetricKeyIsSnakeCaseAndUnique() {
        let keys = GoalMetric.allCases.map(\.rawValue)
        XCTAssertEqual(keys.count, Set(keys).count, "duplicate registry key")
        for key in keys {
            XCTAssertEqual(key, key.lowercased(), "registry keys are lowercase: \(key)")
            XCTAssertFalse(key.contains(" "), "registry keys have no spaces: \(key)")
        }
    }

    func testEveryPresetHasAMetricAndTenTilesAreOffered() {
        XCTAssertEqual(GoalPreset.allCases.count, 11)
        XCTAssertEqual(GoalPreset.tiles.count, 10)
        XCTAssertFalse(GoalPreset.tiles.contains(.repStrength),
                       "rep strength is Strength's second lever, not a tile (spec §2.3)")
        XCTAssertEqual(GoalPreset.strength.metric, .liftOneRepMax)
        XCTAssertEqual(GoalPreset.maintenance.metric, .weeklyMuscleSets)
        XCTAssertEqual(GoalPreset.recovery.metric, .stretchingExercisesPerWeek)
        XCTAssertFalse(GoalPreset.maintenance.asksForDate)
        XCTAssertFalse(GoalPreset.recovery.asksForDate)
        XCTAssertTrue(GoalPreset.strength.asksForDate)
    }

    func testDraftBecomesAGoalWithItsEnrollment() {
        let userID = UUID()
        let enrollmentID = UUID()
        let now = Date(timeIntervalSince1970: 1_788_696_000)
        let draft = BlockGoalDraft(metric: .liftOneRepMax,
                                   target: GoalTarget(targetWeightLbs: 225),
                                   byDate: now, preset: .strength)
        let goal = BlockGoal(draft: draft, userID: userID,
                             enrollmentID: enrollmentID, now: now)
        XCTAssertEqual(goal.enrollmentID, enrollmentID)
        XCTAssertEqual(goal.source, .user, "the door is the athlete choosing")
        XCTAssertEqual(goal.createdAt, now)
        XCTAssertEqual(goal.updatedAt, now)
        XCTAssertNil(goal.outcome)
    }
}
