import XCTest
@testable import GymSync

/// Hermetic tests for `WatchEnvelope` and its sibling wire types
/// (`GymSyncShared/WatchEnvelope.swift` — Phase W Task 2, watch-hr design
/// §3). Pure Codable logic: no WCSession, no `WatchConnectivityBridge`, no
/// network — covers exactly the 3 properties the task brief names
/// verbatim ("round-trip, unknown-kind tolerance, version gate").
///
/// `WatchConnectivityBridge`'s own routing behavior (which handler a kind
/// dispatches to, reply shapes, offline-queue fallback) is covered
/// separately in `WatchConnectivityBridgeTests.swift` — kept apart from
/// this file the same way `OfflineSetLogQueueTests` and
/// `VoiceRoomServiceTests` each own one seam's worth of behavior rather
/// than one mega-file.
final class WatchEnvelopeTests: XCTestCase {

    // MARK: - Round-trip

    /// Full round trip through the ACTUAL wire shape a `sendMessage`/
    /// `updateApplicationContext` call would use: build a payload -> encode
    /// into an envelope -> `asMessage()` (the `[String: Any]` dictionary
    /// WCSession requires) -> `from(message:)` (the receiving side's first
    /// step) -> `decodePayload(as:)`. Every hop is exercised, not just the
    /// innermost Codable conformance.
    func testLogSetPayloadRoundTripsThroughMessageDictionary() throws {
        let payload = WatchLogSetPayload(
            exerciseID: UUID(), reps: 8, weight: 135.5, rpe: 8, isFailed: false, note: "felt good"
        )
        let envelope = try WatchEnvelope.encode(kind: .logSet, payload: payload)
        let message = try envelope.asMessage()

        // Sanity: the ONE dictionary value must be a WCSession-supported
        // property-list type (`Data` bridges to `NSData`) — this is the
        // whole reason `WatchWire` exists (see its doc comment).
        XCTAssertTrue(message["envelope"] is Data)

        let decodedEnvelope = try XCTUnwrap(WatchEnvelope.from(message: message))
        XCTAssertEqual(decodedEnvelope, envelope)
        XCTAssertEqual(decodedEnvelope.decodedKind(), .logSet)
        XCTAssertTrue(decodedEnvelope.isSupportedVersion)

        let decodedPayload = try decodedEnvelope.decodePayload(as: WatchLogSetPayload.self)
        XCTAssertEqual(decodedPayload, payload)
    }

    /// Same round trip for `WatchSessionStatePayload` — the one payload
    /// carrying a `Date` field, so this also proves `WatchWire`'s
    /// `.iso8601` date strategy round-trips (sub-second precision is
    /// deliberately NOT asserted — ISO-8601 without fractional seconds
    /// truncates to whole seconds, which is fine for a "latest wins"
    /// state push; asserting exact `Date` equality here would be testing
    /// an unmade promise).
    func testSessionStatePayloadRoundTripsWithDate() throws {
        let original = WatchSessionStatePayload(
            sessionID: UUID(), groupID: UUID(), sessionName: "Push Day",
            currentExerciseName: "Bench Press", currentLifterName: "tommy",
            isMyTurn: true, burpeesOwed: 3, updatedAt: Date()
        )
        let envelope = try WatchEnvelope.encode(kind: .sessionState, payload: original)
        let message = try envelope.asMessage()
        let decoded = try XCTUnwrap(WatchEnvelope.from(message: message))
        let decodedPayload = try decoded.decodePayload(as: WatchSessionStatePayload.self)

        XCTAssertEqual(decodedPayload.sessionID, original.sessionID)
        XCTAssertEqual(decodedPayload.groupID, original.groupID)
        XCTAssertEqual(decodedPayload.sessionName, original.sessionName)
        XCTAssertEqual(decodedPayload.currentExerciseName, original.currentExerciseName)
        XCTAssertEqual(decodedPayload.currentLifterName, original.currentLifterName)
        XCTAssertEqual(decodedPayload.isMyTurn, original.isMyTurn)
        XCTAssertEqual(decodedPayload.burpeesOwed, original.burpeesOwed)
        XCTAssertLessThan(abs(decodedPayload.updatedAt.timeIntervalSince(original.updatedAt)), 1.0)
    }

    /// `WatchActionReply` rides the identical single-key `WatchWire` bridge
    /// but deliberately outside the `WatchEnvelope` shell (see its doc
    /// comment) — its own round trip is tested independently.
    func testActionReplyRoundTrips() throws {
        let reply = WatchActionReply(outcome: .queued, message: "saved locally")
        let message = try reply.asMessage()
        let decoded = WatchActionReply.from(message: message)
        XCTAssertEqual(decoded, reply)
    }

    func testFromMessageReturnsNilWhenWireKeyMissing() {
        XCTAssertNil(WatchEnvelope.from(message: ["unrelated": "value"]))
        XCTAssertNil(WatchActionReply.from(message: [:]))
    }

    /// A dictionary whose "envelope" value isn't even `Data` (e.g. a stray
    /// `String`) must be tolerated the same as a missing key — `from(message:)`
    /// never force-casts.
    func testFromMessageReturnsNilForWrongValueType() {
        XCTAssertNil(WatchEnvelope.from(message: ["envelope": "not-data"]))
    }

    // MARK: - Unknown-kind tolerance

    /// Mirrors `WatchEnvelope`'s own `{v, kind, payload}` shape exactly, so
    /// it can stand in for "a peer that sent a `kind` string this build's
    /// `WatchMessageKind` enum doesn't declare" — `WatchEnvelope`'s own
    /// memberwise `init` only accepts a real `WatchMessageKind`, so this is
    /// the only way to construct that scenario without reaching into
    /// `WatchEnvelope`'s private wire key.
    private struct RawEnvelopeShell: Codable {
        let v: Int
        let kind: String
        let payload: Data
    }

    /// The core "unknown-kind tolerance" test the brief names: a `kind`
    /// this build's enum doesn't recognize must decode the SHELL fine
    /// (`WatchEnvelope` itself is a valid, well-formed value) and only
    /// `decodedKind()` — the one place kind-recognition happens — returns
    /// `nil`. Nothing here throws.
    func testUnknownKindDecodesShellButReturnsNilKind() throws {
        let raw = RawEnvelopeShell(v: WatchEnvelope.currentVersion, kind: "somethingFromTheFuture", payload: Data())
        let data = try WatchWire.encoder.encode(raw)
        let envelope = try WatchWire.decoder.decode(WatchEnvelope.self, from: data)

        XCTAssertEqual(envelope.kind, "somethingFromTheFuture")
        XCTAssertNil(envelope.decodedKind())
        XCTAssertTrue(envelope.isSupportedVersion, "an unknown KIND is orthogonal to the shell VERSION gate")
    }

    /// Every currently-declared kind round-trips through `decodedKind()` —
    /// guards against a future rename of a `WatchMessageKind` case
    /// silently breaking recognition of its own raw value.
    func testAllDeclaredKindsAreRecognized() {
        for kind: WatchMessageKind in [.sessionState, .logSet, .soundboardTap, .hrSample] {
            let envelope = WatchEnvelope(kind: kind, payload: Data())
            XCTAssertEqual(envelope.decodedKind(), kind)
        }
    }

    // MARK: - Version gate

    /// A shell version ABOVE what this build declares it supports still
    /// decodes structurally (the 3-field shell hasn't changed) but is
    /// flagged `isSupportedVersion == false` — callers are expected to
    /// check this BEFORE acting on a recognized kind, per
    /// `WatchConnectivityBridge.handle(message:replyHandler:)`'s own gate
    /// ordering.
    func testVersionAboveMaxSupportedIsFlaggedUnsupported() throws {
        let raw = RawEnvelopeShell(
            v: WatchEnvelope.maxSupportedVersion + 1,
            kind: WatchMessageKind.logSet.rawValue,
            payload: Data()
        )
        let data = try WatchWire.encoder.encode(raw)
        let envelope = try WatchWire.decoder.decode(WatchEnvelope.self, from: data)

        XCTAssertFalse(envelope.isSupportedVersion)
        // The gate is a deliberate "don't ACT on it" choice, not a decode
        // failure — the kind still resolves fine even though a caller
        // should refuse to act on it.
        XCTAssertEqual(envelope.decodedKind(), .logSet)
    }

    func testCurrentVersionIsSupported() {
        let envelope = WatchEnvelope(kind: .logSet, payload: Data())
        XCTAssertEqual(envelope.v, WatchEnvelope.currentVersion)
        XCTAssertTrue(envelope.isSupportedVersion)
    }

    func testVersionAtExactlyMaxSupportedIsSupported() {
        let envelope = WatchEnvelope(kind: .logSet, payload: Data(), v: WatchEnvelope.maxSupportedVersion)
        XCTAssertTrue(envelope.isSupportedVersion)
    }
}
