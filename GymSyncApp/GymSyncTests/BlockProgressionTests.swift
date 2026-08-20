import XCTest
@testable import GymSync

/// Pure coverage for the session-to-session progression engine. Each test is
/// one corpus rule made executable — double progression, the two-tier stall
/// model, and the doctrine interactions (failure counting, penalty sets,
/// warmup exclusion) that could silently corrupt a decision.
final class BlockProgressionTests: XCTestCase {

    private let user = UUID()
    private let lift = UUID()

    private func set(session: UUID, index: Int, reps: Int, weight: Decimal,
                     failed: Bool = false, penalty: Bool = false,
                     daysAgo: Double = 0) -> SetLog {
        SetLog(id: UUID(), userID: user, sessionID: session, exerciseID: lift,
               setIndex: index, reps: reps, weight: weight, rpe: nil,
               isFailed: failed, isPenalty: penalty, note: nil,
               loggedAt: Date(timeIntervalSinceNow: -daysAgo * 86_400))
    }

    private func session(reps: [Int], weight: Decimal, daysAgo: Double,
                         failed: Bool = false) -> [SetLog] {
        let id = UUID()
        return reps.enumerated().map { i, r in
            set(session: id, index: i, reps: r, weight: weight,
                failed: failed && i == reps.count - 1, daysAgo: daysAgo)
        }
    }

    // MARK: Double progression

    func testToppedRangeAdvancesLoadAndCompoundStepIsPercentBased() {
        // Lower-body compound at 200 lb, every working set at the 12 ceiling
        // of 8-12 → +5% = +10 lb.
        let history = session(reps: [12, 12, 12], weight: 200, daysAgo: 2)
        let decision = BlockProgression.decide(
            history: history, repsLow: 8, repsHigh: 12,
            isLowerBody: true, isIsolation: false)
        guard case .advanceLoad(let pounds, let note) = decision else {
            return XCTFail("topped range must advance load, got \(decision)")
        }
        XCTAssertEqual(pounds, 210)
        XCTAssertFalse(note.summary.isEmpty)
    }

    func testIsolationAdvancesBySmallestIncrementNotPercent() {
        // 3DMJ rule: a percent jump is too coarse on isolation loads. Same
        // 200 lb, but isolation → exactly one 5 lb increment, not +10.
        let history = session(reps: [12, 12, 12], weight: 200, daysAgo: 2)
        let decision = BlockProgression.decide(
            history: history, repsLow: 8, repsHigh: 12,
            isLowerBody: true, isIsolation: true)
        guard case .advanceLoad(let pounds, _) = decision else {
            return XCTFail("expected advanceLoad, got \(decision)")
        }
        XCTAssertEqual(pounds, 205)
    }

    func testMidRangeChasesOneRepOnWeakestSet() {
        let history = session(reps: [10, 9], weight: 100, daysAgo: 1)
        let decision = BlockProgression.decide(
            history: history, repsLow: 8, repsHigh: 12,
            isLowerBody: false, isIsolation: false)
        guard case .advanceReps(let target, _) = decision else {
            return XCTFail("mid-range must advance reps, got \(decision)")
        }
        XCTAssertEqual(target, 10, "weakest set was 9 — aim one higher")
    }

    // MARK: Tier 1 — fatigue deload (propose, never apply)

    func testTwoSessionsUnderFloorProposesTenPercentDeload() {
        let history = session(reps: [6, 7], weight: 100, daysAgo: 1)
                    + session(reps: [7, 6], weight: 100, daysAgo: 4)
        let decision = BlockProgression.decide(
            history: history, repsLow: 8, repsHigh: 12,
            isLowerBody: false, isIsolation: false)
        guard case .proposeDeload(let pounds, let note) = decision else {
            return XCTFail("two floor misses must propose a deload, got \(decision)")
        }
        XCTAssertEqual(pounds, 90, "10% off 100 lb, on a loadable increment")
        XCTAssertTrue(note.reason.contains("nothing changes unless you accept"),
                      "a deload is a proposal, never an action")
    }

    func testSelfDeloadHoldsInsteadOfProposingASecondCut() {
        // Athlete already cut 100 → 80 on their own; Coach must not stack
        // another 10% on top of their correction.
        let history = session(reps: [6, 6], weight: 80, daysAgo: 1)
                    + session(reps: [7, 6], weight: 100, daysAgo: 4)
        let decision = BlockProgression.decide(
            history: history, repsLow: 8, repsHigh: 12,
            isLowerBody: false, isIsolation: false)
        guard case .hold(let note) = decision else {
            return XCTFail("self-deload must hold, got \(decision)")
        }
        XCTAssertNotNil(note, "the hold still explains itself")
    }

    func testOneBadSessionIsNotAFatigueSignal() {
        let history = session(reps: [6, 6], weight: 100, daysAgo: 1)
                    + session(reps: [10, 10], weight: 100, daysAgo: 4)
        let decision = BlockProgression.decide(
            history: history, repsLow: 8, repsHigh: 12,
            isLowerBody: false, isIsolation: false)
        if case .proposeDeload = decision {
            XCTFail("a single miss must never trigger a deload proposal")
        }
    }

    // MARK: Tier 2 — true stall (BBM: weeks, not sessions; e1RM, not reps)

    func testNoE1RMBestInThreeWeeksFlagsTrueStall() {
        // Best session 30 days ago (100×10); four sessions since, all worse
        // (100×8) but above the rep floor of 5 — so tier 1 stays quiet and
        // the slow signal is the one that fires.
        var history = session(reps: [10, 10], weight: 100, daysAgo: 30)
        for days in [20.0, 13, 6, 0.5] {
            history += session(reps: [8, 8], weight: 100, daysAgo: days)
        }
        let decision = BlockProgression.decide(
            history: history, repsLow: 5, repsHigh: 12,
            isLowerBody: false, isIsolation: false)
        guard case .flagStall(let note) = decision else {
            return XCTFail("3+ weeks with no e1RM best must flag, got \(decision)")
        }
        XCTAssertTrue(note.reason.contains("swap") || note.reason.contains("volume"),
                      "a true stall points at programming, not another load tweak")
    }

    func testRecentPRSuppressesStallFlag() {
        var history = session(reps: [10, 10], weight: 100, daysAgo: 30)
        history += session(reps: [11, 10], weight: 100, daysAgo: 2)  // fresh best
        history += session(reps: [8, 8], weight: 100, daysAgo: 0.5)
        let decision = BlockProgression.decide(
            history: history, repsLow: 5, repsHigh: 12,
            isLowerBody: false, isIsolation: false)
        if case .flagStall = decision {
            XCTFail("an e1RM best two days ago is the opposite of a stall")
        }
    }

    // MARK: Doctrine interactions

    func testFailedFinalRepDoesNotCountTowardToppingTheRange() {
        // 12 logged with FAIL = 11 completed (failure doctrine) → still
        // inside the 8-12 range, so reps advance, not load.
        let history = session(reps: [12, 12, 12], weight: 100, daysAgo: 1,
                              failed: true)
        let decision = BlockProgression.decide(
            history: history, repsLow: 8, repsHigh: 12,
            isLowerBody: false, isIsolation: false)
        guard case .advanceReps = decision else {
            return XCTFail("a failed 12th rep is 11 completed — not topped, got \(decision)")
        }
    }

    func testPrescribedFailureFinisherIsExcludedFromTargets() {
        // 12, 12, then a prescribed to-failure set of 3 — the finisher is
        // the assignment fulfilled, never evidence against the range.
        let id = UUID()
        let history = [
            set(session: id, index: 0, reps: 12, weight: 100, daysAgo: 1),
            set(session: id, index: 1, reps: 12, weight: 100, daysAgo: 1),
            set(session: id, index: 2, reps: 3, weight: 100, daysAgo: 1),
        ]
        let decision = BlockProgression.decide(
            history: history, repsLow: 8, repsHigh: 12,
            isLowerBody: false, isIsolation: false, lastSetToFailure: true)
        guard case .advanceLoad = decision else {
            return XCTFail("the to-failure finisher must not veto the top-out, got \(decision)")
        }
    }

    func testWarmupSetsCannotVetoAToppedRange() {
        // 45 lb × 5 warmup would drag minReps to 5 if counted; the 90%
        // working-set cutoff excludes it.
        let id = UUID()
        let history = [
            set(session: id, index: 0, reps: 5, weight: 45, daysAgo: 1),
            set(session: id, index: 1, reps: 12, weight: 100, daysAgo: 1),
            set(session: id, index: 2, reps: 12, weight: 100, daysAgo: 1),
        ]
        let decision = BlockProgression.decide(
            history: history, repsLow: 8, repsHigh: 12,
            isLowerBody: false, isIsolation: false)
        guard case .advanceLoad = decision else {
            return XCTFail("warmups are not working sets, got \(decision)")
        }
    }

    func testPenaltySetsAreInvisible() {
        let id = UUID()
        let history = [
            set(session: id, index: 0, reps: 9, weight: 100, daysAgo: 1),
            set(session: id, index: 1, reps: 20, weight: 100, penalty: true, daysAgo: 1),
        ]
        let decision = BlockProgression.decide(
            history: history, repsLow: 8, repsHigh: 12,
            isLowerBody: false, isIsolation: false)
        guard case .advanceReps(let target, _) = decision else {
            return XCTFail("expected advanceReps, got \(decision)")
        }
        XCTAssertEqual(target, 10, "the 20-rep penalty set must not exist to the engine")
    }

    func testNoHistoryHoldsQuietly() {
        let decision = BlockProgression.decide(
            history: [], repsLow: 8, repsHigh: 12,
            isLowerBody: false, isIsolation: false)
        guard case .hold(let note) = decision else {
            return XCTFail("no data → no opinion, got \(decision)")
        }
        XCTAssertNil(note, "nothing to explain when there is nothing to decide")
    }

    func testDegenerateRangeHolds() {
        let history = session(reps: [10], weight: 100, daysAgo: 1)
        let decision = BlockProgression.decide(
            history: history, repsLow: 12, repsHigh: 8,
            isLowerBody: false, isIsolation: false)
        guard case .hold = decision else {
            return XCTFail("an inverted range must never produce advice, got \(decision)")
        }
    }
}
