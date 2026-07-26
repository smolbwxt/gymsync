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

    func testRoundsToLoadableIncrement() {
        // 225 lb is 102.058 kg — nobody can load that. 1.25 kg granularity.
        let kg = Units.fromPounds(225, to: .kg)
        XCTAssertEqual(double(Units.roundToIncrement(kg, unit: .kg)), 102.5, accuracy: 0.001)
        // lbs snap to 2.5.
        XCTAssertEqual(double(Units.roundToIncrement(226, unit: .lbs)), 225, accuracy: 0.001)
        XCTAssertEqual(double(Units.roundToIncrement(224, unit: .lbs)), 225, accuracy: 0.001)
    }

    func testFormatTrimsAndLabels() {
        XCTAssertEqual(Units.format(pounds: 225, unit: .lbs), "225 lbs")
        XCTAssertEqual(Units.format(pounds: 225, unit: .kg), "102.5 kg")
        XCTAssertEqual(Units.format(pounds: 45, unit: .lbs, includeUnit: false), "45")
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

    func testEveryRungIsLoadable() {
        for unit in WeightUnit.allCases {
            let steps = WarmupMath.ramp(workingPounds: 225, barPounds: 45, unit: unit)
            for step in steps where !step.isBar {
                let inUnit = Units.fromPounds(step.pounds, to: unit)
                let snapped = Units.roundToIncrement(inUnit, unit: unit)
                XCTAssertEqual(double(inUnit), double(snapped), accuracy: 0.001,
                               "\(unit): \(step.pounds) lb is not loadable in this unit")
            }
        }
    }

    func testNoRampWhenWorkingWeightIsAtOrBelowTheBar() {
        XCTAssertTrue(WarmupMath.ramp(workingPounds: 45, barPounds: 45, unit: .lbs).isEmpty)
        XCTAssertTrue(WarmupMath.ramp(workingPounds: 30, barPounds: 45, unit: .lbs).isEmpty)
    }

    /// A light working set gets a SHORT ramp — rungs collapse onto the same
    /// loadable weight and near-duplicates are dropped, so the lifter never
    /// sees the same load twice.
    func testLightWorkingWeightCollapsesDuplicateRungs() {
        let steps = WarmupMath.ramp(workingPounds: 95, barPounds: 45, unit: .lbs)
        let loads = steps.map { double($0.pounds) }
        XCTAssertEqual(Set(loads).count, loads.count, "duplicate loads in the ramp")
        XCTAssertLessThan(steps.count, 5, "a 95 lb working set doesn't need a full ladder")
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
