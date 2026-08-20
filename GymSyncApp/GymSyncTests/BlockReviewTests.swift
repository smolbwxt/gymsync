import XCTest
@testable import GymSync

/// Phase 4: history informs the future. Block review (re-freeze,
/// abandonment, the shared stall oracle), proportional block planning,
/// drift probes with their cooldown, and spacing-aware scheduling.
final class BlockReviewTests: XCTestCase {

    private let user = UUID()
    private let bench = UUID()
    private let squat = UUID()
    private let curl = UUID()

    private func session(_ exercise: UUID, reps: [Int], weight: Decimal,
                         daysAgo: Double) -> [SetLog] {
        let id = UUID()
        return reps.enumerated().map { i, r in
            SetLog(id: UUID(), userID: user, sessionID: id, exerciseID: exercise,
                   setIndex: i, reps: r, weight: weight, rpe: nil,
                   isFailed: false, isPenalty: false, note: nil,
                   loggedAt: Date(timeIntervalSinceNow: -daysAgo * 86_400))
        }
    }

    private func prescriptions() -> [BlockReview.Prescription] {
        [.init(exerciseID: bench, repsLow: 8, repsHigh: 12, isLowerBody: false),
         .init(exerciseID: squat, repsLow: 8, repsHigh: 12, isLowerBody: true),
         .init(exerciseID: curl, repsLow: 8, repsHigh: 15, isLowerBody: false)]
    }

    func testReviewRefreezesBaselinesFlagsStrugglersAndAbandonment() {
        var logs: [SetLog] = []
        // Bench: progressing fine (reps climbing), present every session.
        logs += session(bench, reps: [10, 10], weight: 100, daysAgo: 25)
        logs += session(bench, reps: [11, 11], weight: 100, daysAgo: 18)
        logs += session(bench, reps: [12, 11], weight: 100, daysAgo: 11)
        logs += session(bench, reps: [12, 12], weight: 100, daysAgo: 4)
        // Squat: flat e1RM for 3+ weeks across 3+ sessions -> struggling.
        logs += session(squat, reps: [10, 10], weight: 200, daysAgo: 26)
        logs += session(squat, reps: [8, 8], weight: 200, daysAgo: 19)
        logs += session(squat, reps: [8, 8], weight: 200, daysAgo: 12)
        logs += session(squat, reps: [8, 8], weight: 200, daysAgo: 1)
        // Curl: prescribed, logged once in eight sessions -> abandoned.
        logs += session(curl, reps: [12], weight: 30, daysAgo: 25)

        let outcome = BlockReview.analyze(logs: logs,
                                          prescriptions: prescriptions(),
                                          plannedSessions: 12, weeks: 4)
        XCTAssertNotNil(outcome.newBaselines[bench],
                        "every trained lift re-freezes a baseline")
        XCTAssertGreaterThan(outcome.newBaselines[squat] ?? 0,
                             outcome.newBaselines[bench] ?? 0,
                             "baselines are e1RM, not enthusiasm")
        XCTAssertTrue(outcome.strugglingLiftIDs.contains(squat),
                      "the live engine's stall verdict IS the review's verdict")
        XCTAssertFalse(outcome.strugglingLiftIDs.contains(bench))
        XCTAssertTrue(outcome.abandonedExerciseIDs.contains(curl),
                      "logged once in nine sessions = abandoned")
        XCTAssertFalse(outcome.abandonedExerciseIDs.contains(bench))
        XCTAssertEqual(outcome.adherence, 9.0 / 12.0, accuracy: 0.01)
        XCTAssertEqual(outcome.suggestedDaysPerWeek, 2,
                       "nine sessions over four weeks supports ~2 days")
    }

    func testDeprioritizedLiftLosesToEqualPeerButFillsAHole() {
        var a = ProgramGenerator.CatalogExercise(
            id: bench, name: "Bench", primaryMuscle: "chest",
            secondaryMuscles: [], category: "compound", equipment: "barbell",
            movementPattern: "push_horizontal", rank: 1)
        var b = ProgramGenerator.CatalogExercise(
            id: UUID(), name: "DB Press", primaryMuscle: "chest",
            secondaryMuscles: [], category: "compound", equipment: "dumbbell",
            movementPattern: "push_horizontal", rank: 2)
        a.focusScores = ["hypertrophy": 8]; b.focusScores = ["hypertrophy": 8]
        let slot = ProgramGenerator.Slot.pattern("push_horizontal", main: true)
        let pick = ProgramGenerator.select(
            slot: slot, from: [a, b], excluding: [], focus: .hypertrophy,
            focusMuscles: nil, deprioritized: [bench])
        XCTAssertEqual(pick?.name, "DB Press",
                       "a skipped-last-block lift loses the tie")
        let onlyOption = ProgramGenerator.select(
            slot: slot, from: [a], excluding: [], focus: .hypertrophy,
            focusMuscles: nil, deprioritized: [bench])
        XCTAssertEqual(onlyOption?.name, "Bench",
                       "soft gate: deprioritized never leaves a hole")
    }

    // MARK: Block planning (goal weights over TIME)

    func testSeventyThirtyProfileAlternatesProportionally() {
        var profile = TrainingProfile()
        profile.rankedGoals = [.hypertrophy, .maxStrength]   // 2/3 vs 1/3
        var history: [TrainingGoal] = []
        for _ in 0..<6 {
            history.append(BlockPlanner.nextBlockGoal(profile: profile,
                                                      history: history))
        }
        XCTAssertEqual(history.filter { $0 == .hypertrophy }.count, 4,
                       "two-thirds of six blocks go to the top goal")
        XCTAssertEqual(history.filter { $0 == .maxStrength }.count, 2)
        XCTAssertEqual(history.first, .hypertrophy,
                       "the dominant goal always opens the relationship")
    }

    func testWeightOnlyGoalsNeverClaimBlocks() {
        var profile = TrainingProfile()
        profile.rankedGoals = [.boneDensity, .hypertrophy]
        let next = BlockPlanner.nextBlockGoal(profile: profile, history: [])
        XCTAssertEqual(next, .hypertrophy,
                       "bone density tilts selection inside blocks; it never owns one")
    }

    // MARK: Drift probes

    func testAdherenceGapProbesButCooldownSilences() {
        var profile = TrainingProfile()
        profile.daysPerWeek = 5
        var logs: [SetLog] = []
        for days in [24.0, 17, 10, 3] {           // ~1/week against 5 planned
            logs += session(bench, reps: [10], weight: 100, daysAgo: days)
        }
        let signals = DriftDetector.detect(profile: profile, logs: logs,
                                           windowWeeks: 4, lastProbeDate: nil)
        XCTAssertEqual(signals.first?.kind, "adherence_gap")
        XCTAssertTrue(signals.first!.probe.contains("fits"),
                      "a probe is an offer, never a verdict")
        let silenced = DriftDetector.detect(
            profile: profile, logs: logs, windowWeeks: 4,
            lastProbeDate: Date(timeIntervalSinceNow: -3 * 86_400))
        XCTAssertTrue(silenced.isEmpty,
                      "inside the 14-day cooldown Coach stays quiet, whatever the evidence")
    }

    func testRepStyleGapReadsTheLogbookAgainstTheGoal() {
        var profile = TrainingProfile()
        profile.rankedGoals = [.hypertrophy]
        profile.daysPerWeek = 2                    // adherence satisfied
        var logs: [SetLog] = []
        for days in stride(from: 26.0, to: 1, by: -3) {
            logs += session(squat, reps: [3, 3, 2], weight: 300, daysAgo: days)
        }
        let signals = DriftDetector.detect(profile: profile, logs: logs,
                                           windowWeeks: 4, lastProbeDate: nil)
        XCTAssertTrue(signals.contains { $0.kind == "rep_style_gap" },
                      "a hypertrophy goal trained in triples earns a question")
    }

    // MARK: Scheduling

    func testThreeDayWeekGetsMonWedFriShapeAcrossTheBlock() {
        let calendar = Calendar(identifier: .gregorian)
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 8, day: 24))!
        let dates = SchedulePlanner.sessionDates(daysPerWeek: 3, weeks: 2,
                                                 anchor: anchor, calendar: calendar)
        XCTAssertEqual(dates.count, 6)
        let days = dates.map { calendar.component(.day, from: $0) }
        XCTAssertEqual(days, [24, 26, 28, 31, 2 + 31, 4 + 31].map { $0 > 31 ? $0 - 31 : $0 },
                       "Mon/Wed/Fri shape, repeated weekly")
        // 48-hour law: no two sessions on consecutive days at 3/week.
        let sorted = dates.sorted()
        for pair in zip(sorted, sorted.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.timeIntervalSince(pair.0), 2 * 86_400 - 1)
        }
    }
}
