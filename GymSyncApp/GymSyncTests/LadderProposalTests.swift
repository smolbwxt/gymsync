import XCTest
@testable import GymSync

/// `LadderProposal` and its maths — plan task S1.
///
/// PURE. No database, no clock: every date is built from components and the
/// only repository these touch is a stub declared in this file. The value
/// under test is the one spec §4 calls for — "every change to weight, volume
/// or sets is a suggestion the athlete accepts" — so what is asserted here is
/// what the athlete will read on the card.
final class LadderProposalTests: XCTestCase {

    // MARK: - Fixtures

    private static let goalID = UUID(uuidString: "00000000-0000-0000-0000-0000000000d1") ?? UUID()

    /// Noon UTC from components, never an epoch literal — the
    /// `StubBlockGoalRepository.utcDate` idiom.
    private static let derivedAt: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))
            ?? Date(timeIntervalSince1970: 0)
    }()

    /// The stub ladder's own week keys — Sundays from 2026-08-23 — so a rung
    /// in this file and a rung in `StubBlockGoalRepository` describe the same
    /// calendar rather than two that read alike.
    private static let weekKeys = ["2026-08-23", "2026-08-30", "2026-09-06",
                                   "2026-09-13", "2026-09-20", "2026-09-27",
                                   "2026-10-04", "2026-10-11"]

    private func rung(_ weekIndex: Int, _ pounds: Decimal, reps: Int? = 5,
                      status: RungStatus = .ahead) -> LadderRung {
        LadderRung(weekIndex: weekIndex,
                   weekStartString: Self.weekKeys[weekIndex],
                   target: GoalTarget(targetWeightLbs: pounds, targetReps: reps),
                   status: status)
    }

    private func ladder(_ rungs: [LadderRung]) -> Ladder {
        Ladder(goalID: Self.goalID, rungs: rungs, derivedAt: Self.derivedAt)
    }

    private func proposal(current: Ladder, proposed: Ladder) -> LadderProposal {
        LadderProposal(goalID: Self.goalID, current: current, proposed: proposed,
                       changed: LadderProposalMath.changedRungs(current: current,
                                                                proposed: proposed),
                       derivedAt: Self.derivedAt)
    }

    /// A conformer that overrides NOTHING optional — so what it answers for
    /// `reLadderProposal` is the protocol's own default and not an opinion.
    private struct SilentRepository: BlockGoalRepository {
        func activeGoal() async -> BlockGoal? { nil }
        func ladder(goalID: UUID) async -> Ladder? { nil }
        func page(goalID: UUID) async -> LadderPageModel? { nil }
        @discardableResult func save(_ goal: BlockGoal) async -> Bool { true }
        func reLadder(goalID: UUID) async -> Ladder? { nil }
        @discardableResult
        func materialiseRung(goalID: UUID, weekStart: String) async -> WeeklyGoal? { nil }
    }

    // MARK: - 1: an empty diff is an ABSENCE

    /// "No changed rung" is the common case and it must be nil, not a card
    /// reading "Coach proposes: nothing" (the value's own doc comment).
    ///
    /// Asserted against the PROTOCOL DEFAULT — a repository with no opinion is
    /// not forced to invent one — and against the maths, which is what the
    /// live repository's nil-guard reads.
    func testAProposalWithNothingToProposeIsNil() async {
        let repository = SilentRepository()
        let answer = await repository.reLadderProposal(goalID: Self.goalID)
        XCTAssertNil(answer)

        let standing = ladder([rung(0, 190), rung(1, 195), rung(2, 200)])
        // Same targets, DIFFERENT statuses: a re-stamped status is not a
        // proposal, and this is the case a whole-rung diff gets wrong.
        let restamped = ladder([rung(0, 190, status: .met),
                                rung(1, 195, status: .met),
                                rung(2, 200, status: .current)])
        XCTAssertTrue(LadderProposalMath.changedRungs(current: standing,
                                                      proposed: restamped).isEmpty)
    }

    // MARK: - 2: the diff is ordered, and only the moved rungs are in it

    func testChangedIsOrderedByWeekIndexAndOnlyHoldsMovedTargets() {
        let standing = ladder([rung(0, 190), rung(1, 195), rung(2, 200),
                               rung(3, 205), rung(4, 210)])
        // Out of order on purpose, and rung 1 is untouched.
        let proposed = ladder([rung(4, 230), rung(0, 190), rung(3, 220),
                               rung(2, 215), rung(1, 195)])

        let changed = LadderProposalMath.changedRungs(current: standing,
                                                      proposed: proposed)
        XCTAssertEqual(changed.map(\.weekIndex), [2, 3, 4])
        XCTAssertEqual(changed.map { $0.target.targetWeightLbs }, [215, 220, 230])
    }

    // MARK: - 3: one changed rung reads as the change

    func testSentenceForOneChangedRung() {
        let standing = ladder([rung(0, 190), rung(1, 195), rung(2, 200), rung(3, 205)])
        let proposed = ladder([rung(0, 190), rung(1, 195), rung(2, 200), rung(3, 215)])

        XCTAssertEqual(
            LadderProposalMath.sentence(proposal(current: standing, proposed: proposed),
                                        unit: .lbs),
            "Week 4 becomes 3 × 5 at 215 lbs.")
    }

    // MARK: - 4: more than one reads as the span plus the nearest change

    func testSentenceForThreeChangedRungsNamesTheSpanAndTheNearestOne() {
        let standing = ladder([rung(0, 190), rung(1, 195), rung(2, 200),
                               rung(3, 205), rung(4, 210), rung(5, 175),
                               rung(6, 220), rung(7, 225)])
        var rungs = standing.rungs
        rungs[3] = rung(3, 215)
        rungs[5] = rung(5, 185)
        rungs[7] = rung(7, 235)
        let proposed = ladder(rungs)

        let value = proposal(current: standing, proposed: proposed)
        XCTAssertEqual(value.changed.count, 3)
        XCTAssertEqual(
            LadderProposalMath.sentence(value, unit: .lbs),
            "Weeks 4 to 8 move — the next is 3 × 5 at 215 lbs.")
    }

    // MARK: - 5: a kilo athlete reads kilos

    /// The Units doctrine. A frozen "215 lbs" shown to a kilo athlete is the
    /// bug this test exists for: 215 lb is 98 kg to the nearest whole unit
    /// (`Units.wholeNumber`), and the label comes off `WeightUnit` rather than
    /// out of a string literal.
    func testSentenceRendersTheAthletesOwnUnit() {
        let standing = ladder([rung(0, 190), rung(1, 195), rung(2, 200), rung(3, 205)])
        let proposed = ladder([rung(0, 190), rung(1, 195), rung(2, 200), rung(3, 215)])
        let value = proposal(current: standing, proposed: proposed)

        XCTAssertEqual(LadderProposalMath.sentence(value, unit: .kg),
                       "Week 4 becomes 3 × 5 at 98 kg.")
        XCTAssertFalse(LadderProposalMath.sentence(value, unit: .kg).contains("lbs"))
    }

    // MARK: - The catalog's world

    /// `ladder-reladder-proposal` (plan task S11) renders this. A frame whose
    /// fixture drifted out of agreement with its own ladder is a frame that
    /// proves nothing, so the stub's proposal is asserted against the stub's
    /// ladder here — the `testTheStubIsHermeticAndConsistent` precedent.
    func testTheStubsProposalAgreesWithTheStubsLadder() {
        let fixture = StubBlockGoalRepository.fixtureProposal
        XCTAssertEqual(fixture.goalID, StubBlockGoalRepository.fixtureGoalID)
        XCTAssertEqual(fixture.current, StubBlockGoalRepository.fixtureLadder)
        XCTAssertEqual(fixture.changed,
                       LadderProposalMath.changedRungs(current: fixture.current,
                                                       proposed: fixture.proposed))
        XCTAssertFalse(fixture.changed.isEmpty)
        XCTAssertEqual(LadderProposalMath.sentence(fixture, unit: .lbs),
                       "Weeks 4 to 8 move — the next is 3 × 5 at 215 lbs.")
    }
}
