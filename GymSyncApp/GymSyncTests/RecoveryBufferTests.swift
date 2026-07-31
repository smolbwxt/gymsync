import XCTest
@testable import GymSync

/// Pure-function coverage for `RecoveryBuffer` — the spectator page's
/// YOUR RECOVERY math. No network setUp (the ProgramMathTests pattern).
final class RecoveryBufferTests: XCTestCase {

    func testIgnoresNonPositiveAndOutOfOrder() {
        var buf = RecoveryBuffer(window: 90)
        buf.append(bpm: 0, at: 0)
        buf.append(bpm: -5, at: 1)
        XCTAssertTrue(buf.samples.isEmpty)
        buf.append(bpm: 150, at: 5)
        buf.append(bpm: 140, at: 5)   // same timestamp — ignored
        buf.append(bpm: 140, at: 4)   // going backwards — ignored
        XCTAssertEqual(buf.samples.count, 1)
        XCTAssertEqual(buf.current, 150)
    }

    func testDropIsPeakMinusCurrent() {
        var buf = RecoveryBuffer(window: 90)
        buf.append(bpm: 150, at: 0)
        buf.append(bpm: 168, at: 10)
        buf.append(bpm: 132, at: 20)
        XCTAssertEqual(buf.peak, 168)
        XCTAssertEqual(buf.current, 132)
        XCTAssertEqual(buf.drop, 36)
    }

    func testDropNilUntilTwoSamples() {
        var buf = RecoveryBuffer(window: 90)
        XCTAssertNil(buf.drop)
        buf.append(bpm: 160, at: 0)
        XCTAssertNil(buf.drop)
        buf.append(bpm: 150, at: 5)
        XCTAssertEqual(buf.drop, 10)
    }

    func testWindowTrimsOldPeak() {
        // The spike from three sets ago must not inflate today's drop.
        var buf = RecoveryBuffer(window: 90)
        buf.append(bpm: 180, at: 0)
        buf.append(bpm: 140, at: 50)
        buf.append(bpm: 120, at: 100)   // cutoff = 10 → t=0 sample trimmed
        XCTAssertEqual(buf.samples.count, 2)
        XCTAssertEqual(buf.peak, 140)
        XCTAssertEqual(buf.drop, 20)
    }

    func testSparklineCountAndRange() {
        var buf = RecoveryBuffer(window: 90)
        for i in 0..<22 {
            buf.append(bpm: 160 - i * 2, at: TimeInterval(i))
        }
        let bars = buf.sparkline(barCount: 22)
        XCTAssertEqual(bars.count, 22)
        XCTAssertEqual(bars.first, 1.0)   // the peak bucket
        XCTAssertEqual(bars.last, 0.0)    // the low bucket
        // Monotone decreasing input → monotone non-increasing bars.
        for (a, b) in zip(bars, bars.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a, b)
        }
    }

    func testSparklineFlatIsCentered() {
        var buf = RecoveryBuffer(window: 90)
        buf.append(bpm: 120, at: 0)
        buf.append(bpm: 120, at: 10)
        buf.append(bpm: 120, at: 20)
        let bars = buf.sparkline(barCount: 6)
        XCTAssertEqual(bars.count, 6)
        XCTAssertTrue(bars.allSatisfy { $0 == 0.5 })
    }

    func testSparklineEmptyUntilTwoSamples() {
        var buf = RecoveryBuffer(window: 90)
        XCTAssertTrue(buf.sparkline(barCount: 10).isEmpty)
        buf.append(bpm: 150, at: 0)
        XCTAssertTrue(buf.sparkline(barCount: 10).isEmpty)
    }

    func testReset() {
        var buf = RecoveryBuffer(window: 90)
        buf.append(bpm: 150, at: 0)
        buf.reset()
        XCTAssertTrue(buf.samples.isEmpty)
        XCTAssertNil(buf.current)
    }
}
