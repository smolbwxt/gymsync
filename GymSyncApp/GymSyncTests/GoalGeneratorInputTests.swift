import XCTest
@testable import GymSync

final class GoalGeneratorInputTests: XCTestCase {

    private func draft(_ preset: GoalPreset, target: GoalTarget = GoalTarget()) -> BlockGoalDraft {
        BlockGoalDraft(metric: preset.metric, target: target, byDate: nil, preset: preset)
    }

    func testEachPresetChoosesItsBandAndTwoDeliberatelyDoNot() {
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.strength)), .strength)
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.repStrength)), .strength)
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.muscle)), .hypertrophy)
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.maintenance)), .hypertrophy)
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.endurance)), .conditioning)
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.benchmark)), .conditioning)
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.bodyComposition)), .weightLoss)
        XCTAssertNil(GoalGeneratorMapping.focus(for: draft(.consistency)),
                     "showing up more often is not a training emphasis")
        XCTAssertNil(GoalGeneratorMapping.focus(for: draft(.recovery)))
    }

    func testAStrengthGoalMakesItsLiftAFocusLiftWithoutErasingTheOthers() {
        let bench = UUID(), squat = UUID()
        var profile = TrainingProfile()
        profile.focusExerciseIDs = [squat]
        let inputs = profile.generatorInputs(
            durationWeeks: 8,
            goal: draft(.strength, target: GoalTarget(exerciseID: bench,
                                                      targetWeightLbs: 225)))
        XCTAssertTrue(inputs.focusExerciseIDs.contains(bench))
        XCTAssertTrue(inputs.focusExerciseIDs.contains(squat),
                      "the consult's own focus lift survives the goal")
        XCTAssertEqual(inputs.focus, .strength)
    }

    func testMaintenanceTargetsEveryMajorGroupAndSeedsTheirNumbers() {
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 6,
            goal: draft(.maintenance,
                        target: GoalTarget(muscleTargets: ["chest": 12, "back": 14,
                                                           "legs": 16, "arms": 10,
                                                           "shoulders": 10, "core": 8])))
        XCTAssertNil(inputs.focusMuscles,
                     "owner decision 9: Maintenance is every major group, which the "
                     + "generator already spells as nil")
        XCTAssertEqual(inputs.volumeTargets["chest"], 12)
        XCTAssertEqual(inputs.volumeTargets["core"], 8)
    }

    func testAMuscleGoalFocusesTheOneGroup() {
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 6,
            goal: draft(.muscle, target: GoalTarget(muscleTargets: ["chest": 16])))
        XCTAssertEqual(inputs.focusMuscles, ["chest"])
    }

    func testNoGoalLeavesEveryInputExactlyAsItWas() {
        let profile = TrainingProfile()
        let withoutGoal = profile.generatorInputs(durationWeeks: 8)
        let withNilGoal = profile.generatorInputs(durationWeeks: 8, goal: nil)
        XCTAssertEqual(withoutGoal.focus, withNilGoal.focus)
        XCTAssertEqual(withoutGoal.focusExerciseIDs, withNilGoal.focusExerciseIDs)
        XCTAssertEqual(withoutGoal.focusMuscles, withNilGoal.focusMuscles)
        XCTAssertEqual(withoutGoal.volumeTargets, withNilGoal.volumeTargets)
    }
}
