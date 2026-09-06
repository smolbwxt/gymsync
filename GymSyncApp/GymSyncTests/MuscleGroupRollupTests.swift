import XCTest
@testable import GymSync

/// `MuscleGroup` is the arithmetic under the weekly goal strip's chips
/// (plan: `docs/superpowers/plans/2026-09-06-home-v3-production-plan.md`,
/// task 0.1). Its failure mode is QUIET — a muscle string that stops
/// mapping just makes a chip smaller, and a secondary credited twice makes
/// one bigger, neither of which looks like a bug on screen. So these tests
/// pin the table, the three worked examples the plan names, and the cap.
final class MuscleGroupRollupTests: XCTestCase {

    /// Every muscle string the seeded catalog can hold, and the group it
    /// must roll up into. 21 mapped + `neck`, which maps to nothing. If a
    /// migration adds a 23rd string, this list is where it gets a home.
    private static let table: [String: MuscleGroup?] = [
        "chest": .chest,
        "upper_chest": .chest,
        "back": .back,
        "lats": .back,
        "lower_back": .back,
        "traps": .back,
        "shoulders": .shoulders,
        "front_delts": .shoulders,
        "rear_delts": .shoulders,
        "quads": .legs,
        "hamstrings": .legs,
        "glutes": .legs,
        "calves": .legs,
        "adductors": .legs,
        "abductors": .legs,
        "hip_flexors": .legs,
        "biceps": .arms,
        "triceps": .arms,
        "forearms": .arms,
        "core": .core,
        "obliques": .core,
        "neck": Optional<MuscleGroup>.none,
    ]

    // MARK: - The table

    func testSixGroups() {
        XCTAssertEqual(MuscleGroup.allCases.count, 6)
        XCTAssertEqual(MuscleGroup.allCases.map(\.rawValue),
                       ["chest", "back", "shoulders", "legs", "arms", "core"])
    }

    func testEveryCatalogMuscleStringMapsAsTheTableSays() {
        XCTAssertEqual(Self.table.count, 22, "the catalog's vocabulary is 22 strings")
        for (muscle, expected) in Self.table {
            XCTAssertEqual(MuscleGroup.group(muscle), expected,
                           "\(muscle) rolled up to the wrong group")
        }
    }

    func testNeckBelongsToNoGroup() {
        XCTAssertNil(MuscleGroup.group("neck"))
        XCTAssertTrue(MuscleGroup.credit(primary: "neck", secondaries: []).isEmpty,
                      "a neck-primary set credits nothing")
    }

    func testUnknownStringCreditsNothingAndIsNotAnError() {
        XCTAssertNil(MuscleGroup.group("gizzard"))
        let credit = MuscleGroup.credit(primary: "gizzard", secondaries: ["gizzard", "spleen"])
        XCTAssertTrue(credit.isEmpty)
    }

    /// The packs are hand-authored JSON with no case constraint on the
    /// column, so the lookup lowercases rather than trusting the seed.
    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(MuscleGroup.group("CHEST"), .chest)
        XCTAssertEqual(MuscleGroup.group("Upper_Chest"), .chest)
    }

    // MARK: - The three worked examples from the plan

    /// Bench Press: `chest` primary, `['triceps','front_delts']` secondary —
    /// two groups after rollup, so 0.5 each (the cap, not the split).
    func testBenchPress() {
        let credit = MuscleGroup.credit(primary: "chest",
                                        secondaries: ["triceps", "front_delts"])
        XCTAssertEqual(credit.count, 3)
        XCTAssertEqual(credit[.chest], 1.0)
        XCTAssertEqual(credit[.arms], 0.5)
        XCTAssertEqual(credit[.shoulders], 0.5)
    }

    /// Back Squat: `quads` primary, `['glutes','hamstrings','core']` —
    /// glutes and hamstrings roll up into `legs`, which is the primary's own
    /// group and therefore dropped. One survivor, so 0.5.
    func testBackSquatDoesNotPayItsOwnGroupTwice() {
        let credit = MuscleGroup.credit(primary: "quads",
                                        secondaries: ["glutes", "hamstrings", "core"])
        XCTAssertEqual(credit.count, 2)
        XCTAssertEqual(credit[.legs], 1.0, "legs is credited once, as the primary")
        XCTAssertEqual(credit[.core], 0.5)
    }

    /// Alternating Renegade Row, a real catalog row: `back` primary with
    /// five secondaries that collapse to three groups (`lats` is `back`, the
    /// primary's own; `biceps` and `triceps` are both `arms`).
    func testRenegadeRowCollapsesFiveSecondariesToThreeGroups() {
        let credit = MuscleGroup.credit(
            primary: "back",
            secondaries: ["core", "biceps", "chest", "lats", "triceps"])
        XCTAssertEqual(credit.count, 4)
        XCTAssertEqual(credit[.back], 1.0)
        XCTAssertEqual(credit[.core] ?? 0, 1.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(credit[.arms] ?? 0, 1.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(credit[.chest] ?? 0, 1.0 / 3.0, accuracy: 1e-12)
    }

    // MARK: - The cap

    func testSecondaryWeightsForEachFanoutSize() {
        // |S| = 1 → 0.5 (the cap wins over 1/1)
        XCTAssertEqual(MuscleGroup.credit(primary: "chest", secondaries: ["biceps"])[.arms], 0.5)
        // |S| = 2 → 0.5 each (the cap and the split agree)
        let two = MuscleGroup.credit(primary: "chest", secondaries: ["biceps", "quads"])
        XCTAssertEqual(two[.arms], 0.5)
        XCTAssertEqual(two[.legs], 0.5)
        // |S| = 4 → 0.25 each
        let four = MuscleGroup.credit(primary: "chest",
                                      secondaries: ["biceps", "quads", "core", "traps"])
        for group in [MuscleGroup.arms, .legs, .core, .back] {
            XCTAssertEqual(four[group] ?? 0, 0.25, accuracy: 1e-12)
        }
    }

    /// The owner's cap, over every primary and every window of secondaries
    /// the catalog vocabulary can produce: Σ(secondary credit) ≤ 1.0, and
    /// the primary's own group is never credited more than 1.0.
    func testSecondaryCreditNeverExceedsOneForAnyCatalogRow() {
        let vocabulary = Self.table.keys.sorted()
        for primary in vocabulary {
            let primaryGroup = MuscleGroup.group(primary)
            for start in vocabulary.indices {
                for length in 0...(vocabulary.count - start) {
                    let secondaries = Array(vocabulary[start..<(start + length)])
                    let credit = MuscleGroup.credit(primary: primary, secondaries: secondaries)

                    let secondaryTotal = credit
                        .filter { $0.key != primaryGroup }
                        .values
                        .reduce(0, +)
                    XCTAssertLessThanOrEqual(
                        secondaryTotal, 1.0 + 1e-9,
                        "primary \(primary), secondaries \(secondaries): secondary credit \(secondaryTotal)")

                    if let primaryGroup = primaryGroup {
                        XCTAssertEqual(credit[primaryGroup], 1.0,
                                       "primary \(primary) must always be credited exactly 1.0")
                    }
                }
            }
        }
    }

    /// Same inputs, same output — the strip re-renders on every refresh and
    /// a `Set`-ordered split that moved between runs would reshuffle chips.
    func testCreditIsOrderIndependent() {
        let a = MuscleGroup.credit(primary: "back",
                                   secondaries: ["core", "biceps", "chest", "lats", "triceps"])
        let b = MuscleGroup.credit(primary: "back",
                                   secondaries: ["triceps", "lats", "chest", "biceps", "core"])
        XCTAssertEqual(a, b)
    }
}
