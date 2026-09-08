import XCTest
@testable import GymSync

final class LadderReadoutTests: XCTestCase {

    private let bench = UUID()

    /// A catalog row, built on the real initializer — the same private-helper
    /// idiom `WeeklyGoalProgressTests:18-25` uses. There is no shared
    /// `Exercise.fixture` in this repo and this task does not add one.
    private func exercise(_ id: UUID, primaryMuscle: String,
                          secondaryMuscles: [String]) -> Exercise {
        Exercise(id: id, name: "Bench Press", slug: "bench-press",
                 category: "compound", primaryMuscle: primaryMuscle,
                 secondaryMuscles: secondaryMuscles, equipment: "barbell",
                 defaultUnit: "lbs", demoVideoURL: nil)
    }

    private func program(weeks: [ProgramGenerator.Week],
                         percentOfMax: Double? = 80,
                         sets: Int = 3, repsLow: Int = 5) -> ProgramGenerator.Program {
        let exercise = ProgramGenerator.Exercise(
            exerciseID: bench, name: "Bench Press", sets: sets,
            repsLow: repsLow, repsHigh: repsLow + 3, restSeconds: 180,
            percentOfMax: percentOfMax, isMain: true)
        return ProgramGenerator.Program(days: [.init(name: "Push A", exercises: [exercise])],
                                        weeks: weeks, notes: [])
    }

    private func wave(_ count: Int, deloadAt: Int? = nil) -> [ProgramGenerator.Week] {
        (0..<count).map { index in
            .init(number: index + 1,
                  volumeMultiplier: index == deloadAt ? 0.5 : 1.0,
                  intensityMultiplier: index == deloadAt
                      ? 0.95 : 1.0 + Double(index) / Double(max(1, count - 1)) * 0.05,
                  isDeload: index == deloadAt,
                  note: nil)
        }
    }

    func testStrengthRungsAreThePrescribedLoadingAndTheDeloadIsARung() throws {
        let rungs = try XCTUnwrap(LadderReadout.strengthRungs(
            program: program(weeks: wave(8, deloadAt: 5)),
            exerciseID: bench, baselineE1RMLbs: 250, unit: .lbs))
        XCTAssertEqual(rungs.count, 8)
        // week 1 = 250 × 80 % × 1.0 = 200, rounded to the 5 lb grid
        XCTAssertEqual(try XCTUnwrap(rungs[0].targetWeightLbs), 200)
        XCTAssertLessThan(try XCTUnwrap(rungs[5].targetWeightLbs),
                          try XCTUnwrap(rungs[4].targetWeightLbs),
                          "the wave's deload appears as the lower rung it is")
        XCTAssertEqual(rungs[0].targetReps, 5, "the rung carries the prescribed reps")
    }

    func testAMainWithNoPercentOfMaxHasNoStrengthLadder() {
        XCTAssertNil(LadderReadout.strengthRungs(
            program: program(weeks: wave(4), percentOfMax: nil),
            exerciseID: bench, baselineE1RMLbs: 250, unit: .lbs),
            "a bodyweight main carries no %1RM, and the ladder does not invent one")
    }

    func testALiftTheBlockDoesNotTrainAsAMainHasNoLadder() {
        XCTAssertNil(LadderReadout.strengthRungs(
            program: program(weeks: wave(4)), exerciseID: UUID(),
            baselineE1RMLbs: 250, unit: .lbs))
    }

    func testRepStrengthClimbsRepsAtAFixedLoadAndEasesOnADeload() throws {
        let rungs = try XCTUnwrap(LadderReadout.repStrengthRungs(
            program: program(weeks: wave(6, deloadAt: 3)),
            exerciseID: bench, loadLbs: 225, currentReps: 5, targetReps: 10))
        XCTAssertEqual(rungs.count, 6)
        XCTAssertEqual(rungs.last?.targetReps, 10)
        XCTAssertEqual(try XCTUnwrap(rungs[0].targetWeightLbs), 225,
                       "the load is fixed; the reps are the rung")
        XCTAssertLessThanOrEqual(try XCTUnwrap(rungs[3].targetReps),
                                 try XCTUnwrap(rungs[2].targetReps))
    }

    func testMuscleRungsScaleWithTheWavesVolumeMultiplier() throws {
        let catalog = [bench: exercise(bench, primaryMuscle: "chest",
                                       secondaryMuscles: ["triceps"])]
        let rungs = LadderReadout.muscleRungs(
            program: program(weeks: wave(4, deloadAt: 2), sets: 4),
            catalog: catalog, groups: [.chest, .arms])
        XCTAssertEqual(rungs.count, 4)
        XCTAssertEqual(rungs[0].muscleTargets?["chest"], 4, "4 sets, full primary credit")
        XCTAssertEqual(rungs[0].muscleTargets?["arms"], 2, "0.5 secondary credit × 4 sets")
        XCTAssertEqual(rungs[2].muscleTargets?["chest"], 2, "the deload halves the week")
    }

    func testConstraintsCarryTheWavesDeloadAndTaper() {
        var weeks = wave(8, deloadAt: 5)
        weeks[7].volumeMultiplier = 0.5      // the strength taper
        let constraints = LadderReadout.constraints(
            program: program(weeks: weeks), unit: .lbs)
        XCTAssertEqual(constraints.deloadWeeks, [5])
        XCTAssertEqual(constraints.taperWeeks, [7])
    }

    /// THE EPLEY NUMBER, not the spec's prose. The plan's snippet expected
    /// `≈ 214 e1RM`, which is Brzycki's 36/(37−r); `StatMath.estimatedOneRepMax`
    /// is the app's one 1RM formula and it is Epley — 190 × (1 + 5/30) = 221.67,
    /// which rounds to 222. Corrected here per the controller's ruling: the
    /// helper is the authority, and it is never forked for one surface.
    func testRungTextIsSpelledOnceForEverySurface() {
        let (text, implication) = LadderReadout.strengthRungText(
            GoalTarget(targetWeightLbs: 190, targetReps: 5), sets: 3, unit: .lbs)
        XCTAssertEqual(text, "3 × 5 at 190")
        XCTAssertEqual(implication, "≈ 222 e1RM")
    }

    /// The implication is the SAME arithmetic `StatMath` does, not a copy of it
    /// — asserted against the helper rather than against a second literal, so
    /// the two can never drift and this test cannot pass a forked formula.
    func testTheImplicationIsStatMathsOwnAnswer() {
        let (_, implication) = LadderReadout.strengthRungText(
            GoalTarget(targetWeightLbs: 225, targetReps: 3), sets: 5, unit: .lbs)
        let expected = Units.wholeNumber(
            pounds: StatMath.estimatedOneRepMax(weight: 225, reps: 3), unit: .lbs)
        XCTAssertEqual(implication, "≈ \(expected) e1RM")
    }

    func testARungWithNoLoadOrRepsSaysSoRatherThanPrintingZero() {
        let (text, implication) = LadderReadout.strengthRungText(
            GoalTarget(days: 3), sets: 3, unit: .lbs)
        XCTAssertEqual(text, "—")
        XCTAssertNil(implication)
    }
}
