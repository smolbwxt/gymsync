import XCTest
@testable import GymSync

/// Per-muscle weekly volume accounting — the corpus audit's confirmed
/// defect made into a contract: `secondaryMuscles` is READ, indirect
/// volume counts at half a set, and the weekly band is enforced against
/// what a week actually delivers to each muscle, not per slot.
final class VolumeAccountingTests: XCTestCase {

    private func ex(_ rank: Int, _ name: String, _ muscle: String,
                    secondaries: [String] = [],
                    cat: String = "isolation") -> ProgramGenerator.CatalogExercise {
        ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", rank))!,
            name: name, primaryMuscle: muscle, secondaryMuscles: secondaries,
            category: cat, equipment: "barbell", movementPattern: "isolation",
            rank: rank)
    }

    private func entry(_ catalogEx: ProgramGenerator.CatalogExercise,
                       sets: Int, isMain: Bool = false) -> ProgramGenerator.Exercise {
        ProgramGenerator.Exercise(
            exerciseID: catalogEx.id, name: catalogEx.name, sets: sets,
            repsLow: 8, repsHigh: 12, restSeconds: 90,
            percentOfMax: nil, isMain: isMain)
    }

    func testSecondariesCountAtHalfASet() {
        let bench = ex(1, "Bench Press", "chest",
                       secondaries: ["triceps", "shoulders"], cat: "compound")
        let days = [ProgramGenerator.Day(name: "Push",
                                         exercises: [entry(bench, sets: 4, isMain: true)])]
        let tally = ProgramGenerator.weeklyMuscleSets(days: days, catalog: [bench])
        XCTAssertEqual(tally["chest"], 4.0)
        XCTAssertEqual(tally["triceps"], 2.0, "4 sets x 0.5 for a secondary")
        XCTAssertEqual(tally["shoulders"], 2.0)
    }

    func testCeilingTrimsAccessoriesNeverMains() {
        let bench = ex(1, "Bench Press", "chest",
                       secondaries: ["triceps"], cat: "compound")
        let pushdown = ex(2, "Pushdown", "triceps")
        let overhead = ex(3, "Overhead Extension", "triceps")
        let catalog = [bench, pushdown, overhead]
        // Triceps: 5x0.5 (bench) + 5 + 5 = 12.5 against a ceiling of 10.
        let days = [ProgramGenerator.Day(name: "Push", exercises: [
            entry(bench, sets: 5, isMain: true),
            entry(pushdown, sets: 5),
            entry(overhead, sets: 5),
        ])]
        let result = ProgramGenerator.balanceWeeklyVolume(
            days: days, catalog: catalog, low: 0, high: 10)
        let tally = ProgramGenerator.weeklyMuscleSets(days: result.days,
                                                     catalog: catalog)
        XCTAssertLessThanOrEqual(tally["triceps"] ?? 0, 10.0)
        XCTAssertEqual(result.trimmed, 3)
        XCTAssertEqual(result.days[0].exercises[0].sets, 5,
                       "the MAIN is never touched — slot logic owns it")
        XCTAssertEqual(result.days[0].exercises[2].sets, 2,
                       "trims come from the LAST accessory first")
    }

    // MARK: - The note has to be true

    func testACeilingItCannotFixIsReportedRatherThanIgnored() {
        // The defect: both loops can exhaust their levers and `break`, and
        // that exit was silent - so a week that broke a ceiling it had no
        // accessory to trim still reported itself "balanced per muscle",
        // because the caller wrote that sentence from the trim/add COUNTS
        // rather than from the outcome.
        //
        // Chest here is over the ceiling and every chest set comes from a
        // MAIN, which balance may never touch. Nothing can be trimmed.
        let bench = ex(1, "Bench", "chest")
        let days = [ProgramGenerator.Day(name: "Push", exercises: [
            entry(bench, sets: 15, isMain: true),
        ])]
        let result = ProgramGenerator.balanceWeeklyVolume(
            days: days, catalog: [bench], low: 0, high: 10)
        XCTAssertEqual(result.trimmed, 0, "there was nothing it could trim")
        XCTAssertTrue(result.unresolvedHigh.contains("chest"),
                      "and it must say so instead of exiting quietly")
    }

    func testAFloorItCannotReachIsReportedToo() {
        // Biceps is trained as a primary but its only accessory already
        // sits at the per-exercise cap, so the floor cannot be met.
        let curl = ex(1, "Curl", "biceps")
        let days = [ProgramGenerator.Day(name: "Arms",
                                         exercises: [entry(curl, sets: 5)])]
        let result = ProgramGenerator.balanceWeeklyVolume(
            days: days, catalog: [curl], low: 12, high: 20)
        XCTAssertEqual(result.added, 0)
        XCTAssertTrue(result.unresolvedLow.contains("biceps"))
    }

    func testAGenuinelyBalancedWeekReportsNothingUnresolved() {
        // The guard against crying wolf: if everything fits, both lists
        // must be empty, or every program would carry a false warning.
        let curl = ex(1, "Curl", "biceps")
        let days = [ProgramGenerator.Day(name: "Arms",
                                         exercises: [entry(curl, sets: 8)])]
        let result = ProgramGenerator.balanceWeeklyVolume(
            days: days, catalog: [curl], low: 6, high: 12)
        XCTAssertTrue(result.unresolvedHigh.isEmpty)
        XCTAssertTrue(result.unresolvedLow.isEmpty)
    }

    // MARK: - Direct vs effective

    func testTheCoverageTallyCanAnswerDirectOnly() {
        // A muscle with heavy INDIRECT volume and zero direct work used to
        // pass the orphan gate, because the gate asked the effective tally
        // while the note it printed claimed the dosed muscles "had no
        // direct work this week". The test and the sentence disagreed.
        let row = ex(1, "Row", "back", secondaries: ["biceps"])
        let days = [ProgramGenerator.Day(name: "Pull",
                                         exercises: [entry(row, sets: 9, isMain: true)])]
        let effective = ProgramGenerator.weeklyMuscleSets(days: days, catalog: [row])
        let direct = ProgramGenerator.weeklyMuscleSets(days: days, catalog: [row],
                                                       directOnly: true)
        XCTAssertEqual(effective["biceps"], 4.5, "rows carry biceps indirectly")
        XCTAssertNil(direct["biceps"], "but nothing trains them directly")
        XCTAssertEqual(direct["back"], 9, "the primary is unaffected either way")
    }

    func testDirectOnlyNeverInflatesAnyMuscle() {
        // Counting direct can only ever REMOVE incidental volume, so it can
        // only ever cause a dose to be ADDED - never a trim. That asymmetry
        // is why this was safe to change without re-deciding any number.
        let row = ex(1, "Row", "back", secondaries: ["biceps", "forearms"])
        let days = [ProgramGenerator.Day(name: "Pull",
                                         exercises: [entry(row, sets: 4, isMain: true)])]
        let effective = ProgramGenerator.weeklyMuscleSets(days: days, catalog: [row])
        let direct = ProgramGenerator.weeklyMuscleSets(days: days, catalog: [row],
                                                       directOnly: true)
        for muscle in Set(effective.keys).union(direct.keys) {
            XCTAssertLessThanOrEqual(direct[muscle] ?? 0, effective[muscle] ?? 0,
                                     "direct must never exceed effective")
        }
    }

    func testFloorRaisesPrimaryTrainedMuscleCappedAtFive() {
        let curl = ex(1, "Curl", "biceps")
        let days = [ProgramGenerator.Day(name: "Arms",
                                         exercises: [entry(curl, sets: 2)])]
        let result = ProgramGenerator.balanceWeeklyVolume(
            days: days, catalog: [curl], low: 6, high: 20)
        XCTAssertEqual(result.days[0].exercises[0].sets, 5,
                       "adds stop at the per-exercise cap even under the floor")
        XCTAssertEqual(result.added, 3)
    }

    func testSecondaryOnlyMuscleGetsNoFloor() {
        // Forearms appear only as a secondary: incidental volume is not a
        // training commitment, so the floor must not chase it.
        let curl = ex(1, "Curl", "biceps", secondaries: ["forearms"])
        let days = [ProgramGenerator.Day(name: "Arms",
                                         exercises: [entry(curl, sets: 3)])]
        let result = ProgramGenerator.balanceWeeklyVolume(
            days: days, catalog: [curl], low: 10, high: 20)
        let tally = ProgramGenerator.weeklyMuscleSets(days: result.days,
                                                     catalog: [curl])
        XCTAssertEqual(tally["forearms"], 2.5,
                       "5 sets x 0.5 after biceps' own floor pass — never inflated for forearms' sake")
    }

    func testCardioContributesNoVolume() {
        let bike = ex(1, "Cycling", "quads", cat: "cardio")
        var cardio = entry(bike, sets: 1)
        cardio.cardioZone = 2
        cardio.cardioMinutes = 30
        let days = [ProgramGenerator.Day(name: "Cardio", exercises: [cardio])]
        let tally = ProgramGenerator.weeklyMuscleSets(days: days, catalog: [bike])
        XCTAssertTrue(tally.isEmpty, "zone minutes are not sets")
    }

    // MARK: - Audit 2026-08-25: the reroll gate leak

    /// The shipped variation control must honour the same hard exclusions
    /// the generated program did. Before the audit, `reroll` built its own
    /// equipment-only candidate pool, so the roll button could hand back a
    /// lift the athlete had explicitly excluded — an injury exclusion
    /// silently outranked by a UI affordance.
    func testRerollNeverReturnsAnExcludedExercise() {
        // cat defaults to "isolation" so the `.isolation("back")` slot
        // actually has candidates — a vacuous pool would pass this test
        // for the wrong reason.
        let a = ex(1, "Row A", "back")
        let b = ex(2, "Row B", "back")
        let c = ex(3, "Row C", "back")
        let catalog = [a, b, c]
        var inputs = ProgramGenerator.Inputs(focus: .hypertrophy, daysPerWeek: 3,
                                             durationWeeks: 8, experience: .intermediate)
        inputs.excludedExerciseIDs = [b.id]

        var current = entry(a, sets: 3, isMain: true)
        current.slot = .isolation("back")
        let day = ProgramGenerator.Day(name: "Pull", exercises: [current])

        // Walk the whole pool; b must never appear at any roll depth.
        var seen: Set<UUID> = []
        var cursor = current
        for _ in 0..<5 {
            guard let next = ProgramGenerator.reroll(cursor, in: day, inputs: inputs,
                                                     catalog: catalog,
                                                     alsoExcluding: seen) else { break }
            XCTAssertNotEqual(next.exerciseID, b.id,
                              "reroll handed back an excluded exercise")
            seen.insert(next.exerciseID)
            cursor = next
        }
        XCTAssertFalse(seen.contains(b.id))
        // Non-vacuity: the pool must actually have produced alternates,
        // otherwise the assertion above proves nothing.
        XCTAssertTrue(seen.contains(c.id),
                      "reroll produced no alternates at all — test is vacuous")
    }

    /// Conditioning days pick their three compounds by COVERAGE, not by
    /// template order. A full-body base used to yield squat + hinge +
    /// horizontal push, deleting horizontal pulling from every day of the
    /// block — a conditioning program with no rowing in it.
    func testConditioningFullBodyKeepsAPullPattern() {
        let slots = ProgramGenerator.slots(for: .fullBody, focus: .conditioning)
        let patterns: [String] = slots.compactMap { slot in
            if case .pattern(let name, _) = slot { return name }
            return nil
        }
        XCTAssertTrue(patterns.contains(where: { $0.hasPrefix("pull") }),
                      "conditioning full-body day dropped all pulling: \(patterns)")
        XCTAssertTrue(patterns.contains(where: { $0.hasPrefix("push") }),
                      "conditioning full-body day dropped all pushing: \(patterns)")
        XCTAssertEqual(patterns.count, 3, "the maintenance floor is three compounds")
    }
}
