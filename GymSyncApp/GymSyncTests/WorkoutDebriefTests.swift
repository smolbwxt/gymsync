import XCTest
@testable import GymSync

/// The debrief's deterministic layer — the part both tiers share. The
/// free card and the AI conversation read the SAME builder, so these
/// tests are the guarantee they can never contradict each other.
final class WorkoutDebriefTests: XCTestCase {

    private let user = UUID()

    private func set(_ session: UUID, exercise: UUID = UUID(), index: Int,
                     reps: Int, weight: Decimal, failed: Bool = false,
                     daysAgo: Double = 0) -> SetLog {
        SetLog(id: UUID(), userID: user, sessionID: session, exerciseID: exercise,
               setIndex: index, reps: reps, weight: weight, rpe: nil,
               isFailed: failed, isPenalty: false, note: nil,
               loggedAt: Date(timeIntervalSinceNow: -daysAgo * 86_400))
    }

    private func benchReport(decision: BlockProgression.Decision? = nil,
                             sets: [SetLog]? = nil) -> DebriefBuilder.ExerciseReport {
        let id = UUID()
        return .init(name: "Bench Press", prescribedSets: 3, repsLow: 8, repsHigh: 12,
                     sets: sets ?? [set(id, index: 0, reps: 12, weight: 135),
                                    set(id, index: 1, reps: 12, weight: 135),
                                    set(id, index: 2, reps: 11, weight: 135)],
                     decision: nil)
            .with(decision: decision)
    }

    func testCorePromptCarriesGoalsPrescriptionActualsAndDecisions() {
        var context = DebriefBuilder.Context()
        context.profile.rankedGoals = [.hypertrophy, .maxStrength]
        context.blockWeek = 3; context.blockWeeks = 8; context.blockGoal = .hypertrophy
        context.personalRecords = ["135×12 bench — rep PR at that weight"]
        let note = BlockProgression.CoachNote(summary: "Load up — you topped the rep range",
                                              reason: "r")
        let debrief = DebriefBuilder.build(
            reports: [benchReport(decision: .advanceLoad(toPounds: 140, note: note))],
            context: context)
        let prompt = debrief.corePrompt
        XCTAssertTrue(prompt.contains("GOALS: hypertrophy then max_strength"))
        XCTAssertTrue(prompt.contains("block: week 3 of 8"))
        XCTAssertTrue(prompt.contains("BENCH PRESS: prescribed 3×8-12 → did 12@135, 12@135, 11@135"))
        XCTAssertTrue(prompt.contains("coach: Load up"))
        XCTAssertTrue(prompt.contains("PR: 135×12 bench"))
        XCTAssertTrue(prompt.contains("cite these numbers verbatim"),
                      "the no-arithmetic rule rides in the payload header too")
    }

    func testSafetyLinesComeBeforeTheWorkAndSkipsAreNamed() {
        var context = DebriefBuilder.Context()
        context.safetyNotes = ["athlete noted right-shoulder twinge on set 2"]
        let skipped = DebriefBuilder.ExerciseReport(
            name: "Curl", prescribedSets: 3, repsLow: 8, repsHigh: 15,
            sets: [], decision: nil)
        let debrief = DebriefBuilder.build(reports: [benchReport(), skipped],
                                           context: context)
        let prompt = debrief.corePrompt
        let safetyIndex = prompt.range(of: "SAFETY:")!.lowerBound
        let todayIndex = prompt.range(of: "TODAY:")!.lowerBound
        XCTAssertLessThan(safetyIndex, todayIndex,
                          "safety precedes the work in the payload itself")
        XCTAssertTrue(prompt.contains("CURL: prescribed 3×8-15 → SKIPPED"))
        XCTAssertEqual(debrief.safetyNotes.count, 1,
                       "safety also surfaces OUTSIDE the prompt — never only behind a model")
    }

    func testFailedRepsSerializeAtCompletedCount() {
        let id = UUID()
        let report = DebriefBuilder.ExerciseReport(
            name: "Row", prescribedSets: 1, repsLow: 8, repsHigh: 12,
            sets: [set(id, index: 0, reps: 12, weight: 115, failed: true)],
            decision: nil)
        let prompt = DebriefBuilder.corePrompt(reports: [report],
                                               context: .init())
        XCTAssertTrue(prompt.contains("did 11@115"),
                      "the failure doctrine holds in the payload: 12 with FAIL = 11 completed")
    }

    // MARK: The free card, by experience

    func testNoviceHeadlineLeadsWithConsistencyOverPR() {
        var context = DebriefBuilder.Context()
        context.profile.trainingAge = .novice
        context.weekSessionCount = 3
        context.personalRecords = ["135×12 bench — rep PR"]
        let headline = DebriefBuilder.headline(reports: [benchReport()],
                                               context: context)
        XCTAssertTrue(headline.contains("Session 3 this week"),
                      "a novice's real win is showing up")
    }

    func testAdvancedHeadlineLeadsWithThePR() {
        var context = DebriefBuilder.Context()
        context.profile.trainingAge = .advanced
        context.weekSessionCount = 3
        context.personalRecords = ["315×5 squat — all-time 5RM"]
        let headline = DebriefBuilder.headline(reports: [benchReport()],
                                               context: context)
        XCTAssertEqual(headline, "315×5 squat — all-time 5RM",
                       "advanced lifters get the number, not cheerleading")
    }

    func testCorePromptStaysInsideTheTokenBudget() {
        // A heavy session: 8 exercises, PRs, a probe, safety — the worst
        // realistic case must still fit ~900 tokens (~3600 chars).
        var context = DebriefBuilder.Context()
        context.profile.rankedGoals = [.hypertrophy, .maxStrength, .conditioning]
        context.blockWeek = 7; context.blockWeeks = 12; context.blockGoal = .hypertrophy
        context.personalRecords = ["135×12 bench — rep PR", "225×8 squat — rep PR"]
        context.safetyNotes = ["athlete noted right-shoulder twinge on set 2"]
        context.pendingProbe = .init(kind: "adherence_gap",
                                     evidence: "The plan schedules 5 days a week; the last 4 weeks averaged 2.4.",
                                     probe: "Want a 2-day plan that actually fits your week?")
        context.sessionMinutes = 62
        let reports = (0..<8).map { _ in benchReport() }
        let prompt = DebriefBuilder.corePrompt(reports: reports, context: context)
        XCTAssertLessThan(prompt.count, 3_600,
                          "the CORE payload must leave the ~4k window room to talk")
    }

    // MARK: Tool backends — computed sentences, never raw rows

    func testTrendSentenceComputesTheDeltaInSwift() {
        let exercise = UUID()
        var logs: [SetLog] = []
        let s1 = UUID(), s2 = UUID(), s3 = UUID()
        logs.append(set(s1, exercise: exercise, index: 0, reps: 8, weight: 200, daysAgo: 42))
        logs.append(set(s2, exercise: exercise, index: 0, reps: 8, weight: 215, daysAgo: 21))
        logs.append(set(s3, exercise: exercise, index: 0, reps: 8, weight: 225, daysAgo: 1))
        let sentence = DebriefBuilder.trendSentence(name: "Squat", logs: logs)
        XCTAssertTrue(sentence.contains("Squat: estimated 1RM"))
        XCTAssertTrue(sentence.contains("across 3 sessions"))
        XCTAssertTrue(sentence.contains("+"),
                      "a rising trend states its delta — got: \(sentence)")
        XCTAssertFalse(sentence.contains("?"), "display-ready, no placeholders")
    }

    func testVolumeSentenceRanksAndRounds() {
        let sentence = DebriefBuilder.volumeSentence(
            tally: ["chest": 12.5, "triceps": 8.0, "back": 14.0])
        XCTAssertTrue(sentence.contains("back 14.0"))
        XCTAssertTrue(sentence.hasPrefix("Effective weekly sets"))
    }

    // MARK: Instructions — persona x register x rails

    func testInstructionsComposeVoiceRegisterAndRails() {
        var profile = TrainingProfile()
        profile.trainingAge = .novice
        let scientist = CoachPersona.bySlug("the-scientist")!
        let text = DebriefInstructions.build(persona: scientist, profile: profile)
        XCTAssertTrue(text.contains("You are The Scientist"))
        XCTAssertTrue(text.contains("define any term you use"),
                      "novice register: teach as you go")
        XCTAssertTrue(text.contains("Never calculate, estimate, or recall numbers"),
                      "the rails ride in every composition")
        XCTAssertTrue(text.contains("address them FIRST"),
                      "safety priority is identical in every voice")

        profile.trainingAge = .advanced
        let advanced = DebriefInstructions.build(persona: nil, profile: profile)
        XCTAssertTrue(advanced.contains("terse and data-dense"))
        XCTAssertTrue(advanced.contains("read the logbook before speaking"),
                      "no persona = the house voice, not an empty voice")
    }

    func testConversationAvailabilityIsFalseOnTestRunners() {
        XCTAssertFalse(CoachDebrief.isConversationAvailable,
                       "pre-iOS-26 environments fall back to the report card")
    }
}

private extension DebriefBuilder.ExerciseReport {
    func with(decision: BlockProgression.Decision?) -> DebriefBuilder.ExerciseReport {
        .init(name: name, prescribedSets: prescribedSets, repsLow: repsLow,
              repsHigh: repsHigh, sets: sets, decision: decision)
    }
}
