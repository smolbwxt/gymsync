import XCTest
@testable import GymSync

/// Freestyle's own pace law — plan task S10 (spec §3.3, owner decision 4).
///
/// The rail draws the crew's spread; `FreestylePace.standing(sets:for:)` is
/// what decides which of the three suggestions a lifter sees, and
/// `accessorySuggestion(from:startedIDs:)` is what stops Coach's accessory
/// from ever naming a movement that is not actually on the plan.
final class FreestylePaceTests: XCTestCase {

    private let alex = UUID()
    private let dana = UUID()
    private let sam = UUID()
    private let lee = UUID()

    private func lifter(_ id: UUID, _ done: Int) -> FreestylePace.Lifter {
        FreestylePace.Lifter(userID: id, setsDone: done)
    }

    // MARK: - standing(sets:for:)

    /// Two or more sets clear of the SLOWEST other lifter is ahead — the
    /// crew's tail, not its average, is what a stretch is answering.
    func testTwoSetsClearOfTheSlowestIsAhead() {
        let sets = [lifter(alex, 14), lifter(dana, 12), lifter(sam, 12), lifter(lee, 12)]
        XCTAssertEqual(FreestylePace.standing(sets: sets, for: alex), .ahead(by: 2))
    }

    /// Two or more sets short of the FASTEST other lifter is behind.
    func testTwoSetsShortOfTheFastestIsBehind() {
        let sets = [lifter(alex, 10), lifter(dana, 12), lifter(sam, 12), lifter(lee, 12)]
        XCTAssertEqual(FreestylePace.standing(sets: sets, for: alex), .behind(by: 2))
    }

    /// One set either way is still the crew the style is named for.
    func testOneSetEitherWayIsLevel() {
        let ahead = [lifter(alex, 13), lifter(dana, 12), lifter(sam, 12)]
        XCTAssertEqual(FreestylePace.standing(sets: ahead, for: alex), .level)
        let behind = [lifter(alex, 11), lifter(dana, 12), lifter(sam, 12)]
        XCTAssertEqual(FreestylePace.standing(sets: behind, for: alex), .level)
    }

    /// A solo rotation has nobody to be ahead or behind of.
    func testASoloRotationIsAlwaysLevel() {
        XCTAssertEqual(FreestylePace.standing(sets: [lifter(alex, 40)], for: alex), .level)
    }

    /// A lifter this crew's sets don't name answers level — the honest
    /// fallback, never a crash on a missing key.
    func testAnUnknownLifterIsLevel() {
        let sets = [lifter(dana, 12), lifter(sam, 8)]
        XCTAssertEqual(FreestylePace.standing(sets: sets, for: alex), .level)
    }

    /// The exact fixture the frame carries: 14 against a slowest of 11 is
    /// three sets up, not two — the brief's own quoted sentence is an
    /// example at exactly two, and `RoundCopy` is tested separately for it.
    func testTheFrameFixtureIsThreeSetsUp() {
        let sets = LiveFixtures.freestyleRail.lifters.map {
            FreestylePace.Lifter(userID: $0.id, setsDone: $0.setsDone)
        }
        XCTAssertEqual(FreestylePace.standing(sets: sets, for: LiveFixtures.alexID), .ahead(by: 3))
    }

    // MARK: - accessorySuggestion(from:startedIDs:)

    private func candidate(_ id: UUID, _ name: String, _ category: String) -> FreestylePace.AccessoryCandidate {
        FreestylePace.AccessoryCandidate(id: id, name: name, category: category, prescription: "3 × 12")
    }

    private let squat = UUID()
    private let facePulls = UUID()
    private let curls = UUID()

    /// The FIRST isolation row not yet started — never a compound one, and
    /// never one the lifter has already begun.
    func testTheFirstUnstartedIsolationRowIsSuggested() {
        let candidates = [candidate(squat, "Back squat", "compound"),
                          candidate(facePulls, "Face pulls", "isolation"),
                          candidate(curls, "Curls", "isolation")]
        let suggestion = FreestylePace.accessorySuggestion(from: candidates, startedIDs: [])
        XCTAssertEqual(suggestion?.id, facePulls)
    }

    func testAnAlreadyStartedIsolationRowIsSkipped() {
        let candidates = [candidate(facePulls, "Face pulls", "isolation"),
                          candidate(curls, "Curls", "isolation")]
        let suggestion = FreestylePace.accessorySuggestion(from: candidates, startedIDs: [facePulls])
        XCTAssertEqual(suggestion?.id, curls)
    }

    /// A routine with no isolation work has nothing honest to suggest.
    func testNoIsolationRowsIsNoSuggestion() {
        let candidates = [candidate(squat, "Back squat", "compound")]
        XCTAssertNil(FreestylePace.accessorySuggestion(from: candidates, startedIDs: []))
    }

    func testEveryIsolationRowStartedIsNoSuggestion() {
        let candidates = [candidate(facePulls, "Face pulls", "isolation")]
        XCTAssertNil(FreestylePace.accessorySuggestion(from: candidates, startedIDs: [facePulls]))
    }

    /// Category is read case-insensitively — the generator and hand-entered
    /// rows do not always agree on casing.
    func testCategoryMatchingIsCaseInsensitive() {
        let candidates = [candidate(facePulls, "Face pulls", "ISOLATION")]
        XCTAssertEqual(FreestylePace.accessorySuggestion(from: candidates, startedIDs: [])?.id, facePulls)
    }

    // MARK: - The frame's world (frame 141)

    func testTheFreestyleWorld() {
        let world = LiveFixtures.freestyle
        XCTAssertEqual(world.kicker, "PUSH CREW · FREESTYLE")
        XCTAssertEqual(world.rail.lifters.count, 4)
        XCTAssertEqual(world.rail.totalSets, 18)
        XCTAssertEqual(world.standing, .ahead(by: 3))
        XCTAssertNotNil(world.stretchSuggestion)
        XCTAssertNotNil(world.accessorySuggestion)
        XCTAssertNil(world.behindLine)
    }

    /// The rail's own numbers agree with `standing` — a frame that showed
    /// suggestions the numbers did not support would teach the wrong thing
    /// about when Coach speaks up.
    func testTheWorldsStandingAgreesWithItsRail() {
        let sets = LiveFixtures.freestyle.rail.lifters.map {
            FreestylePace.Lifter(userID: $0.id, setsDone: $0.setsDone)
        }
        let you = LiveFixtures.freestyle.rail.lifters.first(where: \.isYou)!
        XCTAssertEqual(FreestylePace.standing(sets: sets, for: you.id), LiveFixtures.freestyle.standing)
    }
}
