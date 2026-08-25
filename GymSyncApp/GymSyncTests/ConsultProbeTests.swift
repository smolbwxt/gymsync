import XCTest
@testable import GymSync

/// The consult's selector, run against the stories from the 40-persona
/// sweep. The sweep found real defects by hand (a 13-year-old asked which
/// lift his number was on; an athlete offered exercises his gym does not
/// have) — these tests keep those closed as CODE rather than as a
/// paragraph in a design doc.
///
/// Two properties matter more than any individual assertion:
///   1. Nobody is left hanging — the consult always terminates.
///   2. Nobody is asked something impossible — a probe never fires when
///      the athlete has no way to answer it.
final class ConsultProbeTests: XCTestCase {

    // MARK: - Driver
    //
    // Simulates an athlete answering whatever they are asked, applying the
    // side effects a real answer would have. Returns the transcript in
    // order, which is what the story tests read.

    private func run(_ start: ConsultProbe.Context,
                     branch: String,
                     cap: Int = 30) -> [String] {
        var context = start
        var asked: [String] = []
        while asked.count < cap {
            guard let probe = ConsultProbe.next(in: context) else { return asked }
            asked.append(probe.id)
            context.answered.insert(probe.id)
            // Apply what answering actually changes.
            switch probe.id {
            case "opener":         context.goalBranch = branch
            case "equipment":      context.equipmentKnown = true
            case "session_length": context.sessionMinutesKnown = true
            case "cautions":       context.cautionsKnown = true
            case "standing_rule":  context.offeredRuleCapture = true
            case "days":           context.statedDaysPerWeek = context.statedDaysPerWeek ?? 4
            case "commitment":     context.statedDaysPerWeek = 4
            default: break
            }
            // A probe that tunes a profile field has now STATED it, which
            // is what stops the consult re-asking a confirmed value.
            for key in probe.tunes { context.provenance[key] = .stated }
        }
        XCTFail("the consult did not terminate within \(cap) questions: \(asked)")
        return asked
    }

    // MARK: - Bank integrity

    func testEveryProbeTunesSomethingRealAndReadable() {
        // The dead-knob tripwire. repAppetite sat in TrainingProfile for
        // months with no reader; a probe writing to a field nothing reads
        // is worse than no probe, because it costs a question and buys
        // nothing. Every destination must be nameable.
        for probe in [ConsultProbe.opener] + ConsultProbe.bank {
            XCTAssertFalse(probe.tunes.isEmpty, "\(probe.id) tunes nothing")
            for key in probe.tunes {
                XCTAssertTrue(ConsultProbe.knownTunables.contains(key),
                              "\(probe.id) claims to tune '\(key)', which nothing reads")
            }
        }
    }

    func testProbeIDsAreUnique() {
        let ids = ([ConsultProbe.opener] + ConsultProbe.bank).map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate probe id")
    }

    func testGainsAreInRangeAndOptionsCarryLabels() {
        for probe in [ConsultProbe.opener] + ConsultProbe.bank {
            XCTAssertTrue((1...10).contains(probe.gain), "\(probe.id) gain out of range")
            for option in probe.options {
                XCTAssertFalse(option.label.isEmpty, "\(probe.id) has an unlabelled option")
            }
        }
    }

    // MARK: - Ordering invariants

    func testTheOpenerAlwaysComesFirst() {
        let asked = run(ConsultProbe.Context(), branch: "size")
        XCTAssertEqual(asked.first, "opener")
    }

    func testEquipmentIsAskedBeforeAnythingExerciseSpecific() {
        // The credibility failure the consult exists to avoid: proposing
        // lifts the athlete has no way to perform. Equipment outranks even
        // higher-gain probes.
        let asked = run(ConsultProbe.Context(hasLog: true), branch: "numbers")
        let equipment = asked.firstIndex(of: "equipment")
        XCTAssertNotNil(equipment)
        for specific in ["focus_lift", "anchor_lifts", "wont_do"] {
            if let index = asked.firstIndex(of: specific) {
                XCTAssertLessThan(equipment!, index,
                                  "\(specific) was asked before we knew the equipment")
            }
        }
    }

    func testWontDoOnlyFollowsCautions() {
        let asked = run(ConsultProbe.Context(), branch: "forge")
        if let wontDo = asked.firstIndex(of: "wont_do") {
            let cautions = asked.firstIndex(of: "cautions")
            XCTAssertNotNil(cautions, "wont_do fired without cautions")
            XCTAssertLessThan(cautions!, wontDo)
        }
    }

    func testAStatedValueIsNeverReAsked() {
        // The five doors give coarse adjustment; the consult refines. A
        // value the athlete already typed into a door is not a question.
        var context = ConsultProbe.Context(hasLog: true)
        context.provenance["effort"] = .stated
        context.provenance["repAppetite"] = .confirmed
        let asked = run(context, branch: "size")
        XCTAssertFalse(asked.contains("effort"))
        XCTAssertFalse(asked.contains("rep_appetite"))
    }

    func testAPersonaDefaultIsStillWorthChallenging() {
        // The mirror of the above: a value we GUESSED is cheap to probe.
        var context = ConsultProbe.Context(hasLog: true)
        context.provenance["effort"] = .personaDefault
        let asked = run(context, branch: "size")
        XCTAssertTrue(asked.contains("effort"))
    }

    // MARK: - Cold start (persona sweep: the 13-year-old)

    func testAnAthleteWithNoLogIsNeverAskedToNameTheirNumbers() {
        // Story #1 from the sweep: a 13-year-old on day one was asked
        // "which lift is the number on?" — a question with no answer.
        let asked = run(ConsultProbe.Context(hasLog: false, isYouth: true), branch: "numbers")
        XCTAssertFalse(asked.contains("focus_lift"),
                       "a lifter with no history cannot name a focus lift")
        XCTAssertTrue(asked.contains("anchor_lifts"),
                      "cold start must route to anchors instead")
        XCTAssertTrue(asked.contains("gym_comfort"))
    }

    func testAnAthleteWithALogIsNotAskedToGuessTheirAnchors() {
        let asked = run(ConsultProbe.Context(hasLog: true), branch: "numbers")
        XCTAssertFalse(asked.contains("anchor_lifts"),
                       "we can read these from the log — asking is a tax")
        XCTAssertTrue(asked.contains("focus_lift"))
    }

    // MARK: - The commitment probe (owner: "lets be kind about it")

    func testCommitmentIsRaisedOnlyWhenIntentOutrunsTheRecord() {
        var context = ConsultProbe.Context(hasLog: true)
        context.loggedDaysPerWeek = 2
        context.statedDaysPerWeek = 4          // gap of 2
        XCTAssertTrue(run(context, branch: "size").contains("commitment"))
    }

    func testCommitmentIsNotRaisedWhenTheRecordAlreadyMatches() {
        var context = ConsultProbe.Context(hasLog: true)
        context.loggedDaysPerWeek = 4
        context.statedDaysPerWeek = 4
        XCTAssertFalse(run(context, branch: "size").contains("commitment"),
                       "confronting someone who is already showing up is a nag")
    }

    func testCommitmentIsNotRaisedForAFractionalGap() {
        // Someone averaging 3.4 sessions who says 4 is not contradicting
        // themselves; they are rounding.
        var context = ConsultProbe.Context(hasLog: true)
        context.loggedDaysPerWeek = 3.4
        context.statedDaysPerWeek = 4
        XCTAssertFalse(run(context, branch: "size").contains("commitment"))
    }

    func testCommitmentNeedsALogToFireAtAll() {
        var context = ConsultProbe.Context(hasLog: false)
        context.statedDaysPerWeek = 6
        XCTAssertFalse(run(context, branch: "forge").contains("commitment"),
                       "there is no record to contradict")
    }

    // MARK: - Goal branches

    func testEachBranchAsksOnlyItsOwnRefinement() {
        let branches: [String: String] = [
            "numbers": "focus_lift",
            "size": "focus_areas",
            "date": "the_date",
            "engine": "engine_kind",
        ]
        for (branch, expected) in branches {
            let asked = run(ConsultProbe.Context(hasLog: true), branch: branch)
            XCTAssertTrue(asked.contains(expected), "\(branch) never asked \(expected)")
            for (other, unexpected) in branches where other != branch {
                XCTAssertFalse(asked.contains(unexpected),
                               "\(branch) leaked \(other)'s refinement")
            }
        }
    }

    func testEveryOpenerDoorLeadsSomewhere() {
        // The generalization of a hole this file found: five of the six
        // doors branched into a refinement and "BUILD THE ENGINE" branched
        // into nothing, dropping an endurance athlete straight into the
        // generic probes. An opener option with no follow-up is a door
        // painted on a wall.
        let refinements: Set<String> = ["focus_lift", "focus_areas", "the_date",
                                        "engine_kind", "whats_off"]
        for option in ConsultProbe.opener.options {
            let asked = Set(run(ConsultProbe.Context(hasLog: true), branch: option.id))
            XCTAssertFalse(asked.intersection(refinements).isEmpty,
                           "the '\(option.id)' door leads to no goal refinement")
        }
    }

    func testTheDiagnosticBranchesAskWhatIsOff() {
        for branch in ["running", "forge"] {
            XCTAssertTrue(run(ConsultProbe.Context(hasLog: true), branch: branch)
                            .contains("whats_off"))
        }
    }

    // MARK: - Termination and proportionality

    func testEveryStoryTerminates() {
        // The 40-persona sweep, compressed to the dimensions the selector
        // actually branches on. If any story loops, the driver fails.
        for story in Self.stories {
            let asked = run(story.context, branch: story.branch)
            XCTAssertFalse(asked.isEmpty, "\(story.name) was asked nothing")
            XCTAssertEqual(asked.count, Set(asked).count,
                           "\(story.name) was asked the same thing twice")
        }
    }

    func testNoStoryIsLeftHanging() {
        // "Left hanging" = the consult ends without knowing the three
        // things the generator cannot run without.
        for story in Self.stories {
            let asked = Set(run(story.context, branch: story.branch))
            let known = story.context
            XCTAssertTrue(asked.contains("equipment") || known.equipmentKnown,
                          "\(story.name): equipment never determined")
            XCTAssertTrue(asked.contains("days") || known.statedDaysPerWeek != nil,
                          "\(story.name): training days never determined")
            XCTAssertTrue(asked.contains("cautions") || known.cautionsKnown,
                          "\(story.name): nobody asked what hurts")
        }
    }

    func testTheConsultIsProportionalNotFixedLength() {
        // The owner's Akinator framing: no budget, but a simple athlete
        // must genuinely finish faster than a complex one. If these two
        // converge, the selector has degenerated into a fixed script.
        var simple = ConsultProbe.Context(hasLog: true)
        simple.equipmentKnown = true
        simple.sessionMinutesKnown = true
        simple.cautionsKnown = true
        simple.statedDaysPerWeek = 3
        simple.loggedDaysPerWeek = 3
        for key in ["effort", "repAppetite", "sessionStructure", "cardioStyle",
                    "intensityAppetite"] {
            simple.provenance[key] = .stated
        }

        var complex = ConsultProbe.Context(hasLog: false)
        complex.statedDaysPerWeek = nil

        let short = run(simple, branch: "running").count
        let long = run(complex, branch: "date").count
        XCTAssertLessThan(short, long,
                          "a known athlete should be asked less than an unknown one")
        XCTAssertLessThanOrEqual(short, 5, "a fully-known athlete is being over-asked")
    }

    func testRemainingIsAReadoutNotACountdown() {
        // Documented behaviour, not a defect — and it cost a CI round to
        // learn, so it is written down here rather than in a commit
        // message. Answering the opener CLOSES one question and OPENS the
        // refinement for the branch chosen, so the remaining count can sit
        // still or rise. Same for cautions, which unlocks wont_do.
        //
        // This is why the header hedges: CoachConsultView says "A FEW
        // LEFT" above four and only commits to an exact number once the
        // branching is behind it. A screen that promised "8 LEFT" and then
        // asked nine would be a number we did not keep.
        var context = ConsultProbe.Context(hasLog: true)
        let atStart = ConsultProbe.remaining(in: context)
        context.answered.insert("opener")
        context.goalBranch = "size"
        context.answered.insert("equipment")
        context.equipmentKnown = true
        XCTAssertLessThanOrEqual(ConsultProbe.remaining(in: context), atStart + 1,
                                 "a branch may reveal a refinement, but not a wave of them")
    }

    func testAFollowUpMayReplaceTheQuestionItClosed() {
        // The specific case: naming a caution earns the right to ask what
        // the athlete flat-out will not do.
        var context = ConsultProbe.Context(hasLog: true)
        context.goalBranch = "size"
        context.answered = ["opener"]
        let before = ConsultProbe.remaining(in: context)
        context.answered.insert("cautions")
        context.cautionsKnown = true
        XCTAssertEqual(ConsultProbe.remaining(in: context), before,
                       "cautions closes itself and opens wont_do — net zero")
    }

    func testRemainingReachesZeroWhenThereIsNothingLeftToAsk() {
        // The property that actually matters: the readout must land on
        // zero at the same moment next() returns nil, or the last screen
        // would say there are questions left while offering none.
        var context = ConsultProbe.Context(hasLog: true)
        var guardRail = 30
        while let probe = ConsultProbe.next(in: context), guardRail > 0 {
            guardRail -= 1
            context.answered.insert(probe.id)
            switch probe.id {
            case "opener":         context.goalBranch = "size"
            case "equipment":      context.equipmentKnown = true
            case "session_length": context.sessionMinutesKnown = true
            case "cautions":       context.cautionsKnown = true
            case "standing_rule":  context.offeredRuleCapture = true
            case "days":           context.statedDaysPerWeek = 4
            default: break
            }
            for key in probe.tunes { context.provenance[key] = .stated }
        }
        XCTAssertNil(ConsultProbe.next(in: context))
        XCTAssertEqual(ConsultProbe.remaining(in: context), 0)
    }

    func testRemainingNeverExceedsTheBank() {
        XCTAssertLessThanOrEqual(ConsultProbe.remaining(in: ConsultProbe.Context()),
                                 ConsultProbe.bank.count)
    }

    func testTheConsultEndsRatherThanPaddingItself() {
        // Everything known, every preference stated: there is nothing left
        // that would change the program, so next() must return nil rather
        // than reach for filler.
        var context = ConsultProbe.Context(hasLog: true)
        context.answered = Set(([ConsultProbe.opener] + ConsultProbe.bank).map(\.id))
        XCTAssertNil(ConsultProbe.next(in: context))
    }

    // MARK: - Reading the log

    private func dates(_ dayOffsets: [Int], perDay: Int = 1) -> [Date] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return dayOffsets.flatMap { offset in
            (0..<perDay).map { i in
                // Minutes apart, so 40 sets stay inside one calendar day
                // whatever timezone the CI runner is in.
                base.addingTimeInterval(TimeInterval(-offset * 86_400 + i * 60))
            }
        }
    }

    func testCadenceCountsTrainingDaysNotSetLogs() {
        // The defect this exists to prevent: forty sets on Tuesday is ONE
        // training day. Dividing raw rows by weeks would tell an athlete
        // they train thirty times a week, and the commitment probe fires
        // off this number.
        let manySetsOverEightDays = dates(Array(stride(from: 0, to: 56, by: 7)), perDay: 40)
        let cadence = ConsultProbe.loggedCadence(sessionDates: manySetsOverEightDays)
        XCTAssertEqual(cadence ?? 0, 1.0, accuracy: 0.01)
    }

    func testCadenceIsSessionsPerWeekOverTheWindow() {
        // 16 distinct days across 8 weeks = 2 a week.
        let twiceWeekly = dates(Array(stride(from: 0, to: 56, by: 7))
                                + Array(stride(from: 3, to: 56, by: 7)))
        XCTAssertEqual(ConsultProbe.loggedCadence(sessionDates: twiceWeekly) ?? 0,
                       2.0, accuracy: 0.05)
    }

    func testAnEmptyLogIsNoEvidenceRatherThanZero() {
        // nil and 0.0 route differently: nil sends the athlete down the
        // cold-start branch, 0.0 would claim we watched them train nothing.
        XCTAssertNil(ConsultProbe.loggedCadence(sessionDates: []))
    }

    func testARidiculousWindowIsRefused() {
        XCTAssertNil(ConsultProbe.loggedCadence(sessionDates: dates([0, 1]), over: 3))
    }

    // MARK: - Stories

    private struct Story {
        let name: String
        let branch: String
        let context: ConsultProbe.Context
    }

    /// The sweep's spread, reduced to what the selector branches on:
    /// whether there is a log, whether intent matches the record, what is
    /// already known, and which door they came through.
    private static let stories: [Story] = {
        func context(log: Bool,
                     logged: Double? = nil,
                     stated: Int? = nil,
                     equipment: Bool = false,
                     minutes: Bool = false,
                     cautions: Bool = false,
                     youth: Bool = false) -> ConsultProbe.Context {
            var c = ConsultProbe.Context()
            c.hasLog = log
            c.loggedDaysPerWeek = logged
            c.statedDaysPerWeek = stated
            c.equipmentKnown = equipment
            c.sessionMinutesKnown = minutes
            c.cautionsKnown = cautions
            c.isYouth = youth
            return c
        }
        return [
            Story(name: "13-year-old, day one",
                  branch: "numbers", context: context(log: false, youth: true)),
            Story(name: "college footballer home for summer",
                  branch: "date", context: context(log: true, logged: 4, stated: 5)),
            Story(name: "powerlifter between coaches",
                  branch: "numbers", context: context(log: true, logged: 4, stated: 4)),
            Story(name: "returning after two years",
                  branch: "forge", context: context(log: true, logged: 0.2, stated: 3)),
            Story(name: "4-months postpartum",
                  branch: "running", context: context(log: true, logged: 2, stated: 3)),
            Story(name: "second-trimester, training through",
                  branch: "running", context: context(log: true, logged: 3, stated: 3)),
            Story(name: "masters lifter, bad shoulder",
                  branch: "size", context: context(log: true, logged: 3, stated: 3, cautions: true)),
            Story(name: "home gym, dumbbells only",
                  branch: "size", context: context(log: true, logged: 3, stated: 3, equipment: true)),
            Story(name: "shift worker, unpredictable",
                  branch: "running", context: context(log: true, logged: 1.5, stated: 4)),
            Story(name: "complete beginner, commercial gym",
                  branch: "forge", context: context(log: false)),
            Story(name: "endurance athlete adding lifting",
                  branch: "engine", context: context(log: true, logged: 5, stated: 5)),
            Story(name: "fully-profiled regular",
                  branch: "running",
                  context: context(log: true, logged: 4, stated: 4,
                                   equipment: true, minutes: true, cautions: true)),
        ]
    }()
}
