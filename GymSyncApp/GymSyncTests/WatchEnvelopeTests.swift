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

    /// Task 3 round-trip: the 4 new `WatchSessionStatePayload` fields
    /// (`currentExerciseID`, `burpeesPaid`, `soundboardFavorites`,
    /// `isActive`) survive the SAME full wire path as the Task 2 test
    /// above, non-default values throughout so a bug that silently drops
    /// back to a default couldn't hide behind "happens to match anyway."
    /// Fix wave 1 extended this to also cover `soundboardFavoriteLabels`
    /// (the 5th field, reviewer finding IMPORTANT 2) with its own distinct
    /// (non-slug-matching) values, for the identical reason.
    func testSessionStatePayloadRoundTripsTask3Fields() throws {
        let exerciseID = UUID()
        let original = WatchSessionStatePayload(
            sessionID: UUID(), groupID: UUID(), sessionName: "Push Day",
            currentExerciseName: "Bench Press", currentExerciseID: exerciseID,
            currentLifterName: "tommy", isMyTurn: true, burpeesOwed: 3,
            burpeesPaid: 7, soundboardFavorites: ["airhorn", "crowd-cheer"],
            soundboardFavoriteLabels: ["Air Horn", "Crowd Cheer"],
            isActive: false
        )
        let envelope = try WatchEnvelope.encode(kind: .sessionState, payload: original)
        let message = try envelope.asMessage()
        let decoded = try XCTUnwrap(WatchEnvelope.from(message: message))
        let decodedPayload = try decoded.decodePayload(as: WatchSessionStatePayload.self)

        XCTAssertEqual(decodedPayload.currentExerciseID, exerciseID)
        XCTAssertEqual(decodedPayload.burpeesPaid, 7)
        XCTAssertEqual(decodedPayload.soundboardFavorites, ["airhorn", "crowd-cheer"])
        XCTAssertEqual(decodedPayload.soundboardFavoriteLabels, ["Air Horn", "Crowd Cheer"])
        XCTAssertFalse(decodedPayload.isActive)
    }

    /// THE proof of this task's additive-payload discipline: a payload
    /// shaped like what a PRE-TASK-3 build would have encoded (only the 6
    /// Task-2 fields, none of the newer ones) must still decode
    /// successfully — a plain `Decodable` synthesis would have thrown here
    /// (missing required keys), which is exactly why `WatchSessionStatePayload`
    /// gained a custom `init(from:)` (see that type's own doc comment,
    /// `GymSyncShared/WatchEnvelope.swift`, for the `WorkoutSession`-mirrored
    /// "schema-lag" reasoning). Hand-builds the OLD-shaped JSON directly —
    /// constructing via `WatchSessionStatePayload.init(...)` would always
    /// include the new fields (they have parameter defaults), so it could
    /// never actually exercise the missing-key decode path this test needs.
    /// Fix wave 1 extended this test's own assertions to cover
    /// `soundboardFavoriteLabels`'s fallback too (falls back to `[]`, the
    /// same default `soundboardFavorites` itself lands on here, since both
    /// keys are equally absent from this JSON) — see the SEPARATE test
    /// immediately below for the fix-wave-1-specific "slugs present, labels
    /// absent" schema-lag scenario this field's fallback rule was actually
    /// designed for.
    func testSessionStatePayloadDecodesOldShapeMissingTask3Fields() throws {
        let sessionID = UUID()
        let json = """
        {
            "sessionID": "\(sessionID.uuidString)",
            "groupID": null,
            "sessionName": "Push Day",
            "currentExerciseName": "Bench Press",
            "currentLifterName": "tommy",
            "isMyTurn": true,
            "burpeesOwed": 3,
            "updatedAt": "2026-07-19T12:00:00Z"
        }
        """
        let decoded = try WatchWire.decoder.decode(WatchSessionStatePayload.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.sessionID, sessionID)
        XCTAssertEqual(decoded.sessionName, "Push Day")
        XCTAssertEqual(decoded.burpeesOwed, 3)
        // The Task 3 fields — absent from the JSON above — must fall back
        // to their documented defaults, not throw.
        XCTAssertNil(decoded.currentExerciseID)
        XCTAssertEqual(decoded.burpeesPaid, 0)
        XCTAssertEqual(decoded.soundboardFavorites, [])
        XCTAssertEqual(decoded.soundboardFavoriteLabels, [])
        XCTAssertTrue(decoded.isActive)
        // Task 4 field — also absent from this fully-old JSON — must fall
        // back to `false` (the column's own safe default), not throw.
        XCTAssertFalse(decoded.shareHeartRate)
    }

    /// Fix wave 1's OWN backward-compat proof (IMPORTANT 2) — the schema-lag
    /// scenario `soundboardFavoriteLabels`'s fallback rule was actually
    /// written for: a build that already sends `soundboardFavorites` (any
    /// Task-3-wave-0 build, already shipped before this fix) but predates
    /// `soundboardFavoriteLabels` itself. Falling back to `[]` here (like
    /// the fully-old-shape test above) would silently blank out every
    /// soundboard tile's label on a Watch that's otherwise perfectly capable
    /// of showing slugs — the fallback instead reuses `soundboardFavorites`
    /// itself, so the watch keeps rendering exactly what it rendered before
    /// this field existed (the slug), never a blank string.
    func testSessionStatePayloadFallsBackToSlugsWhenLabelsKeyAbsent() throws {
        let sessionID = UUID()
        let json = """
        {
            "sessionID": "\(sessionID.uuidString)",
            "groupID": null,
            "sessionName": "Push Day",
            "currentExerciseName": "Bench Press",
            "currentLifterName": "tommy",
            "isMyTurn": true,
            "burpeesOwed": 3,
            "soundboardFavorites": ["airhorn", "crowd-cheer"],
            "updatedAt": "2026-07-19T12:00:00Z"
        }
        """
        let decoded = try WatchWire.decoder.decode(WatchSessionStatePayload.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.soundboardFavorites, ["airhorn", "crowd-cheer"])
        XCTAssertEqual(decoded.soundboardFavoriteLabels, ["airhorn", "crowd-cheer"])
    }

    /// Task 4 (watch-hr design §4) round trip: `shareHeartRate` survives the
    /// SAME full wire path as the Task 3 fields above — `true` (the
    /// non-default value) so a silent fallback-to-`false` bug couldn't hide
    /// behind "happens to match anyway."
    func testSessionStatePayloadRoundTripsShareHeartRate() throws {
        let original = WatchSessionStatePayload(
            sessionID: UUID(), groupID: UUID(), sessionName: "Push Day",
            currentExerciseName: "Bench Press", currentLifterName: "tommy",
            isMyTurn: true, burpeesOwed: 3, shareHeartRate: true
        )
        let envelope = try WatchEnvelope.encode(kind: .sessionState, payload: original)
        let message = try envelope.asMessage()
        let decoded = try XCTUnwrap(WatchEnvelope.from(message: message))
        let decodedPayload = try decoded.decodePayload(as: WatchSessionStatePayload.self)

        XCTAssertTrue(decodedPayload.shareHeartRate)
    }

    /// Task 4's OWN backward-compat proof — the T3 fix wave's established
    /// pattern, followed exactly (see `testSessionStatePayloadFallsBackToSlugsWhenLabelsKeyAbsent`
    /// above for the analogous Task-3-wave-1 case): a payload JSON that
    /// already carries every Task-3 field but predates `shareHeartRate`
    /// itself (a build one version behind THIS fix) must still decode,
    /// falling back to `false` — the Watch's default posture is "don't
    /// start the HR query" unless explicitly told otherwise, matching the
    /// column's own `DEFAULT false`
    /// (`supabase/migrations/20260727000001_user_settings_share_heart_rate.sql`).
    func testSessionStatePayloadFallsBackToShareHeartRateFalseWhenKeyAbsent() throws {
        let sessionID = UUID()
        let json = """
        {
            "sessionID": "\(sessionID.uuidString)",
            "groupID": null,
            "sessionName": "Push Day",
            "currentExerciseName": "Bench Press",
            "currentLifterName": "tommy",
            "isMyTurn": true,
            "burpeesOwed": 3,
            "burpeesPaid": 7,
            "soundboardFavorites": ["airhorn"],
            "soundboardFavoriteLabels": ["Air Horn"],
            "isActive": true,
            "updatedAt": "2026-07-19T12:00:00Z"
        }
        """
        let decoded = try WatchWire.decoder.decode(WatchSessionStatePayload.self, from: Data(json.utf8))

        XCTAssertFalse(decoded.shareHeartRate)
        // Sanity: every OTHER field on this deliberately Task-3-shaped JSON
        // still decodes normally — this test isolates `shareHeartRate`'s
        // own fallback, not a general decode failure.
        XCTAssertEqual(decoded.burpeesPaid, 7)
        XCTAssertEqual(decoded.soundboardFavorites, ["airhorn"])
    }

    /// `WatchIdleStatePayload` round trip — Task 3's other new payload type,
    /// same wire path as every other kind (envelope -> message dict ->
    /// back).
    func testIdleStatePayloadRoundTrips() throws {
        let at = Date()
        let original = WatchIdleStatePayload(nextSessionName: "Leg Day", nextSessionAt: at)
        let envelope = try WatchEnvelope.encode(kind: .idleState, payload: original)
        let message = try envelope.asMessage()
        let decoded = try XCTUnwrap(WatchEnvelope.from(message: message))
        XCTAssertEqual(decoded.decodedKind(), .idleState)
        let decodedPayload = try decoded.decodePayload(as: WatchIdleStatePayload.self)

        XCTAssertEqual(decodedPayload.nextSessionName, "Leg Day")
        XCTAssertNotNil(decodedPayload.nextSessionAt)
        XCTAssertLessThan(abs(decodedPayload.nextSessionAt!.timeIntervalSince(at)), 1.0)
    }

    /// The "no upcoming session" idle shape — both fields nil, matching
    /// `HomeView.pushWatchIdleStateIfNoLiveSession`'s own "always set
    /// together" derivation (`upcomingSessions.first == nil`).
    func testIdleStatePayloadRoundTripsWithNoUpcomingSession() throws {
        let original = WatchIdleStatePayload(nextSessionName: nil, nextSessionAt: nil)
        let envelope = try WatchEnvelope.encode(kind: .idleState, payload: original)
        let message = try envelope.asMessage()
        let decoded = try XCTUnwrap(WatchEnvelope.from(message: message))
        let decodedPayload = try decoded.decodePayload(as: WatchIdleStatePayload.self)

        XCTAssertNil(decodedPayload.nextSessionName)
        XCTAssertNil(decodedPayload.nextSessionAt)
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
        // Task 3 extended this list with `.idleState` — every kind
        // `WatchMessageKind` currently declares.
        for kind: WatchMessageKind in [.sessionState, .logSet, .soundboardTap, .hrSample, .idleState] {
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
