import XCTest
@testable import GymSync

/// The volume search: prescribe the middle, perturb, read what comes back.
///
/// Owner 2026-08-26: "Everyone responds to volume stimulus differently.
/// Let's prescribe middle of the road, and perturb the volume every couple
/// of weeks to see how performance improves. The data or the client will
/// tell us how it feels."
///
/// The evidence for searching rather than prescribing: Damas found 32% of
/// lifters grew better on high volume, 32% on low, 36% the same, and
/// Scarpelli's within-subject trial had the individualised leg beat a
/// fixed 22 sets/week by 9.9% CSA to 6.2%. No single number is right for
/// most people, and tuning the number does not fix that.
final class VolumeTitrationTests: XCTestCase {

    private let day: TimeInterval = 86_400
    private let now = Date()

    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * day) }

    private func outcome(_ daysBack: Int, reps: Double,
                         failed: Bool = false) -> VolumeTitration.SessionOutcome {
        .init(date: daysAgo(daysBack), repCompletion: reps,
              bestE1RM: nil, anyFailure: failed)
    }

    private func recovered(_ trainedDaysAgo: Int, inDays: Int,
                           state: VolumeTitration.RecoveryState = .tender)
    -> VolumeTitration.RecoveryObservation {
        .init(muscle: "chest", trainedAt: daysAgo(trainedDaysAgo),
              recoveredAt: daysAgo(trainedDaysAgo - inDays), lastState: state)
    }

    // MARK: - The owner's correction, pinned

    func testTrainingAtZeroToOneRIRIsNotByItselfAFatigueSignal() {
        // THE correction that changed this design. The corpus deload
        // trigger reads "most muscles at 0-1 RIR WITH broadly declining
        // performance", and an early draft treated the RIR half as a
        // warning. It is not: an athlete who chose EffortAppetite
        // .toFailure is PRESCRIBED 0-1 RIR and is training exactly as
        // intended. Owner: "I deliberately train for that exact thing to
        // happen."
        //
        // So: maximal effort, every rep landed, recovering in time. The
        // only correct answer is to add.
        XCTAssertEqual(GeneratorScience.EffortAppetite.toFailure.rirRange.low, 0,
                       "the effort knob really does prescribe 0-1 RIR")
        let move = VolumeTitration.decide(
            muscle: "chest", current: 16,
            outcomes: [outcome(3, reps: 1.0), outcome(7, reps: 1.0)],
            recovery: [recovered(3, inDays: 1), recovered(7, inDays: 1)],
            sessionGapDays: 4)
        guard case .add = move else {
            return XCTFail("training hard on purpose must not read as over-reaching: \(move)")
        }
    }

    // MARK: - Adding

    func testCleanRepsAndTimelyRecoveryAddsASet() {
        let move = VolumeTitration.decide(
            muscle: "chest", current: 14,
            outcomes: [outcome(3, reps: 1.0), outcome(7, reps: 1.0)],
            recovery: [recovered(3, inDays: 2), recovered(7, inDays: 2)],
            sessionGapDays: 4)
        XCTAssertEqual(move.delta, 1)
    }

    func testTheSearchStopsAtTheCeilingRatherThanClimbingForever() {
        let move = VolumeTitration.decide(
            muscle: "chest", current: VolumeTitration.ceilingWeeklySets,
            outcomes: [outcome(3, reps: 1.0), outcome(7, reps: 1.0)],
            recovery: [recovered(3, inDays: 1), recovered(7, inDays: 1)],
            sessionGapDays: 4)
        XCTAssertEqual(move.delta, 0)
    }

    func testAFailedSetBlocksTheAdd() {
        let move = VolumeTitration.decide(
            muscle: "chest", current: 14,
            outcomes: [outcome(3, reps: 1.0, failed: true), outcome(7, reps: 1.0)],
            recovery: [recovered(3, inDays: 1), recovered(7, inDays: 1)],
            sessionGapDays: 4)
        XCTAssertEqual(move.delta, 0)
    }

    // MARK: - Holding, and why recovery is measured against the SPLIT

    func testStillCarryingTheLastSessionHolds() {
        // Reps are landing, but the muscle is not back before the next
        // session for it. Room to add is not the same as reps landing.
        let move = VolumeTitration.decide(
            muscle: "chest", current: 16,
            outcomes: [outcome(3, reps: 1.0), outcome(7, reps: 1.0)],
            recovery: [recovered(3, inDays: 4), recovered(7, inDays: 4)],
            sessionGapDays: 4)
        XCTAssertEqual(move.delta, 0)
    }

    func testTheSameRecoveryTimeReadsDifferentlyOnDifferentSplits() {
        // Four days to recover is unremarkable training a muscle weekly
        // and a problem training it twice a week. An absolute soreness
        // threshold could not tell these apart, which is why duration is
        // measured against the SPLIT rather than against a constant.
        let outcomes = [outcome(3, reps: 1.0), outcome(10, reps: 1.0)]
        let recovery = [recovered(3, inDays: 4), recovered(10, inDays: 4)]

        let weekly = VolumeTitration.decide(
            muscle: "chest", current: 16, outcomes: outcomes,
            recovery: recovery, sessionGapDays: 7)
        let twiceWeekly = VolumeTitration.decide(
            muscle: "chest", current: 16, outcomes: outcomes,
            recovery: recovery, sessionGapDays: 3)

        XCTAssertEqual(weekly.delta, 1, "four days is fine when you train it weekly")
        XCTAssertEqual(twiceWeekly.delta, 0, "and not fine when you train it every three")
    }

    func testOneLongRecoveryIsAHardWeekNotADose() {
        // A single slow recovery must not move the prescription; two in a
        // row is a pattern.
        let move = VolumeTitration.decide(
            muscle: "chest", current: 16,
            outcomes: [outcome(3, reps: 1.0), outcome(7, reps: 1.0)],
            recovery: [recovered(3, inDays: 5), recovered(7, inDays: 1)],
            sessionGapDays: 4)
        XCTAssertEqual(move.delta, 1, "one bad week is not a dose")
    }

    // MARK: - Cutting and deloading

    func testRepsSlippingTwoSessionsRunningCutsVolume() {
        // The corpus's MRV rule, verbatim: "distinct performance decline
        // across two consecutive sessions for a muscle group signals it
        // has hit maximum recoverable volume."
        let move = VolumeTitration.decide(
            muscle: "chest", current: 20,
            outcomes: [outcome(3, reps: 0.7), outcome(7, reps: 0.85)],
            recovery: [recovered(3, inDays: 1), recovered(7, inDays: 1)],
            sessionGapDays: 4)
        XCTAssertLessThan(move.delta, 0)
    }

    func testDecliningAndNotRecoveringIsADeloadNotATrim() {
        // The corpus prescribes the bigger response when both signals
        // agree: "cut that muscle group's volume by half or take a
        // recovery week."
        let move = VolumeTitration.decide(
            muscle: "chest", current: 20,
            outcomes: [outcome(3, reps: 0.6), outcome(7, reps: 0.8)],
            recovery: [recovered(3, inDays: 5), recovered(7, inDays: 5)],
            sessionGapDays: 4)
        guard case .deload = move else { return XCTFail("expected a deload: \(move)") }
        XCTAssertEqual(VolumeTitration.apply(move, to: 20), 10, "half, not a trim")
    }

    func testADeloadMayGoUnderTheFloorButAWorkingPrescriptionMayNot() {
        // The floor exists because <12 weekly sets is the one condition
        // with a demonstrated penalty. A deload is the exception, and it
        // is time-boxed by being a deload.
        let deloaded = VolumeTitration.apply(
            .deload(reason: ""), to: 14)
        XCTAssertLessThan(deloaded, VolumeTitration.floorWeeklySets)

        let trimmed = VolumeTitration.apply(.cut(sets: 4, reason: ""), to: 14)
        XCTAssertEqual(trimmed, VolumeTitration.floorWeeklySets,
                       "an ordinary cut stops at the floor")
    }

    // MARK: - Bounds and starting point

    func testTheSearchNeverLeavesTheOwnersBounds() {
        for start in [10, 12, 18, 25, 30] {
            for move in [VolumeTitration.Move.add(sets: 5, reason: ""),
                         .cut(sets: 9, reason: "")] {
                let result = VolumeTitration.apply(move, to: start)
                XCTAssertGreaterThanOrEqual(result, VolumeTitration.floorWeeklySets)
                XCTAssertLessThanOrEqual(result, VolumeTitration.ceilingWeeklySets)
            }
        }
    }

    func testItStartsInTheMiddleOfTheGoalsOwnBand() {
        // "Prescribe middle of the road" - the search begins at the
        // midpoint of whatever band the athlete's goal already prescribes,
        // not at a number of its own.
        XCTAssertEqual(VolumeTitration.startingPoint(low: 12, high: 20), 16)
        XCTAssertEqual(VolumeTitration.startingPoint(low: 6, high: 10),
                       VolumeTitration.floorWeeklySets,
                       "a beginner band starts at the floor, never below it")
    }

    // MARK: - Not moving on thin data

    func testOneSessionIsNeverEnoughToMoveAnything() {
        // A bad night's sleep is indistinguishable from a dose that is too
        // big, if you only look once.
        let move = VolumeTitration.decide(
            muscle: "chest", current: 16,
            outcomes: [outcome(2, reps: 0.5)],
            recovery: [recovered(2, inDays: 6)],
            sessionGapDays: 3)
        XCTAssertEqual(move.delta, 0)
    }

    func testNoRecoveryHistoryDoesNotReadAsRecovered() {
        // Absence of a probe answer must not be treated as "recovered
        // fine" - that would let the search climb on no evidence.
        XCTAssertFalse(VolumeTitration.openTooLong([], gap: 3))
        let move = VolumeTitration.decide(
            muscle: "chest", current: 16,
            outcomes: [outcome(3, reps: 1.0), outcome(7, reps: 1.0)],
            recovery: [], sessionGapDays: 4)
        XCTAssertEqual(move.delta, 1,
                       "with no recovery data the reps decide, and they are clean")
    }

    // MARK: - Every move explains itself

    func testEveryMoveCarriesAReasonTheAthleteCouldRead() {
        // A volume change with no visible cause reads as the app being
        // erratic. Each branch has to say why.
        let moves: [VolumeTitration.Move] = [
            VolumeTitration.decide(muscle: "chest", current: 14,
                                   outcomes: [outcome(3, reps: 1.0), outcome(7, reps: 1.0)],
                                   recovery: [recovered(3, inDays: 1), recovered(7, inDays: 1)],
                                   sessionGapDays: 4),
            VolumeTitration.decide(muscle: "chest", current: 20,
                                   outcomes: [outcome(3, reps: 0.6), outcome(7, reps: 0.8)],
                                   recovery: [recovered(3, inDays: 5), recovered(7, inDays: 5)],
                                   sessionGapDays: 4),
            VolumeTitration.decide(muscle: "chest", current: 16,
                                   outcomes: [outcome(3, reps: 0.9)],
                                   recovery: [], sessionGapDays: 4),
        ]
        for move in moves {
            let reason: String
            switch move {
            case .add(_, let r), .hold(let r), .cut(_, let r), .deload(let r): reason = r
            }
            XCTAssertFalse(reason.isEmpty)
            XCTAssertGreaterThan(reason.count, 20, "a reason, not a label")
        }
    }

    // MARK: - Recovery states

    func testTenderCountsAsRecoveredButSoreDoesNot() {
        // Waiting for a perfectly fresh muscle would never close a probe
        // for anyone training hard, and mild residual soreness is normal.
        XCTAssertTrue(VolumeTitration.RecoveryState.fresh.isRecovered)
        XCTAssertTrue(VolumeTitration.RecoveryState.tender.isRecovered)
        XCTAssertFalse(VolumeTitration.RecoveryState.sore.isRecovered)
        XCTAssertFalse(VolumeTitration.RecoveryState.wrecked.isRecovered)
    }
}
