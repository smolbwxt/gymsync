import XCTest
@testable import GymSync

/// Decision 4's rule, branch by branch. `nil` is the normal case and most of
/// these assert it — a warm-up with no suggestion is the shipped screen.
final class WarmUpReadinessTests: XCTestCase {

    private let benchID = UUID(uuidString: "00000000-0000-4000-b000-0000000000b1")!
    private let flyID = UUID(uuidString: "00000000-0000-4000-b000-0000000000b2")!
    private let squatID = UUID(uuidString: "00000000-0000-4000-b000-0000000000b3")!

    private func row(_ id: UUID, _ name: String, muscle: String?,
                     sets: Int?, reps: String? = "5") -> WarmUpReadiness.PlanRow {
        .init(exerciseID: id, name: name, muscle: muscle,
              targetSets: sets, targetReps: reps)
    }

    /// The case that suggests: hot, recent, sore, and a plan that trains it.
    private func hotSignal() -> WarmUpReadiness.Signal {
        WarmUpReadiness.Signal(
            rungStatus: .current,
            reachesMilestone: true,
            lastSessionMeanRPE: 9,
            daysSinceLastSession: 1,
            openProbeMuscles: ["chest"],
            planRows: [row(benchID, "Bench Press", muscle: "chest", sets: 4),
                       row(flyID, "Cable Fly", muscle: "chest", sets: 3, reps: "12")])
    }

    // MARK: - The one case that suggests

    func testAnOpenProbeAndAHotRecentSessionSuggestsOneSetFewer() {
        let suggestion = WarmUpReadiness.suggestion(signal: hotSignal())
        XCTAssertEqual(suggestion?.exerciseID, benchID)
        XCTAssertEqual(suggestion?.setsInstead, 3)
    }

    func testTheSentenceNamesTheSignalItRead() {
        let read = WarmUpReadiness.suggestion(signal: hotSignal())?.read ?? ""
        XCTAssertTrue(read.contains("RPE 9"), read)
        XCTAssertTrue(read.contains("yesterday"), read)
        XCTAssertTrue(read.contains("chest"), read)
    }

    func testTheProposalSaysTodaysPrescriptionAndTheOneItOffers() {
        let suggestion = WarmUpReadiness.suggestion(signal: hotSignal())
        XCTAssertEqual(suggestion?.proposal,
                       "Today is 4 × 5 on Bench Press — want 3 × 5?")
    }

    func testARowWithNoRepTargetCountsSetsInstead() {
        var signal = hotSignal()
        signal.planRows = [row(benchID, "Bench Press", muscle: "chest",
                               sets: 4, reps: nil)]
        XCTAssertEqual(WarmUpReadiness.suggestion(signal: signal)?.proposal,
                       "Today is 4 sets of Bench Press — want 3?")
    }

    func testTheBiggestDoseOnASoreMuscleIsThePickAndATieGoesToPlanOrder() {
        var signal = hotSignal()
        signal.planRows = [row(flyID, "Cable Fly", muscle: "chest", sets: 4, reps: "12"),
                           row(benchID, "Bench Press", muscle: "chest", sets: 4)]
        XCTAssertEqual(WarmUpReadiness.suggestion(signal: signal)?.exerciseID, flyID)
    }

    // MARK: - Every branch that suggests nothing

    func testAMissedRungThatCannotReachSuggestsNothing() {
        // That conversation belongs to the ladder page's own proposal (§4),
        // even though every other term here says "scale it".
        var signal = hotSignal()
        signal.rungStatus = .missed
        signal.reachesMilestone = false
        XCTAssertNil(WarmUpReadiness.suggestion(signal: signal))
    }

    func testAMissedRungThatStillReachesIsNotTheLaddersConversation() {
        var signal = hotSignal()
        signal.rungStatus = .missed
        signal.reachesMilestone = true
        XCTAssertNotNil(WarmUpReadiness.suggestion(signal: signal))
    }

    func testTwoQuietDaysSuggestsNothing() {
        var signal = hotSignal()
        signal.daysSinceLastSession = 2
        XCTAssertNil(WarmUpReadiness.suggestion(signal: signal))
    }

    func testASessionThatWasNotHardSuggestsNothing() {
        var signal = hotSignal()
        signal.lastSessionMeanRPE = 8.4
        XCTAssertNil(WarmUpReadiness.suggestion(signal: signal))
        signal.lastSessionMeanRPE = WarmUpReadiness.hotMeanRPE
        XCTAssertNotNil(WarmUpReadiness.suggestion(signal: signal))
    }

    func testNoOpenProbeSuggestsNothing() {
        var signal = hotSignal()
        signal.openProbeMuscles = []
        XCTAssertNil(WarmUpReadiness.suggestion(signal: signal))
    }

    func testAProbeOnAMuscleTodayDoesNotTrainSuggestsNothing() {
        var signal = hotSignal()
        signal.openProbeMuscles = ["hamstrings"]
        XCTAssertNil(WarmUpReadiness.suggestion(signal: signal))
    }

    func testAnEmptyPlanSuggestsNothing() {
        var signal = hotSignal()
        signal.planRows = []
        XCTAssertNil(WarmUpReadiness.suggestion(signal: signal))
    }

    func testASingleSetRowIsNeverScaledToZero() {
        var signal = hotSignal()
        signal.planRows = [row(squatID, "Back Squat", muscle: "chest", sets: 1)]
        XCTAssertNil(WarmUpReadiness.suggestion(signal: signal))
    }

    func testARowTheCatalogDidNotResolveIsNotSuggestable() {
        var signal = hotSignal()
        signal.planRows = [row(benchID, "Bench Press", muscle: nil, sets: 4)]
        XCTAssertNil(WarmUpReadiness.suggestion(signal: signal))
    }

    func testASignalWithEveryTermNilSuggestsNothing() {
        XCTAssertNil(WarmUpReadiness.suggestion(signal: WarmUpReadiness.Signal()))
    }

    // MARK: - The wording helper

    func testAWholeRPEPrintsWithoutADecimal() {
        XCTAssertEqual(WarmUpReadiness.rpeText(9), "9")
        XCTAssertEqual(WarmUpReadiness.rpeText(8.5), "8.5")
    }

    // MARK: - What Accept applies

    /// Decision 5: Accept changes the prescription the plan card prints, and
    /// nothing else. The layered row goes through the one
    /// `SessionPlanRow.prescription(for:)` both screens print from.
    func testTheScaledRowPrintsTheReducedPrescription() throws {
        let exercise = RoutineExercise(
            id: UUID(), routineID: UUID(), exerciseID: benchID, position: 0,
            targetSets: 4, targetReps: "5", targetWeight: "225",
            restSeconds: nil, notes: nil)
        XCTAssertEqual(SessionPlanRow.prescription(for: exercise), "4 × 5 @ 225")

        // THROUGH `RoutineLayering`, not a fourth hand-copy of the order
        // (plan task S7): what this test pins is the PRESCRIPTION the card
        // prints. The layering ORDER is asserted in exactly one place,
        // `RoutineLayeringTests`, and nowhere else.
        let scale = TodaysScale(exerciseID: benchID, setsInstead: 3)
        let scaled = RoutineLayering.apply([exercise], todaysScale: scale)
        XCTAssertEqual(SessionPlanRow.prescription(for: try XCTUnwrap(scaled.first)),
                       "3 × 5 @ 225")
    }
}
