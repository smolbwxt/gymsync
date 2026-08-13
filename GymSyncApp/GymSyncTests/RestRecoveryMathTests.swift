import XCTest
@testable import GymSync

/// Recovery-adaptive rest judgment coverage — the self-referenced baseline
/// and the two-sided verdict windows.
final class RestRecoveryMathTests: XCTestCase {

    func testBaselineNeedsTwoRests() {
        XCTAssertNil(RestRecoveryMath.baseline(priorDrops: []))
        XCTAssertNil(RestRecoveryMath.baseline(priorDrops: [30]))
        XCTAssertEqual(RestRecoveryMath.baseline(priorDrops: [30, 40]), 35)
        XCTAssertEqual(RestRecoveryMath.baseline(priorDrops: [20, 30, 44]), 30)
    }

    func testReadyFiresOnlyEarlyAndAtBaseline() {
        // At baseline before halfway → ready.
        XCTAssertEqual(RestRecoveryMath.verdict(currentDrop: 36, baseline: 35, progress: 0.3), .ready)
        // Same drop but past halfway → silent (let the timer run).
        XCTAssertNil(RestRecoveryMath.verdict(currentDrop: 36, baseline: 35, progress: 0.6))
        // Below baseline early → silent.
        XCTAssertNil(RestRecoveryMath.verdict(currentDrop: 20, baseline: 35, progress: 0.3))
    }

    func testLaggingFiresOnlyLateAndWellShort() {
        // Well short (<60% of baseline) late in the window → lagging.
        XCTAssertEqual(RestRecoveryMath.verdict(currentDrop: 15, baseline: 35, progress: 0.85), .lagging)
        // Short but not WELL short → silent.
        XCTAssertNil(RestRecoveryMath.verdict(currentDrop: 25, baseline: 35, progress: 0.85))
        // Well short but not late yet → silent.
        XCTAssertNil(RestRecoveryMath.verdict(currentDrop: 15, baseline: 35, progress: 0.6))
    }

    func testMissingInputsStaySilent() {
        XCTAssertNil(RestRecoveryMath.verdict(currentDrop: nil, baseline: 35, progress: 0.3))
        XCTAssertNil(RestRecoveryMath.verdict(currentDrop: 30, baseline: nil, progress: 0.3))
        XCTAssertNil(RestRecoveryMath.verdict(currentDrop: 30, baseline: 0, progress: 0.3))
    }
}