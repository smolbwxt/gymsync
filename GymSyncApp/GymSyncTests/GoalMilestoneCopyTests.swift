import XCTest
@testable import GymSync

/// The milestone card's pure half.
///
/// A SwiftUI body is not unit-testable in this target, so everything that can
/// be WRONG lives in `GoalMilestoneCopy` and is tested here: the seed each
/// preset opens on, the sentence Coach says under the levers, and — task C3 —
/// that the levers change the milestone and never the metric.
final class GoalMilestoneCopyTests: XCTestCase {

    func testTheStrengthLineIsTheSpecsOwn() {
        let line = GoalMilestoneCopy.coachLine(
            preset: .strength,
            current: GoalTarget(targetWeightLbs: 205),
            draft: BlockGoalDraft(metric: .liftOneRepMax,
                                  target: GoalTarget(targetWeightLbs: 225),
                                  byDate: nil, preset: .strength),
            weeks: 6, unit: .lbs)
        XCTAssertEqual(line, "You're at 205 now; that's about 6 weeks of work.")
    }

    func testEveryPresetProducesADraftItsMetricCanRead() {
        for preset in GoalPreset.allCases {
            let draft = GoalMilestoneCopy.draft(preset: preset,
                                                current: GoalTarget(),
                                                today: Date(timeIntervalSince1970: 0),
                                                unit: .lbs)
            XCTAssertEqual(draft.metric, preset.metric, "\(preset.rawValue)")
            XCTAssertEqual(draft.preset, preset)
            XCTAssertEqual(draft.source, .user, "the door is the athlete choosing")
            if preset.asksForDate {
                XCTAssertNotNil(draft.byDate, "\(preset.rawValue) is seeded with a date")
            } else {
                XCTAssertNil(draft.byDate,
                             "\(preset.rawValue) is held for the block; it has no deadline")
            }
        }
    }

    func testMaintenanceSeedsEveryMajorGroup() {
        let draft = GoalMilestoneCopy.draft(preset: .maintenance,
                                            current: GoalTarget(),
                                            today: Date(timeIntervalSince1970: 0),
                                            unit: .lbs)
        XCTAssertEqual(Set(draft.target.muscleTargets?.keys ?? [:].keys),
                       Set(MuscleGroup.allCases.map(\.rawValue)),
                       "owner decision 9: every major group")
    }

    func testAnUnreachableMilestoneReplacesTheLineWithTheGap() {
        let reach = GoalBlockLength.Reach(reaches: false,
                                          projected: GoalTarget(targetWeightLbs: 218),
                                          achievableDate: Date(timeIntervalSince1970: 1_795_000_000))
        let line = GoalMilestoneCopy.coachLine(
            preset: .strength, current: GoalTarget(targetWeightLbs: 205),
            draft: BlockGoalDraft(metric: .liftOneRepMax,
                                  target: GoalTarget(targetWeightLbs: 225),
                                  byDate: Date(timeIntervalSince1970: 1_792_411_200),
                                  preset: .strength),
            weeks: 6, unit: .lbs, reach: reach)
        XCTAssertTrue(line.contains("more than this block can safely give"),
                      "the ladder never lies about the gap")
    }

    // MARK: - Task C3: the primary hands over the EDITED draft

    func testThePrimaryHandsOverTheEditedDraftAndNotTheSeed() {
        let bench = UUID()
        let seeded = GoalMilestoneCopy.draft(preset: .strength,
                                             current: GoalTarget(exerciseID: bench,
                                                                 targetWeightLbs: 205),
                                             today: Date(timeIntervalSince1970: 0),
                                             unit: .lbs)
        let edited = GoalMilestoneCopy.applying(seeded,
                                                exerciseID: bench,
                                                targetWeightLbs: 245,
                                                byDate: Date(timeIntervalSince1970: 1_795_000_000))
        XCTAssertEqual(edited.target.targetWeightLbs, 245)
        XCTAssertEqual(edited.target.exerciseID, bench)
        XCTAssertNotEqual(edited.byDate, seeded.byDate)
        XCTAssertEqual(edited.metric, seeded.metric,
                       "the levers change the milestone, never the metric")
        XCTAssertEqual(edited.preset, .strength)
    }

    // MARK: - The seeds, one preset at a time

    /// The catalog's own strength frame: 205 now, 225 asked for. Ten percent,
    /// snapped to a loadable increment — not an arbitrary literal, which is
    /// why a kg athlete gets a kg-loadable rung rather than a converted one.
    func testTheStrengthSeedIsTenPercentSnappedToAPlateStep() {
        let draft = GoalMilestoneCopy.draft(
            preset: .strength,
            current: GoalTarget(targetWeightLbs: 205),
            today: Date(timeIntervalSince1970: 0), unit: .lbs)
        XCTAssertEqual(draft.target.targetWeightLbs, 225)
    }

    /// Never a milestone the athlete is already standing on.
    func testAStrengthSeedIsAlwaysAboveWhereTheAthleteIs() {
        for pounds in stride(from: Decimal(45), through: Decimal(500), by: 5) {
            let raised = GoalMilestoneCopy.raisedLoad(from: pounds, unit: .lbs)
            XCTAssertGreaterThan(raised, pounds, "\(pounds)")
        }
    }

    /// The date is the block's LAST DAY, so `GoalBlockLength.weeks` reads the
    /// same block length back out of it. The two halves of the door cannot
    /// disagree about how long the block is.
    func testTheSeededDateRoundTripsToTheBlockLength() {
        let today = Date(timeIntervalSince1970: 1_788_696_000)
        for weeks in [4, 6, 8, 12, 16] {
            let date = GoalMilestoneCopy.milestoneDate(from: today, weeks: weeks)
            XCTAssertEqual(GoalBlockLength.weeks(byDate: date, from: today), weeks,
                           "\(weeks) weeks")
        }
    }

    /// Held for the block: no number to chase, so no "you're at 0 now".
    func testAHeldGoalSaysItIsHeldRatherThanReadingZero() {
        for preset in [GoalPreset.maintenance, .recovery] {
            let draft = GoalMilestoneCopy.draft(preset: preset, current: GoalTarget(),
                                                today: Date(timeIntervalSince1970: 0),
                                                unit: .lbs, weeks: 6)
            let line = GoalMilestoneCopy.coachLine(preset: preset, current: GoalTarget(),
                                                   draft: draft, weeks: 6, unit: .lbs)
            XCTAssertEqual(line, "I'll hold this for 6 weeks.", preset.rawValue)
        }
    }

    /// A metric with nothing logged says so; it never prints a zero standing
    /// in for an absent reading — the shipped strip's own rule.
    func testAnUnreadMetricSaysSoRatherThanReadingZero() {
        for preset in GoalPreset.allCases where preset.asksForDate {
            let reading = GoalMilestoneCopy.currentReading(preset: preset,
                                                           current: GoalTarget(),
                                                           unit: .lbs)
            XCTAssertNil(reading, "\(preset.rawValue) has nothing measured")
        }
    }

    func testEveryPresetProducesALineThatIsASentence() {
        for preset in GoalPreset.allCases {
            let draft = GoalMilestoneCopy.draft(preset: preset, current: GoalTarget(),
                                                today: Date(timeIntervalSince1970: 0),
                                                unit: .lbs)
            let line = GoalMilestoneCopy.coachLine(preset: preset, current: GoalTarget(),
                                                   draft: draft, weeks: 8, unit: .lbs)
            XCTAssertFalse(line.isEmpty, preset.rawValue)
            XCTAssertTrue(line.hasSuffix("."), "\(preset.rawValue): \(line)")
        }
    }

    /// Only the three presets whose milestone names a THING can be
    /// under-specified, and each says which thing is missing.
    func testOnlyAMilestoneMissingItsSubjectBlocksThePrimary() {
        let blocked: Set<GoalPreset> = [.strength, .repStrength, .muscle, .benchmark]
        for preset in GoalPreset.allCases {
            let empty = BlockGoalDraft(metric: preset.metric, target: GoalTarget(),
                                       byDate: nil, preset: preset)
            let reason = GoalMilestoneCopy.incompleteReason(preset: preset, draft: empty)
            if blocked.contains(preset) {
                XCTAssertNotNil(reason, "\(preset.rawValue) must say what is missing")
                XCTAssertTrue(reason?.hasSuffix(".") ?? false, preset.rawValue)
            } else {
                XCTAssertNil(reason, "\(preset.rawValue) cannot be incomplete")
            }
        }
    }

    /// A seeded card is buildable the moment it opens, for every preset whose
    /// subject the athlete's log already names.
    func testASeededCardIsBuildable() {
        let bench = UUID(), murph = UUID()
        let current = GoalTarget(exerciseID: bench, muscleTargets: ["chest": 10],
                                 routineID: murph)
        for preset in GoalPreset.allCases {
            let draft = GoalMilestoneCopy.draft(preset: preset, current: current,
                                                today: Date(timeIntervalSince1970: 0),
                                                unit: .lbs)
            XCTAssertNil(GoalMilestoneCopy.incompleteReason(preset: preset, draft: draft),
                         preset.rawValue)
        }
    }

    /// The two body-composition readings are one milestone said two ways, so
    /// stepping either one may never leave the card contradicting itself.
    func testTheBodyCompositionRateAndWeightAgree() {
        let target = GoalMilestoneCopy.projectedBodyWeight(
            from: 190, ratePercent: GoalMilestoneCopy.bodyCompositionRatePercent,
            weeks: 8, unit: .lbs)
        let implied = GoalMilestoneCopy.impliedRatePercent(from: 190, to: target, weeks: 8)
        XCTAssertEqual(implied, GoalMilestoneCopy.bodyCompositionRatePercent,
                       accuracy: 0.05,
                       "the rate the weight implies is the rate that produced it")
    }

    // MARK: - The block length tracks the date (review finding 1)

    /// **THE DATE IS THE HORIZON.** On the eight date-bearing presets nothing
    /// renders a weeks stepper, so the milestone date is the only lever that
    /// moves the block length — and everything downstream of it has to move
    /// when it does: Coach's "about N weeks of work", and body composition's
    /// rate, which is a weight divided by a horizon.
    ///
    /// Before the fix, `weeks` was `@State` written in one place that eight of
    /// eleven cards never drew, so a milestone six months out still read
    /// "about 8 weeks of work" and frame 95's three readings stopped being
    /// true of one block the moment the date moved.
    func testMovingTheDateMovesTheBlockLengthTheLineAndTheRate() throws {
        let today = Date(timeIntervalSince1970: 1_788_696_000)
        let current = GoalTarget(bodyWeightLbs: 190)
        let seeded = GoalMilestoneCopy.draft(preset: .bodyComposition, current: current,
                                             today: today, unit: .lbs)
        let seededDate = try XCTUnwrap(seeded.byDate)

        let before = GoalMilestoneCopy.weeks(preset: .bodyComposition, byDate: seededDate,
                                             heldWeeks: 8, today: today)
        XCTAssertEqual(before, 8, "the seed is an eight-week block")

        let movedDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 28,
                                                           to: seededDate))
        let moved = GoalMilestoneCopy.applying(seeded, byDate: movedDate)
        let after = GoalMilestoneCopy.weeks(preset: .bodyComposition, byDate: movedDate,
                                            heldWeeks: 8, today: today)
        XCTAssertEqual(after, 12, "four weeks later is a twelve-week block")

        // Coach's line counts the new horizon.
        let lineBefore = GoalMilestoneCopy.coachLine(preset: .bodyComposition, current: current,
                                                     draft: seeded, weeks: before, unit: .lbs)
        let lineAfter = GoalMilestoneCopy.coachLine(preset: .bodyComposition, current: current,
                                                    draft: moved, weeks: after, unit: .lbs)
        XCTAssertTrue(lineBefore.contains("8 weeks of work"), lineBefore)
        XCTAssertTrue(lineAfter.contains("12 weeks of work"), lineAfter)
        XCTAssertNotEqual(lineBefore, lineAfter)

        // A WEIGHT: the weight the athlete set stays, and the RATE follows the
        // date — the same pounds over a longer block is a gentler cut.
        let heldWeight = GoalMilestoneCopy.rebalancedBodyComposition(
            moved, startLbs: 190, weeks: after, stepsTheRate: false, unit: .lbs)
        XCTAssertEqual(heldWeight.target.bodyWeightLbs, moved.target.bodyWeightLbs,
                       "the reading the athlete holds is the one that stays")
        let rateBefore = try XCTUnwrap(seeded.target.bodyWeightRatePercent)
        let rateAfter = try XCTUnwrap(heldWeight.target.bodyWeightRatePercent)
        XCTAssertGreaterThan(rateAfter, rateBefore,
                             "a longer block is a gentler rate, not the same one")

        // A RATE: the rate stays and the WEIGHT follows.
        let heldRate = GoalMilestoneCopy.rebalancedBodyComposition(
            moved, startLbs: 190, weeks: after, stepsTheRate: true, unit: .lbs)
        XCTAssertEqual(heldRate.target.bodyWeightRatePercent,
                       moved.target.bodyWeightRatePercent)
        XCTAssertNotEqual(heldRate.target.bodyWeightLbs, moved.target.bodyWeightLbs,
                          "the same rate over four more weeks lands somewhere else")
    }

    /// The three presets `GoalPreset.asksForDate` excludes are held for the
    /// block, so their stepper — the only lever they have — IS the answer.
    func testAHeldPresetsBlockLengthIsTheStepperAndNotADate() {
        let today = Date(timeIntervalSince1970: 1_788_696_000)
        for preset in GoalPreset.allCases where !preset.asksForDate {
            XCTAssertEqual(
                GoalMilestoneCopy.weeks(preset: preset, byDate: nil, heldWeeks: 6, today: today),
                6, preset.rawValue)
        }
        XCTAssertEqual(Set(GoalPreset.allCases.filter { !$0.asksForDate }),
                       [.maintenance, .recovery, .consistency],
                       "three held presets, and they are the three with the stepper")
    }

    /// The stepper's answer is clamped to the generator's own limits, so a
    /// held block can never be shorter than a wave or longer than the column
    /// allows.
    func testAHeldBlockLengthIsClampedToTheGeneratorsLimits() {
        let today = Date(timeIntervalSince1970: 1_788_696_000)
        XCTAssertEqual(GoalMilestoneCopy.weeks(preset: .recovery, byDate: nil,
                                               heldWeeks: 1, today: today),
                       GoalBlockLength.minimumWeeks)
        XCTAssertEqual(GoalMilestoneCopy.weeks(preset: .recovery, byDate: nil,
                                               heldWeeks: 500, today: today),
                       GoalBlockLength.maximumWeeks)
    }

    /// Deterministic on a tie: a dictionary's maximum is not, and a catalog
    /// frame must be.
    func testTheLeadingGroupIsDeterministicOnATie() {
        let tied = GoalTarget(muscleTargets: ["legs": 12, "back": 12, "chest": 12])
        for _ in 0..<25 {
            XCTAssertEqual(GoalMilestoneCopy.leadingGroup(tied), .back)
        }
    }
}
