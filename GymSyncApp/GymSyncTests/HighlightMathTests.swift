import XCTest
@testable import GymSync

/// Spec §1 line 4, as this release ships it: the top set and the PR, no free
/// text, and a weight that still reads right in a friend's own unit. The
/// milestone proposal waits for `MilestoneCatalog` (controller ruling) and its
/// absence is asserted below, so the day it arrives a test says so.
final class HighlightMathTests: XCTestCase {

    private func set(_ weight: Decimal?, _ reps: Int?,
                     pr: Bool = false, failed: Bool = false)
        -> PostSummary.ExerciseEntry.SetEntry {
        .init(weightLbs: weight, reps: reps, isPR: pr, isFailed: failed)
    }

    private func summary(_ exercises: [PostSummary.ExerciseEntry],
                         volume: Decimal = 7_240) -> PostSummary {
        PostSummary(durationSeconds: 2_520, totalVolumeLbs: volume,
                    exercises: exercises, routineName: "Push day")
    }

    func testTheBestSetIsTheBestEstimatedMaxNotTheHeaviestBar() {
        let s = summary([
            .init(name: "Back Squat", equipment: "barbell",
                  sets: [set(225, 8), set(245, 1)]),
        ])
        // 225 × 8 implies more than 245 × 1 under StatMath's own formula.
        XCTAssertEqual(HighlightMath.bestSet(in: s)?.set.reps, 8)
    }

    func testFailedAndUnweightedSetsAreNotCandidates() {
        let s = summary([
            .init(name: "Back Squat", equipment: "barbell",
                  sets: [set(315, 3, failed: true), set(185, 5)]),
            .init(name: "Walking Lunge", equipment: "bodyweight", sets: [set(nil, 20)]),
        ])
        XCTAssertEqual(HighlightMath.bestSet(in: s)?.set.weightLbs, 185)
    }

    func testAPRSuppressesTheTopSetWhenTheyAreTheSameSet() {
        let s = summary([
            .init(name: "Back Squat", equipment: "barbell",
                  sets: [set(225, 5), set(235, 3, pr: true)]),
        ])
        let proposals = HighlightMath.propose(summary: s)
        XCTAssertEqual(proposals.map(\.kind), [.pr], "one fact, once")
    }

    func testATopSetAndADifferentPRAreBothOffered() {
        let s = summary([
            .init(name: "Back Squat", equipment: "barbell", sets: [set(315, 5)]),
            .init(name: "Bench Press", equipment: "barbell", sets: [set(185, 3, pr: true)]),
        ])
        XCTAssertEqual(HighlightMath.propose(summary: s).map(\.kind), [.topSet, .pr])
    }

    /// THE MILESTONE PROPOSAL IS NOT OFFERED IN THIS RELEASE (controller
    /// ruling): the one catalog is the You hero's `MilestoneCatalog`, and a
    /// private ladder here would be a second accounting of the same pounds.
    /// This test is the guard on that decision — it fails the day someone
    /// adds an arm without wiring it to the catalog, which is precisely when
    /// somebody should be reading this comment.
    func testNoMilestoneIsProposedUntilTheCatalogShips() {
        let s = summary([
            .init(name: "Back Squat", equipment: "barbell", sets: [set(315, 5)]),
        ], volume: 7_240)
        XCTAssertFalse(HighlightMath.propose(summary: s).contains { $0.kind == .milestone })
    }

    func testNeverMoreThanThree() {
        let s = summary([
            .init(name: "Back Squat", equipment: "barbell", sets: [set(315, 5)]),
            .init(name: "Bench Press", equipment: "barbell", sets: [set(185, 3, pr: true)]),
        ])
        XCTAssertLessThanOrEqual(HighlightMath.propose(summary: s).count, 3)
    }

    func testNoCandidatesMeansNoPicker() {
        let s = summary([
            .init(name: "Walking Lunge", equipment: "bodyweight", sets: [set(nil, 20)]),
        ])
        XCTAssertTrue(HighlightMath.propose(summary: s).isEmpty)
    }

    // MARK: - the viewer's unit

    /// THE FORMATTER IS THE AUTHORITY, NOT THE PLAN (task S2.5 step 4). The
    /// plan's draft expected `225 lb`; `WeightUnit.label` is its rawValue and
    /// `WeightUnit.lbs.rawValue` is **"lbs"** (`Units.swift:14-18`), so
    /// `Units.format(pounds:unit:rounded:includeUnit:)` writes `225 lbs`.
    /// The expectation below is the shipped formatter's own spelling.
    func testTheLineRendersInTheViewersUnit() {
        let pr = PostHighlight(kind: .pr, text: "PR — Back Squat",
                               weightLbs: 225, reps: 3)
        XCTAssertEqual(HighlightText.line(pr, unit: .lbs), "PR — Back Squat 225 lbs × 3")
        XCTAssertTrue(HighlightText.line(pr, unit: .kg).contains("kg"),
                      "a frozen string would have shown a kilo lifter pounds")
    }

    func testAMilestoneLineIsCompact() {
        let milestone = PostHighlight(kind: .milestone, text: "Lifetime total crossed",
                                      weightLbs: 1_000_000, reps: nil)
        XCTAssertEqual(HighlightText.line(milestone, unit: .lbs),
                       "Lifetime total crossed — 1M lbs")
    }
}
