import XCTest
@testable import GymSync

// Pure-function coverage for `PlateMath` (Models/PlateMath.swift) — no
// network/auth dependency, same "hermetic derivation" idiom as
// `StatDerivationTests` covering `StatMath`.
//
// The master spec's unit-test list names this case explicitly, verbatim:
// "Plate math (target weight + bar weight → plate stack)."
// (`docs/superpowers/specs/2026-06-28-gymsync-design.md:1292`)
final class PlateMathTests: XCTestCase {

    // MARK: - The master spec's named case, verbatim
    //
    // "Plate math (target weight + bar weight → plate stack)" — a target
    // weight and a bar weight go in, a per-side plate stack comes out.
    // 155 lbs on a 45 lb bar needs 55 lbs of plate across both sides (27.5
    // per side); greedy-descending over [45,35,25,10,5,2.5] takes one 45
    // (leaving 10) then one 10 per side — an exact match, no remainder.

    func testPlateMath_targetWeightAndBarWeightProducesStack() {
        let result = PlateMath.stack(for: 155, barWeight: 45)
        XCTAssertEqual(result.platesPerSide, [1, 0, 0, 1, 0, 0])
        XCTAssertEqual(result.achievedWeight, 155)
        XCTAssertNil(result.remainder)
    }

    // MARK: - Exact bar weight (brief-required case)
    // Target equals the bar itself: zero plates either side, no remainder.

    func testStack_exactBarWeightProducesNoPlates() {
        let result = PlateMath.stack(for: 45, barWeight: 45)
        XCTAssertEqual(result.platesPerSide, Array(repeating: 0, count: 6))
        XCTAssertEqual(result.achievedWeight, 45)
        XCTAssertNil(result.remainder)
    }

    // MARK: - Bar + one smallest-plate pair (brief-required case)
    // 45 lb bar + one 2.5 lb plate per side = 50 lbs exactly.

    func testStack_barPlusOneSmallestPlatePairIsExact() {
        let result = PlateMath.stack(for: 50, barWeight: 45)
        XCTAssertEqual(result.platesPerSide, [0, 0, 0, 0, 0, 1])
        XCTAssertEqual(result.achievedWeight, 50)
        XCTAssertNil(result.remainder)
    }

    // MARK: - Remainder case (brief-required case)
    // 47 lbs needs 1 lb per side of plate — below the smallest available
    // plate (2.5) — so it's unreachable: nearest-below is the bare bar,
    // with a 2 lb remainder note.

    func testStack_unreachableRemainderIsReported() {
        let result = PlateMath.stack(for: 47, barWeight: 45)
        XCTAssertEqual(result.platesPerSide, Array(repeating: 0, count: 6))
        XCTAssertEqual(result.achievedWeight, 45)
        XCTAssertEqual(result.remainder, 2)
    }

    // MARK: - Target below bar weight (brief-required case)
    // There is no rack weight lighter than an empty bar — clamps to the
    // bar, with a remainder note showing how far below it the target sits.

    func testStack_targetBelowBarClampsToBarWeight() {
        let result = PlateMath.stack(for: 30, barWeight: 45)
        XCTAssertEqual(result.platesPerSide, Array(repeating: 0, count: 6))
        XCTAssertEqual(result.achievedWeight, 45)
        XCTAssertEqual(result.remainder, 15)
    }

    // MARK: - Non-integral target, 137.5 (brief-required case)
    // (137.5 - 45) / 2 = 46.25 per side. Greedy takes one 45 (leaving 1.25
    // per side) — too small for the next plate (35) let alone the smallest
    // (2.5) — so 135 lbs is achieved with a 2.5 lb remainder.

    func testStack_nonIntegralTargetProducesRemainder() {
        let result = PlateMath.stack(for: 137.5, barWeight: 45)
        XCTAssertEqual(result.platesPerSide, [1, 0, 0, 0, 0, 0])
        XCTAssertEqual(result.achievedWeight, 135)
        XCTAssertEqual(result.remainder, 2.5)
    }

    // MARK: - Large stack (brief-required case)
    // 405 lbs = 45 lb bar + four 45s per side ("four plates a side").

    func testStack_largeStackUsesMultiplePlatesPerSide() {
        let result = PlateMath.stack(for: 405, barWeight: 45)
        XCTAssertEqual(result.platesPerSide, [4, 0, 0, 0, 0, 0])
        XCTAssertEqual(result.achievedWeight, 405)
        XCTAssertNil(result.remainder)
    }

    // MARK: - Custom bar weight
    // Women's/training bar (35 lbs) is respected, not hardcoded — 115 lbs
    // needs 40 lbs per side: one 35 + one 5, exact.

    func testStack_customBarWeightIsRespected() {
        let result = PlateMath.stack(for: 115, barWeight: 35)
        XCTAssertEqual(result.platesPerSide, [0, 1, 0, 0, 1, 0])
        XCTAssertEqual(result.achievedWeight, 115)
        XCTAssertNil(result.remainder)
    }

    // MARK: - Empty plates array (defensive edge case)
    // No denominations available at all: falls back to bar-only, with the
    // full shortfall reported as the remainder.

    func testStack_emptyPlatesArrayReturnsBarOnly() {
        let result = PlateMath.stack(for: 100, barWeight: 45, plates: [])
        XCTAssertEqual(result.platesPerSide, [])
        XCTAssertEqual(result.achievedWeight, 45)
        XCTAssertEqual(result.remainder, 55)
    }

    // MARK: - Default parameters
    // `barWeight`/`plates` default to `PlateMath.defaultBarWeight` (45) and
    // `PlateMath.standardPlates` when omitted.

    func testStack_defaultsMatchStandardPlatesAndBar() {
        let withDefaults = PlateMath.stack(for: 155)
        let explicit = PlateMath.stack(for: 155, barWeight: 45, plates: PlateMath.standardPlates)
        XCTAssertEqual(withDefaults, explicit)
    }
}
