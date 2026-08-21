import XCTest
@testable import GymSync

/// Body context (field report #22): athlete-stated measurements must
/// provably change output — the no-dead-knobs law. BMI math, the
/// impact-caution thresholds, the generator demotion (which gives the
/// previously-dead `impact` label its first consumer), and the legacy
/// payload contract are each pinned.
final class BodyContextTests: XCTestCase {

    private func cat(_ rank: Int, _ name: String, impact: String = "none",
                     joints: [String] = [], score: Int = 7)
        -> ProgramGenerator.CatalogExercise {
        var c = ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0005-%012d", rank))!,
            name: name, primaryMuscle: "quads", secondaryMuscles: [],
            category: "compound", equipment: "bodyweight", movementPattern: "squat",
            rank: rank)
        c.focusScores = ["conditioning": score, "strength": score]
        c.complexity = 2
        c.impact = impact
        c.jointStress = joints
        return c
    }

    private let slot = ProgramGenerator.Slot.pattern("squat", main: true)

    func testBMIAndCautionThresholds() {
        var p = TrainingProfile()
        XCTAssertNil(p.bmi)
        XCTAssertFalse(p.impactCaution)
        p.bodyweightLbs = 250
        XCTAssertNil(p.bmi, "height missing — no BMI, no caution")
        p.heightInches = 70
        XCTAssertEqual(p.bmi!, 35.87, accuracy: 0.01)
        XCTAssertTrue(p.impactCaution)
        p.bodyweightLbs = 160
        XCTAssertFalse(p.impactCaution)
        p.bodyFatPercent = 31
        XCTAssertTrue(p.impactCaution, "bodyfat alone can trip the line")
    }

    func testImpactCautionDemotesHighImpactWork() {
        // The dead-label resurrection: `impact` has never had a consumer.
        let jump = cat(1, "Jump Squattish Thing", impact: "high", score: 9)
        let step = cat(2, "Step-Uppish Thing", impact: "low", score: 7)
        let without = ProgramGenerator.select(
            slot: slot, from: [jump, step], excluding: [],
            focus: .conditioning, focusMuscles: nil, experience: .intermediate)
        XCTAssertEqual(without?.name, "Jump Squattish Thing",
                       "no caution: the better scorer wins as always")
        let with_ = ProgramGenerator.select(
            slot: slot, from: [jump, step], excluding: [],
            focus: .conditioning, focusMuscles: nil, experience: .intermediate,
            impactCaution: true)
        XCTAssertEqual(with_?.name, "Step-Uppish Thing",
                       "caution on: landings outrank the score")
    }

    func testNamedJointBeatsGeneralImpactRisk() {
        // Gate ordering: a lift stressing a CAUTIONED joint sorts behind
        // a merely high-impact one — specificity wins.
        let jump = cat(1, "Jump Squattish Thing", impact: "high")
        let kneeLoad = cat(2, "Knee Grinder", joints: ["knee"])
        let pick = ProgramGenerator.select(
            slot: slot, from: [kneeLoad, jump], excluding: [],
            focus: .conditioning, focusMuscles: nil, experience: .intermediate,
            cautionJoints: ["knee"], impactCaution: true)
        XCTAssertEqual(pick?.name, "Jump Squattish Thing")
    }

    func testImpactCautionStillFillsASlotAlone() {
        let jump = cat(1, "Jump Squattish Thing", impact: "high")
        let pick = ProgramGenerator.select(
            slot: slot, from: [jump], excluding: [],
            focus: .conditioning, focusMuscles: nil, experience: .intermediate,
            impactCaution: true)
        XCTAssertEqual(pick?.name, "Jump Squattish Thing",
                       "soft gate — never a hole")
    }

    func testProfileFlowsCautionIntoInputsWithAdvisoryNote() {
        var p = TrainingProfile()
        p.bodyweightLbs = 260
        p.heightInches = 69
        let inputs = p.generatorInputs(durationWeeks: 8)
        XCTAssertTrue(inputs.impactCaution)
        XCTAssertTrue(inputs.advisoryNotes.contains { $0.contains("High-impact") },
                      "the athlete hears WHY — never a silent edit")
        var lean = TrainingProfile()
        lean.bodyweightLbs = 170
        lean.heightInches = 69
        XCTAssertFalse(lean.generatorInputs(durationWeeks: 8).impactCaution)
    }

    func testLegacyPayloadDecodesWithoutBodyFields() {
        // Saved profiles predate these keys; optionals decode as absent.
        let encoded = try! JSONEncoder().encode(TrainingProfile())
        let decoded = try! JSONDecoder().decode(TrainingProfile.self, from: encoded)
        XCTAssertNil(decoded.bodyweightLbs)
        XCTAssertNil(decoded.bodyFatPercent)
        XCTAssertFalse(decoded.impactCaution)
    }
}
