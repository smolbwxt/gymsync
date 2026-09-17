import XCTest
@testable import GymSync

/// Every string the round wait prints, and the pure laws that build them —
/// plan task S6.
///
/// The screen is a view and is proved by frame 137. What a screenshot cannot
/// prove is that a sentence is assembled the same way for a crew of two as for
/// a crew of five, or that an absent number reads as an absence rather than as
/// a zero. Those rules are extracted into `RoundCopy` and
/// `HeartRateZoneDisplay` precisely so these assertions can exist.
final class RoundWaitCopyTests: XCTestCase {

    // MARK: - The kicker

    func testTheKickerNamesTheCrewAndTheRound() {
        XCTAssertEqual(RoundCopy.kicker(crew: "Push Crew", round: 3),
                       "PUSH CREW · ROUND 3")
    }

    /// A session with no group has no crew name — the kicker is the round
    /// alone rather than a stray separator.
    func testTheKickerWithoutACrewIsTheRoundAlone() {
        XCTAssertEqual(RoundCopy.kicker(crew: "", round: 1), "ROUND 1")
    }

    // MARK: - The elapsed rest

    func testElapsedFormatsMinutesAndPaddedSeconds() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(RoundCopy.elapsed(since: start,
                                         now: start.addingTimeInterval(102)), "1:42")
        XCTAssertEqual(RoundCopy.elapsed(since: start,
                                         now: start.addingTimeInterval(9)), "0:09")
        XCTAssertEqual(RoundCopy.elapsed(since: start,
                                         now: start.addingTimeInterval(600)), "10:00")
    }

    /// A rest that has not started has not run backwards — `WarmUpGate`'s own
    /// law, kept identical so two clocks in one app cannot disagree.
    func testElapsedIsZeroWithoutAStartAndNeverNegative() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(RoundCopy.elapsed(since: nil, now: start), "0:00")
        XCTAssertEqual(RoundCopy.elapsed(since: start,
                                         now: start.addingTimeInterval(-60)), "0:00")
    }

    // MARK: - WAITING ON …

    func testWaitingOnOneName() {
        XCTAssertEqual(RoundCopy.waitingOn(["Sam"]), "WAITING ON SAM")
    }

    func testWaitingOnTwoNamesTakesAnd() {
        XCTAssertEqual(RoundCopy.waitingOn(["Sam", "Lee"]), "WAITING ON SAM AND LEE")
    }

    func testWaitingOnThreeNamesTakesCommasAndAFinalAnd() {
        XCTAssertEqual(RoundCopy.waitingOn(["Sam", "Lee", "Mo"]),
                       "WAITING ON SAM, LEE AND MO")
    }

    /// The control does not render at all with nobody outstanding
    /// (`RoundWaitView` gates on `waitingOn.isEmpty`), but the law still has
    /// to answer something rather than trail off.
    func testWaitingOnNobodyNamesTheCrew() {
        XCTAssertEqual(RoundCopy.waitingOn([]), "WAITING ON THE CREW")
        XCTAssertEqual(RoundCopy.waitingOn([""]), "WAITING ON THE CREW")
    }

    // MARK: - NEXT

    func testTheNextPrescriptionIsSetOfTargetThenTheMovement() {
        XCTAssertEqual(
            RoundCopy.nextPrescription(setNumber: 3, targetSets: 4,
                                       exercise: "Back squat", prescription: "225 × 5"),
            "Set 3 of 4 · Back squat 225 × 5")
    }

    /// Every part is optional because every part can genuinely be missing.
    /// What is absent is LEFT OUT — a dash inside a sentence reads as a broken
    /// value, not as an honest absence.
    func testTheNextPrescriptionOmitsWhatIsMissing() {
        XCTAssertEqual(
            RoundCopy.nextPrescription(setNumber: 2, targetSets: nil,
                                       exercise: "Back squat", prescription: nil),
            "Set 2 · Back squat")
        XCTAssertEqual(
            RoundCopy.nextPrescription(setNumber: 1, targetSets: 5,
                                       exercise: nil, prescription: nil),
            "Set 1 of 5")
        XCTAssertEqual(
            RoundCopy.nextPrescription(setNumber: 1, targetSets: nil,
                                       exercise: nil, prescription: ""),
            "Set 1")
    }

    // MARK: - The achievability line (spec §2)

    func testAchievabilityStatesWhatWasMovedWhenThePlanHolds() {
        XCTAssertEqual(
            RoundCopy.achievability(lastMoved: "225", target: "225", isUnderTarget: false),
            "Last set moved at 225. The plan still holds.")
    }

    func testAchievabilityNamesTheGapWhenTheLastSetCameInUnder() {
        XCTAssertEqual(
            RoundCopy.achievability(lastMoved: "205", target: "225", isUnderTarget: true),
            "Last set moved at 205 — under the 225 on the plan.")
    }

    /// Nothing logged is an ABSENCE, not a failure — and with no target there
    /// is no gap to name, whatever `isUnderTarget` claims.
    func testAchievabilityWithNothingLoggedOrNoTarget() {
        XCTAssertEqual(
            RoundCopy.achievability(lastMoved: nil, target: "225", isUnderTarget: true),
            "Nothing logged on this movement yet.")
        XCTAssertEqual(
            RoundCopy.achievability(lastMoved: "", target: "225", isUnderTarget: true),
            "Nothing logged on this movement yet.")
        XCTAssertEqual(
            RoundCopy.achievability(lastMoved: "225", target: nil, isUnderTarget: true),
            "Last set moved at 225. The plan still holds.")
    }

    // MARK: - The zone, as a word (§4a, owner decision 17)

    /// The colour is the one exception to the colour rules, and it NEVER
    /// travels alone — this is the word that goes with it, on the recovery
    /// curve's endpoint (S6), the spotter's crew rows (S8) and Together's
    /// timeline (S9).
    func testEveryZoneHasItsWord() {
        XCTAssertEqual(HeartRateZoneDisplay.word(.warmup), "Z1")
        XCTAssertEqual(HeartRateZoneDisplay.word(.moderate), "Z2")
        XCTAssertEqual(HeartRateZoneDisplay.word(.hard), "Z3")
        XCTAssertEqual(HeartRateZoneDisplay.word(.max), "Z4")
    }

    /// Four zones, four distinct words — a mapping that collapsed two would
    /// leave a colour-blind reader with less than the colour gives.
    func testTheZoneWordsAreDistinct() {
        let words = HeartRateZone.allCases.map { HeartRateZoneDisplay.word($0) }
        XCTAssertEqual(Set(words).count, HeartRateZone.allCases.count)
    }

    // MARK: - The frame's world (frame 137)

    /// Frame 137 is two racks at equal height, one ringed lifter, one
    /// scale-down line, and two lifters the round is still waiting on.
    func testTheRoundWaitWorld() {
        let world = LiveFixtures.roundWait
        XCTAssertEqual(world.kicker, "PUSH CREW · ROUND 3")
        XCTAssertEqual(world.stations.count, 2)
        XCTAssertEqual(world.stations[0].lifters.count, 3)
        XCTAssertEqual(world.stations[1].lifters.count, 2)
        XCTAssertEqual(world.stations[0].liftingID, LiveFixtures.samID)
        XCTAssertNil(world.stations[1].liftingID)
        XCTAssertEqual(world.stations[0].lifters.compactMap(\.scaleDown), ["Goblet squat"])
        XCTAssertEqual(RoundCopy.waitingOn(world.waitingOn), "WAITING ON SAM AND LEE")
    }

    /// The reference frame's `128 → 96` as a shape: ten samples, normalized,
    /// falling the whole way. The endpoint is Z1, which is what the caption
    /// prints beside the number.
    func testTheRestWorldIsAFallingCurveEndingAtZ1() {
        let rest = LiveFixtures.rest
        XCTAssertEqual(rest.curve.count, 10)
        XCTAssertEqual(rest.curve.first, 1.0)
        XCTAssertEqual(rest.curve.last, 0.0)
        XCTAssertEqual(rest.curve, rest.curve.sorted(by: >))
        XCTAssertEqual(rest.bpm, 96)
        XCTAssertEqual(rest.zone, .warmup)
        XCTAssertEqual(rest.nextPrescription, "Set 3 of 4 · Back squat 225 × 5")
        XCTAssertEqual(rest.achievability, "Last set moved at 225. The plan still holds.")
    }

    /// SPEC §3.6 — one door in three places. The round wait's Coach row
    /// prints the LOBBY'S OWN two strings, so the crew meets one door and not
    /// two that read alike.
    func testTheCoachDoorIsTheLobbysDoor() {
        XCTAssertEqual(LiveFixtures.coach.title, SessionCopy.talkToCoach)
        XCTAssertEqual(LiveFixtures.coach.detail, SessionCopy.talkToCoachDetail)
        XCTAssertNil(LiveFixtures.coach.note)
    }

    /// CONSTRAINT 11 — the plan card's line is the routine's name, which is
    /// all production has for it today. A fixture that printed a per-lifter
    /// rung would be a frame production cannot reproduce.
    func testThePlanCarriesTheCrewsProgressAndAnHonestLine() {
        XCTAssertEqual(LiveFixtures.rungLine, "Push Crew · leg day")
        XCTAssertEqual(LiveFixtures.plan.filter(\.isCurrent).count, 1)
        XCTAssertEqual(LiveFixtures.plan.first?.setsDone, 2)
        XCTAssertEqual(LiveFixtures.plan.first?.sets, 4)
    }

    /// FIX ROUND 1 / F3 — the reaction pills have a surface again. The round
    /// wait's foot is their call site, and the fixture carries the live view's
    /// own four.
    func testTheReactionStripHasItsFourPills() {
        XCTAssertEqual(LiveFixtures.roundWait.reactionEmojis, ["🔥", "💪", "😂", "👏"])
    }

    // MARK: - The hold's copy (spec §9a, plan task S7)

    /// THE PRONOUN. The spec writes "without him"; the app knows no pronoun
    /// for anybody — `profiles` has no gender column, and guessing one from a
    /// name is how software insults people — so production says THEM, and
    /// this assertion is what stops a later edit guessing.
    func testTheSkipOfferSaysThem() {
        XCTAssertEqual(RoundCopy.skipOffer(name: "Sam"),
                       "Sam's still resting — go ahead without them?")
    }

    /// §9a's rule made legible: both figures, so the offer reads as the
    /// crew's own measured rest and not as the app deciding somebody is slow.
    func testTheWaitedLinePrintsBothFigures() {
        XCTAssertEqual(RoundCopy.skipWaited(waited: 151, threshold: 144),
                       "Waited 2:31 — past the 2:24 the crew's own rest sets.")
    }

    /// The skip costs the lifter nothing, and the line says so — no penalty
    /// row, no `skipped` flag, their set still in their plan.
    func testTheConsequenceLineIsTheWholeCost() {
        XCTAssertEqual(RoundCopy.skipConsequence,
                       "Nothing is recorded against them. They rejoin next round.")
    }

    /// The held lifter's own control, and the line under it that says exactly
    /// what the tap does (rule 9).
    func testTheMinutesCopy() {
        XCTAssertEqual(RoundCopy.needAMinute, "I need a minute")
        XCTAssertEqual(RoundCopy.needAMinuteDetail,
                       "Adds a minute before the crew is offered a skip.")
    }

    /// The marker rides the reaction channel, so it must not be one of the
    /// pills a crewmate can tap — otherwise a 🔥 would buy somebody a minute.
    func testTheMinuteMarkerIsNotAReactionPill() {
        XCTAssertFalse(LiveFixtures.reactionEmojis.contains(RoundCopy.minuteMarker))
    }

    func testDurationsAreMinutesAndPaddedSeconds() {
        XCTAssertEqual(RoundCopy.clock(0), "0:00")
        XCTAssertEqual(RoundCopy.clock(9), "0:09")
        XCTAssertEqual(RoundCopy.clock(151), "2:31")
        XCTAssertEqual(RoundCopy.clock(-30), "0:00")
    }

    // MARK: - The hold's world (frame 138)

    /// Frame 138 is the SAME screen with the line present — and with ONE
    /// lifter out, not two: `RoundHold.holdStartedAt` returns nil while two
    /// are outstanding, so a world that showed the offer over an unticked Lee
    /// would contradict the law the frame illustrates.
    func testTheHoldWorldIsTheSameScreenWithOneLifterOut() {
        let hold = LiveFixtures.roundHold
        let wait = LiveFixtures.roundWait
        XCTAssertEqual(hold.kicker, wait.kicker)
        XCTAssertEqual(hold.plan, wait.plan)
        XCTAssertEqual(hold.rest, wait.rest)
        XCTAssertEqual(hold.waitingOn, ["Sam"])
        XCTAssertNil(wait.skip)
        XCTAssertNotNil(hold.skip)
        let unticked = hold.stations.flatMap(\.lifters).filter { !$0.hasLogged }
        XCTAssertEqual(unticked.count, 1)
        XCTAssertEqual(unticked.first?.id, LiveFixtures.samID)
    }

    // MARK: - Spotter mode's copy (spec §1, owner decision 7, plan task S8)

    func testTheSpottersFourStrings() {
        XCTAssertEqual(RoundCopy.spotterNoSet, "Your plan has no set this round.")
        XCTAssertEqual(RoundCopy.spotterWithTheCrew,
                       "You're with the crew — not in a recap on your own.")
        XCTAssertEqual(RoundCopy.crewRightNow, "THE CREW, RIGHT NOW")
        XCTAssertEqual(RoundCopy.sharedByDefault, "SHARED BY DEFAULT")
        XCTAssertEqual(RoundCopy.cheer, "Cheer")
    }

    /// THE REFERENCE FRAME SAYS "until round 5" AND PRODUCTION DOES NOT.
    /// Which round a lifter rejoins on depends on four other people's
    /// remaining sets; `upcomingTurnHint` already refuses to fabricate the
    /// same kind of number. This assertion is the refusal, written down.
    func testTheWithTheCrewLineNamesNoRound() {
        XCTAssertFalse(RoundCopy.spotterWithTheCrew.lowercased().contains("round"))
    }

    func testTheStillToGoCount() {
        XCTAssertEqual(RoundCopy.stillToGo(2), "2 STILL TO GO")
        XCTAssertEqual(RoundCopy.stillToGo(1), "1 STILL TO GO")
    }

    /// Frame 139: four lifters, one lifting, all four zones across the ramp,
    /// and one STALE reading — the em-dash case a screenshot proves and a
    /// unit test cannot draw.
    func testTheSpotterWorld() {
        let world = LiveFixtures.spotter
        XCTAssertEqual(world.kicker, "PUSH CREW · ROUND 4")
        XCTAssertEqual(world.crew.count, 4)
        XCTAssertEqual(world.crew.filter(\.isLifting).count, 1)
        XCTAssertEqual(world.crew.first?.name, "Dana Kord")
        XCTAssertNil(world.crew.last?.bpm)
        XCTAssertNil(world.crew.last?.zone)
        XCTAssertEqual(world.turn.filter(\.isNow).count, 1)
        XCTAssertEqual(world.stillToGo, "2 STILL TO GO")
    }

    /// The frame's zones are DERIVED from its bpm values, never written down,
    /// so a fixture cannot disagree with the app about what 158 is.
    func testTheSpottersZonesAreDerivedFromTheReadings() {
        for row in LiveFixtures.spotter.crew {
            XCTAssertEqual(row.zone, row.bpm.map { HeartRateZone.zone(bpm: $0) },
                           "\(row.name)")
        }
    }

    /// The threshold on the frame is `RoundHold`'s answer for a 96 s median —
    /// `1.5 × 96 = 144`, between the floor and the cap — so the frame shows
    /// the MULTIPLIER doing the work rather than a clamp. Never a literal.
    func testTheHoldWorldsNumbersComeFromRoundHold() {
        let skip = LiveFixtures.skipOffer
        XCTAssertEqual(skip.threshold, RoundHold.threshold(medianRestSeconds: 96))
        XCTAssertEqual(skip.threshold, 144)
        XCTAssertGreaterThan(skip.waited, skip.threshold)
        XCTAssertEqual(RoundCopy.skipWaited(waited: skip.waited, threshold: skip.threshold),
                       "Waited 2:31 — past the 2:24 the crew's own rest sets.")
        XCTAssertEqual(RoundCopy.skipOffer(name: skip.name),
                       "Sam's still resting — go ahead without them?")
    }

    // MARK: - Freestyle's copy (plan task S10)

    /// The plan's own quoted sentence, verbatim, at the exact count it
    /// quotes — two.
    func testTheStretchSentenceMatchesThePlansOwnQuote() {
        XCTAssertEqual(RoundCopy.freestyleStretchSentence(setsAhead: 2),
                       "You're two sets up — Coach is stretching your rest to keep the crew together.")
    }

    /// Small counts stay in words; the sentence still reads past ten rather
    /// than crashing on a table with no entry for it.
    func testTheStretchSentenceScalesPastTheWordTable() {
        XCTAssertEqual(RoundCopy.freestyleStretchSentence(setsAhead: 5),
                       "You're five sets up — Coach is stretching your rest to keep the crew together.")
        XCTAssertEqual(RoundCopy.freestyleStretchSentence(setsAhead: 12),
                       "You're 12 sets up — Coach is stretching your rest to keep the crew together.")
    }

    func testTheAccessorySentenceNamesTheRowAndItsPrescription() {
        XCTAssertEqual(RoundCopy.freestyleAccessorySentence(name: "Face pulls", prescription: "3 × 12"),
                       "While they catch up — Face pulls, 3 × 12?")
    }

    func testFreestylesOwnStrings() {
        XCTAssertEqual(RoundCopy.freestyleTitle, "Own pace")
        XCTAssertEqual(RoundCopy.freestyleRailKicker, "THE CREW · SETS DONE")
        XCTAssertEqual(RoundCopy.freestyleOfTotal(18), "OF 18")
        XCTAssertEqual(RoundCopy.freestyleYourRest, "YOUR REST")
        XCTAssertFalse(RoundCopy.freestyleBehindLine.isEmpty)
    }
}
