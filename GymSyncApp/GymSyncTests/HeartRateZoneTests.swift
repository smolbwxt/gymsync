import XCTest
@testable import GymSync

/// Hermetic tests for `HeartRateZone`/`HeartRateFreshness` (`Services/
/// HeartRateZone.swift`) — Phase W Task 5. Pure functions, no Supabase, no
/// HealthKit, no `@MainActor` hop needed.
final class HeartRateZoneTests: XCTestCase {

    // MARK: - Zone boundaries (defaultMaxBPM = 190)

    /// Well within the warmup bucket.
    func testZoneWarmupWellBelowBoundary() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 100), .warmup) // 100/190 ≈ 52.6%
    }

    /// Just under the 60% warmup->moderate boundary (113/190 ≈ 59.47%).
    func testZoneJustBelowWarmupModerateBoundary() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 113), .warmup)
    }

    /// Exactly at the 60% boundary (114/190 = 60.0%) — moderate (`<` not `<=`
    /// on the warmup side, so exactly-60% belongs to moderate).
    func testZoneExactlyAtWarmupModerateBoundary() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 114), .moderate)
    }

    /// Well within the moderate bucket.
    func testZoneModerateMidBucket() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 130), .moderate) // 130/190 ≈ 68.4%
    }

    /// Just under the 75% moderate->hard boundary (142/190 ≈ 74.7%).
    func testZoneJustBelowModerateHardBoundary() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 142), .moderate)
    }

    /// Exactly at the 75% boundary (143/190 ≈ 75.26%, first bpm at/above 75%) — hard.
    func testZoneAtOrAboveModerateHardBoundary() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 143), .hard)
    }

    /// Well within the hard bucket.
    func testZoneHardMidBucket() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 155), .hard) // 155/190 ≈ 81.6%
    }

    /// Just under the 90% hard->max boundary (170/190 ≈ 89.47%).
    func testZoneJustBelowHardMaxBoundary() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 170), .hard)
    }

    /// Exactly at the 90% boundary (171/190 = 90.0%) — max.
    func testZoneExactlyAtHardMaxBoundary() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 171), .max)
    }

    /// Well above max HR (e.g. a sensor glitch) — still classified `.max`,
    /// never crashes or produces an out-of-range case.
    func testZoneWellAboveMax() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 250), .max)
    }

    /// bpm=0 — degenerate but must not crash; 0% of max is warmup.
    func testZoneZeroBPM() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 0), .warmup)
    }

    // MARK: - Custom maxBPM

    /// A caller-supplied `maxBPM` is honored, not the default.
    func testZoneRespectsCustomMaxBPM() {
        // 120/200 = 60% -> moderate under a 200 max, though it would be
        // warmup under the 190 default (120/190 ≈ 63.2%, actually already
        // moderate there too — pick a value that diverges cleanly instead).
        XCTAssertEqual(HeartRateZone.zone(bpm: 113, maxBPM: 200), .warmup) // 113/200 = 56.5%
        XCTAssertEqual(HeartRateZone.zone(bpm: 113, maxBPM: 150), .hard)   // 113/150 ≈ 75.3%
    }

    /// Degenerate `maxBPM` (zero/negative) must not divide-by-zero crash —
    /// falls back to `.warmup` rather than producing NaN/infinity comparisons.
    func testZoneWithNonPositiveMaxBPMFallsBackToWarmup() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 150, maxBPM: 0), .warmup)
        XCTAssertEqual(HeartRateZone.zone(bpm: 150, maxBPM: -10), .warmup)
    }

    // MARK: - HeartRateFreshness (staleness boundary — >15s task-5-brief.md item 4)

    func testFreshnessFreshAtZeroAge() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(HeartRateFreshness.isFresh(receivedAt: now, now: now, staleAfter: 15))
    }

    /// Just under the 15s boundary — still fresh.
    func testFreshnessJustUnderBoundary() {
        let receivedAt = Date(timeIntervalSince1970: 1000)
        let now = receivedAt.addingTimeInterval(14.9)
        XCTAssertTrue(HeartRateFreshness.isFresh(receivedAt: receivedAt, now: now, staleAfter: 15))
    }

    /// Exactly at the 15s boundary — inclusive (`<=`), so still fresh.
    func testFreshnessExactlyAtBoundary() {
        let receivedAt = Date(timeIntervalSince1970: 1000)
        let now = receivedAt.addingTimeInterval(15.0)
        XCTAssertTrue(HeartRateFreshness.isFresh(receivedAt: receivedAt, now: now, staleAfter: 15))
    }

    /// Just past the 15s boundary — stale.
    func testFreshnessJustPastBoundary() {
        let receivedAt = Date(timeIntervalSince1970: 1000)
        let now = receivedAt.addingTimeInterval(15.1)
        XCTAssertFalse(HeartRateFreshness.isFresh(receivedAt: receivedAt, now: now, staleAfter: 15))
    }

    /// Comfortably stale.
    func testFreshnessWellPastBoundary() {
        let receivedAt = Date(timeIntervalSince1970: 1000)
        let now = receivedAt.addingTimeInterval(60)
        XCTAssertFalse(HeartRateFreshness.isFresh(receivedAt: receivedAt, now: now, staleAfter: 15))
    }
}
