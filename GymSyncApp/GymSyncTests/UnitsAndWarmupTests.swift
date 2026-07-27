import XCTest
@testable import GymSync

/// Units + warm-up ramp. Both are pure (the StatMath/PlateMath idiom).
///
/// The property these tests protect above all: STORED WEIGHTS ARE POUNDS.
/// A conversion bug here doesn't show up as a wrong label — it shows up as
/// a lifter's logged 100 kg squat being recorded as 100 lb, silently, with
/// PRs and program baselines built on top of it.
final class UnitsAndWarmupTests: XCTestCase {

    private func double(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }

    // MARK: - Conversion

    func testPoundsAreIdentityInPounds() {
        XCTAssertEqual(double(Units.fromPounds(225, to: .lbs)), 225, accuracy: 0.0001)
        XCTAssertEqual(double(Units.toPounds(225, from: .lbs)), 225, accuracy: 0.0001)
    }

    func testKilogramConversionBothWays() {
        // 100 kg is the canonical check: 220.46 lb.
        XCTAssertEqual(double(Units.toPounds(100, from: .kg)), 220.462, accuracy: 0.01)
        XCTAssertEqual(double(Units.fromPounds(220.462, to: .kg)), 100, accuracy: 0.01)
    }

    func testRoundTripSurvives() {
        for pounds: Decimal in [45, 135, 225, 315, 405] {
            let kg = Units.fromPounds(pounds, to: .kg)
            let back = Units.toPounds(kg, from: .kg)
            XCTAssertEqual(double(back), double(pounds), accuracy: 0.001,
                           "\(pounds) lb did not survive a kg round trip")
        }
    }

    // MARK: - Loadable rounding

    /// PLATES GO ON IN PAIRS, so the smallest step is twice the smallest
    /// plate — 5 lb, not 2.5. Getting this wrong prints 227.5 lb, which
    /// needs a 1.25 lb pair no gym stocks.
    func testLoadableIncrementIsTwiceTheSmallestPlate() {
        XCTAssertEqual(double(Units.loadableIncrement(plates: WeightUnit.lbs.standardPlates, unit: .lbs)),
                       5, accuracy: 0.001)
        XCTAssertEqual(double(Units.loadableIncrement(plates: WeightUnit.kg.standardPlates, unit: .kg)),
                       2.5, accuracy: 0.001)
        // A gym without 2.5s genuinely moves in 10 lb steps.
        XCTAssertEqual(double(Units.loadableIncrement(plates: [45, 35, 25, 10, 5], unit: .lbs)),
                       10, accuracy: 0.001)
    }

    func testRoundsToLoadableIncrement() {
        // 225 lb is 102.058 kg — nobody can load that; 2.5 kg granularity.
        let kg = Units.fromPounds(225, to: .kg)
        XCTAssertEqual(double(Units.roundToIncrement(kg, unit: .kg)), 102.5, accuracy: 0.001)
        XCTAssertEqual(double(Units.roundToIncrement(226, unit: .lbs)), 225, accuracy: 0.001)
    }

    /// The real contract the user asked for: whatever we print must be
    /// buildable. Verified against PlateMath itself, not against arithmetic
    /// — PlateMath is the single source of truth for what can be racked.
    func testNearestLoadableIsAlwaysActuallyBuildable() {
        let cases: [(unit: WeightUnit, bar: Decimal, plates: [Decimal])] = [
            (.lbs, 45, WeightUnit.lbs.standardPlates),
            (.kg, 20, WeightUnit.kg.standardPlates),
            (.lbs, 45, [45, 35, 25, 10, 5]),        // no 2.5s
            (.lbs, 35, [45, 25, 10]),               // sparse gym, light bar
        ]
        for c in cases {
            for target: Decimal in [47, 96.3, 137.9, 225.7, 314.2] {
                let snapped = Units.nearestLoadable(target, barWeight: c.bar,
                                                    plates: c.plates, unit: c.unit)
                let achieved = PlateMath.stack(for: snapped, barWeight: c.bar,
                                               plates: c.plates).achievedWeight
                XCTAssertEqual(double(achieved), double(snapped), accuracy: 0.001,
                               "\(c.unit) target \(target) snapped to \(snapped), which cannot be loaded")
                XCTAssertGreaterThanOrEqual(double(snapped), double(c.bar))
            }
        }
    }

    /// Switching units must land on a real number: 225 lb -> 102.5 kg,
    /// which is a 20 kg bar plus 25+15+1.25 per side.
    func testUnitSwitchLandsOnALoadableWeight() {
        let text = Units.formatLoadable(pounds: 225, unit: .kg,
                                        barPounds: Units.toPounds(20, from: .kg),
                                        plates: WeightUnit.kg.standardPlates)
        XCTAssertEqual(text, "102.5 kg")
    }

    /// With no 2.5 lb plates, a converted weight must fall back to a 10 lb
    /// grid rather than printing something that gym can't build.
    func testSparseInventoryWidensTheGrid() {
        let plates: [Decimal] = [45, 35, 25, 10, 5]
        let snapped = Units.nearestLoadable(227.5, barWeight: 45, plates: plates, unit: .lbs)
        let achieved = PlateMath.stack(for: snapped, barWeight: 45, plates: plates).achievedWeight
        XCTAssertEqual(double(achieved), double(snapped), accuracy: 0.001)
        XCTAssertNotEqual(double(snapped), 227.5, "227.5 needs a 1.25 lb pair this gym lacks")
    }

    func testFormatTrimsAndLabels() {
        XCTAssertEqual(Units.format(pounds: 225, unit: .lbs), "225 lbs")
        XCTAssertEqual(Units.format(pounds: 225, unit: .kg), "102.5 kg")
        XCTAssertEqual(Units.format(pounds: 45, unit: .lbs, includeUnit: false), "45")
    }

    /// Units sweep: the exact (`rounded: false`) path caps at 2 decimals —
    /// a historical 100 lb set viewed in kg is 45.359237…, and "45.36" is
    /// the honest display — while a value TYPED in kg round-trips exactly
    /// (kg × factor ÷ factor), so entries never grow spurious decimals.
    func testExactFormatCapsDecimals() {
        XCTAssertEqual(Units.format(pounds: 100, unit: .kg, rounded: false), "45.36 kg")
        let storedFromKgEntry = Units.toPounds(100, from: .kg)
        XCTAssertEqual(Units.format(pounds: storedFromKgEntry, unit: .kg, rounded: false), "100 kg")
    }

    /// The Double overload backing volume aggregates (Σ reps×weight
    /// accumulates in Double at the recap/leaderboard call sites).
    func testDoubleVolumeConversion() {
        let kg = Units.fromPounds(Double(2204.6226218), to: .kg)
        XCTAssertEqual(kg, 1000, accuracy: 0.001)
        XCTAssertEqual(Units.fromPounds(Double(500), to: .lbs), 500, accuracy: 0.0001)
    }

    /// Est-1RM tiles show whole numbers in the user's unit.
    func testWholeNumberDisplay() {
        XCTAssertEqual(Units.wholeNumber(pounds: 231.66, unit: .lbs), "232")
        XCTAssertEqual(Units.wholeNumber(pounds: Units.toPounds(100, from: .kg), unit: .kg), "100")
    }

    // MARK: - Entry parsing

    func testParseStoresPounds() {
        // Typing 100 while in kg must STORE 220.46 lb, not 100.
        let stored = Units.parseToPounds("100", unit: .kg)
        XCTAssertEqual(double(stored ?? 0), 220.462, accuracy: 0.01)
        XCTAssertEqual(double(Units.parseToPounds("225", unit: .lbs) ?? 0), 225, accuracy: 0.001)
    }

    /// A kg-using locale very often types a comma decimal; silently
    /// dropping that entry is a bad first impression.
    func testParseAcceptsCommaDecimal() {
        let comma = Units.parseToPounds("102,5", unit: .kg)
        let period = Units.parseToPounds("102.5", unit: .kg)
        XCTAssertNotNil(comma)
        XCTAssertEqual(double(comma ?? 0), double(period ?? 1), accuracy: 0.001)
    }

    func testParseRejectsGarbageAndNegatives() {
        XCTAssertNil(Units.parseToPounds("", unit: .lbs))
        XCTAssertNil(Units.parseToPounds("abc", unit: .lbs))
        XCTAssertNil(Units.parseToPounds("-5", unit: .lbs))
    }

    // MARK: - Warm-up ramp

    func testRampStartsAtTheBarAndClimbsToBelowWorking() {
        let steps = WarmupMath.ramp(workingPounds: 225, barPounds: 45, unit: .lbs)
        XCTAssertGreaterThan(steps.count, 1)
        XCTAssertTrue(steps.first?.isBar ?? false, "a ramp always opens with the empty bar")
        XCTAssertEqual(double(steps.first?.pounds ?? 0), 45, accuracy: 0.001)
        for step in steps {
            XCTAssertLessThan(double(step.pounds), 225, "a warm-up must be lighter than the work")
        }
        // Ascending.
        let loads = steps.map { double($0.pounds) }
        XCTAssertEqual(loads, loads.sorted(), "ramp must climb")
    }

    /// Every rung must be rackable with the lifter's own plates — checked
    /// against PlateMath, including a gym missing its 2.5s.
    func testEveryRungIsLoadable() {
        let cases: [(unit: WeightUnit, bar: Decimal, plates: [Decimal])] = [
            (.lbs, 45, WeightUnit.lbs.standardPlates),
            (.kg, 20, WeightUnit.kg.standardPlates),
            (.lbs, 45, [45, 35, 25, 10, 5]),
        ]
        for c in cases {
            let barPounds = Units.toPounds(c.bar, from: c.unit)
            let steps = WarmupMath.ramp(workingPounds: 225, barPounds: barPounds,
                                        unit: c.unit, plates: c.plates)
            for step in steps where !step.isBar {
                let inUnit = Units.fromPounds(step.pounds, to: c.unit)
                let achieved = PlateMath.stack(for: inUnit, barWeight: c.bar,
                                               plates: c.plates).achievedWeight
                XCTAssertEqual(double(achieved), double(inUnit), accuracy: 0.001,
                               "\(c.unit) rung \(inUnit) is not loadable with \(c.plates)")
            }
        }
    }

    func testNoRampWhenWorkingWeightIsAtOrBelowTheBar() {
        XCTAssertTrue(WarmupMath.ramp(workingPounds: 45, barPounds: 45, unit: .lbs).isEmpty)
        XCTAssertTrue(WarmupMath.ramp(workingPounds: 30, barPounds: 45, unit: .lbs).isEmpty)
    }

    /// The lifter must never see the same load twice, at any weight.
    func testRampNeverRepeatsALoad() {
        for working: Decimal in [55, 95, 135, 225, 405] {
            let steps = WarmupMath.ramp(workingPounds: working, barPounds: 45, unit: .lbs)
            let loads = steps.map { double($0.pounds) }
            XCTAssertEqual(Set(loads).count, loads.count,
                           "duplicate loads in the \(working) lb ramp")
        }
    }

    /// A working weight barely above the bar collapses to a SHORT ramp:
    /// most rungs land at or below the bar and are dropped, because a
    /// "warm-up" you can't load — or that IS the bar — isn't a step.
    ///
    /// (An earlier version of this test asserted a 95 lb set produces fewer
    /// than 5 rungs. It doesn't, and shouldn't: on a 5 lb grid from a 45 lb
    /// bar, 50/65/80/90 are four legitimately distinct rungs. That assertion
    /// was inventing a requirement rather than testing one.)
    func testVeryLightWorkingWeightYieldsAShortRamp() {
        let steps = WarmupMath.ramp(workingPounds: 55, barPounds: 45, unit: .lbs)
        XCTAssertTrue(steps.first?.isBar ?? false)
        XCTAssertLessThanOrEqual(steps.count, 3,
                                 "55 lb is one plate-pair above the bar — there is almost nothing to ramp")
        for step in steps {
            XCTAssertLessThan(double(step.pounds), 55)
            XCTAssertGreaterThanOrEqual(double(step.pounds), 45)
        }
    }

    func testKilogramRampIsLoadableInKilograms() {
        let working = Units.toPounds(100, from: .kg)
        let bar = Units.toPounds(20, from: .kg)
        let steps = WarmupMath.ramp(workingPounds: working, barPounds: bar, unit: .kg)
        XCTAssertTrue(steps.first?.isBar ?? false)
        XCTAssertEqual(double(Units.fromPounds(steps.first?.pounds ?? 0, to: .kg)), 20, accuracy: 0.01)
        for step in steps {
            XCTAssertLessThan(double(step.pounds), double(working))
        }
    }
}
