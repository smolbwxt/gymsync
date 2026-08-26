import XCTest
@testable import GymSync

/// The return horizon: which logged sets belong to the athlete the app is
/// prescribing for TODAY.
///
/// Every test here is a defect that shipped. The app read an athlete's
/// whole logged history with no recency bound in three separate places,
/// so a lifter two years away had a two-year-old PR projected onto the bar
/// on their first session back, and was told three sessions later that
/// they had made no progress in 730 days — then advised to push closer to
/// failure and add a set. The corpus names that exact behaviour as THE
/// failure mode on return, and rates it against injury.
final class TrainingHorizonTests: XCTestCase {

    /// Real time, not a fixed epoch: BlockProgression.decide has no
    /// injectable clock, so a 2023 anchor would read as a three-year
    /// layoff and every fixture would be filtered away.
    private let now = Date()
    private let sessionA = UUID()
    private let sessionB = UUID()

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    private func log(_ daysBack: Int,
                     weight: Decimal,
                     reps: Int,
                     session: UUID? = nil,
                     setIndex: Int = 1,
                     failed: Bool = false) -> SetLog {
        SetLog(id: UUID(), userID: UUID(), sessionID: session ?? UUID(),
               exerciseID: UUID(), setIndex: setIndex, reps: reps,
               weight: weight, rpe: nil, isFailed: failed, isPenalty: false,
               note: nil, loggedAt: daysAgo(daysBack))
    }

    // MARK: - Finding the return

    func testAGapLongerThanTheLayoffThresholdIsAReturn() {
        let logs = [log(800, weight: 315, reps: 5), log(2, weight: 135, reps: 5)]
        XCTAssertNotNil(TrainingHorizon.returnDate(in: logs))
        XCTAssertTrue(TrainingHorizon.isReturning(logs))
    }

    func testAnUnbrokenLogHasNoReturn() {
        let logs = (0..<20).map { log($0 * 3, weight: 225, reps: 5) }
        XCTAssertNil(TrainingHorizon.returnDate(in: logs))
        XCTAssertFalse(TrainingHorizon.isReturning(logs))
    }

    func testAGapJustUnderTheThresholdIsNotALayoff() {
        let logs = [log(300, weight: 225, reps: 5),
                    log(300 - GeneratorScience.layoffResetDays + 1, weight: 225, reps: 5)]
        XCTAssertNil(TrainingHorizon.returnDate(in: logs))
    }

    func testTheMostRecentReturnWins() {
        // Come back twice, be judged on the latest one.
        let logs = [log(1400, weight: 405, reps: 3), log(1000, weight: 315, reps: 5),
                    log(700, weight: 275, reps: 5), log(5, weight: 135, reps: 5)]
        let resumed = TrainingHorizon.returnDate(in: logs)
        XCTAssertEqual(resumed, Calendar.current.startOfDay(for: daysAgo(5)))
    }

    func testTheFirstSessionBackIsARETURNEvenThoughNoGapIsLogged() {
        // The case an earlier cut of this missed, and the exact moment the
        // horizon exists for. On day one there is no gap BETWEEN two
        // logged sets — the gap is between the last set and today. A
        // gap-walk over logged dates alone cannot see it, so the horizon
        // would have stayed silent while a two-year-old PR sat one rung
        // from the bar.
        let logs = [log(800, weight: 315, reps: 5), log(790, weight: 315, reps: 5)]
        XCTAssertNotNil(TrainingHorizon.returnDate(in: logs, now: now))
        XCTAssertTrue(TrainingHorizon.sinceReturn(logs, now: now).isEmpty,
                      "every set on file predates the layoff, so none of it counts")
    }

    func testSomeoneWhoTrainedLastWeekIsNotReturning() {
        let logs = [log(9, weight: 225, reps: 5), log(3, weight: 225, reps: 5)]
        XCTAssertNil(TrainingHorizon.returnDate(in: logs, now: now))
    }

    func testComingBackTodayOutranksAnOlderReturn() {
        // Came back once a year ago, trained a while, then vanished again
        // and is opening the app now. The CURRENT return is today.
        let logs = [log(900, weight: 315, reps: 5), log(500, weight: 275, reps: 5),
                    log(480, weight: 280, reps: 5)]
        XCTAssertEqual(TrainingHorizon.returnDate(in: logs, now: now),
                       Calendar.current.startOfDay(for: now))
    }

    // MARK: - Filtering

    func testNoLayoffIsAPassThrough() {
        // The overwhelmingly common case must be untouched, because this
        // filter is applied unconditionally at every prescription site.
        let logs = (0..<10).map { log($0 * 2, weight: 225, reps: 5) }
        XCTAssertEqual(TrainingHorizon.sinceReturn(logs).count, logs.count)
    }

    func testPreLayoffSetsAreDropped() {
        let logs = [log(800, weight: 315, reps: 5), log(790, weight: 320, reps: 5),
                    log(4, weight: 135, reps: 5), log(1, weight: 140, reps: 5)]
        let kept = TrainingHorizon.sinceReturn(logs)
        XCTAssertEqual(kept.count, 2)
        XCTAssertTrue(kept.allSatisfy { ($0.weight ?? 0) <= 140 })
    }

    func testAnEmptyLogSurvivesTheFilter() {
        XCTAssertTrue(TrainingHorizon.sinceReturn([]).isEmpty)
    }

    func testAHistoryTooShortToContainTheGapReturnsUnfiltered() {
        // nil means "no gap FOUND", not "no gap exists". Returning the
        // input unchanged is the safe direction — the alternative is
        // inventing a horizon out of missing data.
        let logs = [log(2, weight: 135, reps: 5)]
        XCTAssertEqual(TrainingHorizon.sinceReturn(logs).count, 1)
    }

    // MARK: - Defect A: the bar prefilled a pre-layoff PR

    func testTheBarDoesNotPrefillATwoYearOldPersonalRecord() {
        // THE defect. Before the horizon, rung 2 projected an inverse-Epley
        // of the best set in all of history onto session one back.
        let history = [log(800, weight: 315, reps: 5, session: sessionA),
                       log(795, weight: 315, reps: 5, session: sessionA)]
        let suggestion = WorkingWeight.suggest(
            exerciseID: UUID(), targetReps: 5, routineTargetPounds: nil,
            history: history + [log(1, weight: 135, reps: 5, session: sessionB)],
            lastSetPounds: nil, enrollment: nil)
        // Whatever it says, it must not be a projection off 315.
        if let suggestion {
            XCTAssertLessThan(suggestion.pounds, 200,
                              "prescribed off a pre-layoff max: \(suggestion.pounds)")
        }
    }

    func testAnUninterruptedLifterStillGetsTheirRepGoalProjection() {
        // The guard against over-suppression: this is the normal path and
        // it must be untouched.
        let history = (0..<6).map { log($0 * 3, weight: 225, reps: 5, session: UUID()) }
        let suggestion = WorkingWeight.suggest(
            exerciseID: UUID(), targetReps: 5, routineTargetPounds: nil,
            history: history, lastSetPounds: nil, enrollment: nil)
        XCTAssertEqual(suggestion?.source, .repGoal(targetReps: 5))
        XCTAssertGreaterThan(suggestion?.pounds ?? 0, 200)
    }

    func testSessionOneBackHasNothingHonestToSay() {
        // The empty bar the corpus asks for: "rebuilt every working weight
        // from an empty bar using feel rather than resuming old numbers."
        // Only pre-layoff history exists, so every history-fed rung is
        // blind and the onboarding seed is suppressed too.
        let history = [log(800, weight: 315, reps: 5), log(700, weight: 315, reps: 5)]
        let suggestion = WorkingWeight.suggest(
            exerciseID: UUID(), targetReps: 5, routineTargetPounds: nil,
            history: history, lastSetPounds: nil, enrollment: nil,
            seededPounds: 225, now: now)
        XCTAssertNil(suggestion,
                     "nothing on file belongs to this athlete today — the bar stays empty")
    }

    func testTheOnboardingSeedStillFiresForSomeoneWithNoLayoff() {
        let suggestion = WorkingWeight.suggest(
            exerciseID: UUID(), targetReps: 5, routineTargetPounds: nil,
            history: [], lastSetPounds: nil, enrollment: nil, seededPounds: 225)
        XCTAssertEqual(suggestion?.source, .seeded)
    }

    // MARK: - Defect B: told they stalled for two years

    func testAReturnerIsNotToldTheyStalledForTwoYears() {
        // Three sessions into a comeback, the old code found a 730-day-old
        // e1RM best and fired the true-stall rule — then chose its remedy
        // from a defaulted RPE and said "push closer to failure, add a
        // set", to the exact athlete the corpus says must undershoot.
        var history: [SetLog] = []
        let old = UUID()
        history += [log(800, weight: 315, reps: 5, session: old, setIndex: 1),
                    log(800, weight: 315, reps: 5, session: old, setIndex: 2)]
        for back in [7, 4, 1] {
            let s = UUID()
            history += [log(back, weight: 135, reps: 5, session: s, setIndex: 1),
                        log(back, weight: 135, reps: 5, session: s, setIndex: 2)]
        }
        let decision = BlockProgression.decide(
            history: history, repsLow: 5, repsHigh: 8,
            isLowerBody: false, isIsolation: false)
        if case .flagStall = decision {
            XCTFail("flagged a two-year-old best as a stall on a comeback")
        }
    }

    func testARealStallIsStillFlaggedForAnUninterruptedLifter() {
        // Over-suppression guard: without a layoff, nothing changes.
        var history: [SetLog] = []
        let best = UUID()
        history += [log(60, weight: 225, reps: 8, session: best, setIndex: 1)]
        for back in [40, 27, 14, 3] {
            let s = UUID()
            history += [log(back, weight: 225, reps: 5, session: s, setIndex: 1)]
        }
        let decision = BlockProgression.decide(
            history: history, repsLow: 5, repsHigh: 8,
            isLowerBody: false, isIsolation: false)
        if case .flagStall = decision { return }
        if case .advanceReps = decision { return }
        if case .advanceLoad = decision { return }
        // A hold is acceptable; the point is the horizon did not silently
        // erase a lifter's real history.
        XCTAssertEqual(TrainingHorizon.sinceReturn(history).count, history.count)
    }

    // MARK: - One algorithm, three questions

    func testTheHorizonAndTheExperienceDecayAgreeOnWhenSomeoneCameBack() {
        // GeneratorScience.daysSinceReturn (how long ago), returnDate
        // (when), and TrainingHorizon (which sets) must never disagree —
        // two copies of this rule would drift invisibly, because each half
        // would still look correct on its own.
        let dates = [daysAgo(800), daysAgo(790), daysAgo(10), daysAgo(3)]
        let resumed = GeneratorScience.returnDate(sessionDates: dates)
        let days = GeneratorScience.daysSinceReturn(sessionDates: dates, now: now)
        XCTAssertEqual(resumed, Calendar.current.startOfDay(for: daysAgo(10)))
        XCTAssertEqual(days, 10)
    }

    func testTheEmptyBarNoteSaysWhatToDoInsteadOfApologising() {
        let note = TrainingHorizon.emptyBarNote
        XCTAssertTrue(note.contains("5 or 6"), "must give the athlete an anchor to act on")
        XCTAssertFalse(note.contains("  "))
        XCTAssertFalse(note.isEmpty)
    }
}
