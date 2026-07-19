import XCTest
@testable import GymSync

/// Pure-logic tests for `ThemeStore.mergeExternalSettingsWrite` — the merge
/// rule behind `noteExternalSettingsWrite`, which reconciles a rest-timer
/// save against `ThemeStore`'s own cached `user_settings` row (fix round B1,
/// final-review blocker: full-row upserts from `RestTimerSettingView` and
/// `ThemeStore.select(_:)` were clobbering each other's field via two
/// independent, never-reconciled caches).
///
/// This targets the extracted `nonisolated static` helper directly — no
/// `ThemeStore` singleton, no `@MainActor` hop, no network — so it can run
/// as a fast, deterministic unit test.
final class ThemeStoreMergeTests: XCTestCase {
    private let userID = UUID()

    private func settings(rest: Int, palette: String, shareHeartRate: Bool = false) -> UserSettings {
        UserSettings(userID: userID, defaultRestSeconds: rest, palette: palette, updatedAt: Date(), shareHeartRate: shareHeartRate)
    }

    /// No cached row yet (e.g. `ThemeStore.load()` never ran, or failed) —
    /// nothing to protect, so the incoming row is adopted wholesale.
    func testNoCachedRowAdoptsIncomingWholesale() {
        let incoming = settings(rest: 90, palette: "arena")

        let result = ThemeStore.mergeExternalSettingsWrite(
            cached: nil,
            incoming: incoming,
            persistInFlight: true
        )

        XCTAssertEqual(result, incoming)
    }

    /// No palette persist in flight — `cached` isn't fresher than
    /// `incoming` in this case, so adopt `incoming` wholesale. This is the
    /// common path: a rest-timer change with no concurrent palette tap.
    func testNoPersistInFlightAdoptsIncomingWholesale() {
        let cached = settings(rest: 120, palette: "midnight")
        let incoming = settings(rest: 90, palette: "midnight")

        let result = ThemeStore.mergeExternalSettingsWrite(
            cached: cached,
            incoming: incoming,
            persistInFlight: false
        )

        XCTAssertEqual(result, incoming)
    }

    /// A palette `select(_:)` persist is still in flight — that task owns
    /// `.palette` in the cache until its own upsert lands. The rest-timer
    /// save must not jump ahead and overwrite it; only `defaultRestSeconds`
    /// (the field this call actually has authority over) should be adopted.
    func testPersistInFlightMergesOnlyRestSecondsAndKeepsCachedPalette() {
        let cached = settings(rest: 120, palette: "arena")      // in-flight task's target
        let incoming = settings(rest: 90, palette: "midnight")  // rest-timer save's own row

        let result = ThemeStore.mergeExternalSettingsWrite(
            cached: cached,
            incoming: incoming,
            persistInFlight: true
        )

        XCTAssertEqual(result.palette, "arena", "in-flight palette must not be clobbered")
        XCTAssertEqual(result.defaultRestSeconds, 90, "rest seconds must still be adopted")
        XCTAssertEqual(result.userID, cached.userID, "everything else stays sourced from cached")
    }

    /// Sanity check for the guard's fallback branch: `persistInFlight: true`
    /// with no cached row still can't merge into anything, so it must fall
    /// back to adopting `incoming` wholesale rather than crashing/force-
    /// unwrapping.
    func testPersistInFlightWithNoCachedRowFallsBackToIncoming() {
        let incoming = settings(rest: 90, palette: "midnight")

        let result = ThemeStore.mergeExternalSettingsWrite(
            cached: nil,
            incoming: incoming,
            persistInFlight: true
        )

        XCTAssertEqual(result, incoming)
    }

    /// Task 4 (watch-hr design §4) extension: `shareHeartRate` has no
    /// in-flight-task owner of its own (unlike `.palette`, which
    /// `select(_:)`'s own in-flight task owns) — it must be treated exactly
    /// like `defaultRestSeconds`: always adopted from `incoming`, even while
    /// a palette persist is in flight. Without this, `YouTabView
    /// .setShareHeartRate`'s own `noteExternalSettingsWrite` call would be
    /// silently defeated by a concurrent palette tap, reproducing the exact
    /// clobber class this merge function exists to prevent — just for a
    /// THIRD field instead of the original two.
    func testPersistInFlightAlsoAdoptsShareHeartRateAndKeepsCachedPalette() {
        let cached = settings(rest: 120, palette: "arena", shareHeartRate: false)     // in-flight task's target
        let incoming = settings(rest: 120, palette: "midnight", shareHeartRate: true) // HR toggle's own row

        let result = ThemeStore.mergeExternalSettingsWrite(
            cached: cached,
            incoming: incoming,
            persistInFlight: true
        )

        XCTAssertEqual(result.palette, "arena", "in-flight palette must not be clobbered")
        XCTAssertTrue(result.shareHeartRate, "shareHeartRate must still be adopted from incoming, same as defaultRestSeconds")
    }
}
