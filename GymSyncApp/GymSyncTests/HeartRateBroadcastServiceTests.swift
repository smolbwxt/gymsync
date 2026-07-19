import XCTest
@testable import GymSync

/// Hermetic tests for `HeartRateBroadcastService`'s pure, testable seam
/// (Phase W Task 4, watch-hr design §4) — the channel-name builder, the
/// `HeartRatePayload` wire shape, and the per-user throttle. No Supabase,
/// no Realtime channel, no `@MainActor` hop for the value-type pieces —
/// `subscribe`/`publish`/`unsubscribe` themselves are deliberately not
/// exercised here: implemented for real in T5, but they talk to a live
/// Supabase Realtime channel with no seam to fake it behind (the
/// `HeartRateBroadcasting` protocol abstracts this SERVICE for ITS
/// callers, not the SDK for this service), so they stay device-QA/CI
/// territory. (Fix wave 2 doc correction — this clause previously said
/// "unimplemented T5 stubs", stale since `95dd7a3`.)
// @MainActor: the service's statics are MainActor-isolated (CI-caught
// nonisolated-context error) — same annotation WatchConnectivityBridgeTests
// carries for the same reason.
@MainActor
final class HeartRateBroadcastServiceTests: XCTestCase {

    // MARK: - Channel name

    /// Spec's literal channel name (`docs/superpowers/specs/
    /// 2026-06-28-gymsync-design.md:965`, `session:{session_id}:hr`) — a
    /// DIFFERENT channel from plain `session:{id}`
    /// (`SessionBroadcastService`'s own channel).
    func testChannelNameMatchesSpecShape() {
        let sessionID = UUID()
        XCTAssertEqual(
            HeartRateBroadcastService.channelName(sessionID: sessionID),
            "session:\(sessionID.uuidString):hr"
        )
    }

    // MARK: - Payload wire shape

    /// Field names/keys match the spec's payload EXACTLY: `user_id`, `bpm`,
    /// `zone`, `ts` (`docs/superpowers/specs/2026-06-28-gymsync-design.md:1041`).
    /// Decodes the encoded bytes back through `JSONSerialization` (not a
    /// `Decodable` round trip — `HeartRatePayload` is deliberately
    /// `Encodable`-only, see its own doc comment) to inspect the actual
    /// wire keys a Realtime `broadcast(event:message:)` call would send.
    func testHeartRatePayloadEncodesExactWireKeys() throws {
        let userID = UUID()
        let payload = HeartRatePayload(
            userID: userID, bpm: 172, zone: "hard", at: Date(timeIntervalSince1970: 1_741_800_000.123)
        )

        let data = try JSONEncoder().encode(payload)
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(raw.keys), ["user_id", "bpm", "zone", "ts"])
        XCTAssertEqual(raw["user_id"] as? String, userID.uuidString)
        XCTAssertEqual(raw["bpm"] as? Int, 172)
        XCTAssertEqual(raw["zone"] as? String, "hard")
        XCTAssertEqual((raw["ts"] as? Double) ?? -1, 1_741_800_000_123, accuracy: 1.0)
    }

    /// `zone` is optional on the wire (the design doc's own shorthand:
    /// "the payload is {user_id, bpm, zone?}",
    /// `docs/superpowers/specs/2026-07-19-watch-hr-design.md:22`) — `nil`
    /// encodes by OMISSION, not as explicit JSON `null`.
    ///
    /// Fix wave 2 ADJUDICATION (this test previously asserted explicit
    /// `"zone": null` and was ruled WRONG — the implementation is right):
    /// (1) the spec's literal payload example
    /// (`docs/superpowers/specs/2026-06-28-gymsync-design.md:1041`) shows
    /// `zone` only WITH a value ("hard") and never demonstrates a null —
    /// it does not demand an always-present-nullable key; the design doc's
    /// `zone?` shorthand above marks it optional. (2) The phone-side
    /// receiver (`HeartRateBroadcastService.subscribe`'s
    /// `payload["zone"]?.stringValue`) returns `nil` identically for an
    /// absent key and an explicit null — the T4-era rationale this test
    /// carried ("so a receiver's `Decodable` (T5) can rely on the key
    /// always being present") never came true: T5's receiver is manual
    /// `AnyJSON` reads, not a `Decodable`. (3) The ACTUAL T5 production
    /// send path (`HeartRatePayload.wireMessage`) already omits `zone`
    /// when `nil`, with its own documented justification — this
    /// `Encodable` conformance is exercised only by these tests, and
    /// synthesized `Encodable` (no custom `encode(to:)` has ever existed
    /// on this type, checked back to T4's `7c537e1`) uses
    /// `encodeIfPresent` semantics: nil optionals are dropped. The old
    /// assertion contradicted the implementation from the day it was
    /// written and simply never ran (T5's CI died at a compile error
    /// before the suite executed).
    func testHeartRatePayloadOmitsNilZone() throws {
        let payload = HeartRatePayload(userID: UUID(), bpm: 60, zone: nil)

        let data = try JSONEncoder().encode(payload)
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertFalse(raw.keys.contains("zone"), "nil zone encodes by omission — matching wireMessage's own documented behavior and the receiver's absent-or-null-identical decode")
        XCTAssertEqual(Set(raw.keys), ["user_id", "bpm", "ts"])
    }

    // MARK: - Throttle (pure decision core)

    /// No prior send for this user — always allowed.
    func testThrottleAllowedWithNoPriorSend() {
        XCTAssertTrue(
            HeartRateThrottle.allowed(lastSentAt: nil, now: Date(), minInterval: 5.0)
        )
    }

    /// Just under the 5s window — denied.
    func testThrottleDeniedJustUnderInterval() {
        let last = Date(timeIntervalSince1970: 1000)
        let now = last.addingTimeInterval(4.9)
        XCTAssertFalse(
            HeartRateThrottle.allowed(lastSentAt: last, now: now, minInterval: 5.0)
        )
    }

    /// Exactly at the 5s boundary — allowed (`>=`, matching
    /// `SessionBroadcastService.rateAllowed()`'s identical `>=` boundary,
    /// `Services/SessionBroadcastService.swift:172`).
    func testThrottleAllowedExactlyAtInterval() {
        let last = Date(timeIntervalSince1970: 1000)
        let now = last.addingTimeInterval(5.0)
        XCTAssertTrue(
            HeartRateThrottle.allowed(lastSentAt: last, now: now, minInterval: 5.0)
        )
    }

    /// Comfortably past the window — allowed.
    func testThrottleAllowedWellPastInterval() {
        let last = Date(timeIntervalSince1970: 1000)
        let now = last.addingTimeInterval(10.0)
        XCTAssertTrue(
            HeartRateThrottle.allowed(lastSentAt: last, now: now, minInterval: 5.0)
        )
    }

    // MARK: - Throttle (stateful wrapper)

    /// First send for a user always succeeds and records the timestamp; an
    /// immediate second send for the SAME user is denied.
    func testStatefulThrottleDeniesImmediateSecondSendForSameUser() {
        var throttle = HeartRateThrottle(minInterval: 5.0)
        let userID = UUID()
        let t0 = Date(timeIntervalSince1970: 1000)

        XCTAssertTrue(throttle.rateAllowed(userID: userID, now: t0))
        XCTAssertFalse(throttle.rateAllowed(userID: userID, now: t0.addingTimeInterval(1.0)))
        XCTAssertTrue(throttle.rateAllowed(userID: userID, now: t0.addingTimeInterval(5.0)))
    }

    /// Per-user keying (spec: "one broadcast per 5 seconds per user") — a
    /// throttled user must not block a DIFFERENT user's send in the same
    /// window.
    func testStatefulThrottleIsIndependentPerUser() {
        var throttle = HeartRateThrottle(minInterval: 5.0)
        let userA = UUID()
        let userB = UUID()
        let t0 = Date(timeIntervalSince1970: 1000)

        XCTAssertTrue(throttle.rateAllowed(userID: userA, now: t0))
        XCTAssertFalse(throttle.rateAllowed(userID: userA, now: t0.addingTimeInterval(1.0)), "userA still within its own 5s window")
        XCTAssertTrue(throttle.rateAllowed(userID: userB, now: t0.addingTimeInterval(1.0)), "userB has never sent — must not be blocked by userA's window")
    }
}
