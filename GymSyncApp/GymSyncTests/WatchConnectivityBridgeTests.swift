import XCTest
@testable import GymSync

/// Hermetic tests for `WatchConnectivityBridge`'s (`Services/
/// WatchConnectivityBridge.swift`) phone-side action routing — Phase W
/// Task 2 (watch-hr design §3). No WatchConnectivity, no Supabase, no
/// AVFoundation: `WCSession` is faked via the `WatchSessionProviding`
/// seam, the set-log submit path via `SetLogSubmitting` (the SAME seam
/// `OfflineSetLogQueueTests` already fakes — see that file's header doc
/// comment for the shared idiom this mirrors), and the soundboard
/// play/broadcast pair via `SoundboardBroadcasting`.
///
/// `WatchEnvelope`'s own codec properties (round-trip, unknown-kind
/// tolerance, version gate) are covered separately in
/// `WatchEnvelopeTests.swift` — this file assumes that codec works and
/// focuses purely on WHAT THE BRIDGE DOES with a decoded envelope: which
/// handler a `kind` dispatches to, what `SetLog` gets built and submitted,
/// how a `.network` failure becomes a `.queued` reply via the SAME offline
/// queue the phone's own live-session UI uses, and the exact reply shapes.
@MainActor
final class WatchConnectivityBridgeTests: XCTestCase {

    // MARK: - Fakes

    /// Records every `sendMessage`-style delivery and every
    /// `updateApplicationContext` push. Captures the bridge's
    /// `onMessageReceived` closure on assignment (mirrors how the real
    /// `WCSessionProvider` wires it once in `WatchConnectivityBridge.init`)
    /// so a test can simulate an inbound WCSession delivery by invoking it
    /// directly — no WatchConnectivity linkage anywhere in this file.
    private final class FakeWatchSession: WatchSessionProviding {
        var onMessageReceived: (([String: Any], @escaping ([String: Any]) -> Void) -> Void)?
        private(set) var activateCallCount = 0
        private(set) var pushedContexts: [[String: Any]] = []
        var updateContextError: Error?

        func activate() { activateCallCount += 1 }

        func updateApplicationContext(_ context: [String: Any]) throws {
            if let updateContextError { throw updateContextError }
            pushedContexts.append(context)
        }
    }

    /// Same "protocol + production conformer + test fake" idiom as
    /// `OfflineSetLogQueueTests.FakeSetLogSubmitter` (that file's header
    /// doc comment) — deliberately redefined here rather than shared,
    /// matching this codebase's existing convention of each test file
    /// owning its own fakes (`VoiceRoomServiceTests`, `OfflineSetLogQueueTests`
    /// each define structurally-similar-but-separate fakes).
    private final class FakeSetLogSubmitter: SetLogSubmitting {
        enum Outcome {
            case success
            case failure(GymSyncError)
        }
        var outcome: Outcome = .success
        private(set) var submittedLogs: [SetLog] = []

        func submit(_ log: SetLog) async throws {
            submittedLogs.append(log)
            switch outcome {
            case .success: return
            case .failure(let error): throw error
            }
        }
    }

    private final class FakeCurrentUserIDProvider: CurrentUserIDProviding {
        var currentUserID: UUID?
        init(currentUserID: UUID?) { self.currentUserID = currentUserID }
    }

    private final class FakeSoundboardBroadcasting: SoundboardBroadcasting {
        private(set) var playedSlugs: [String] = []
        private(set) var sentSounds: [(sessionID: UUID, groupID: UUID?, slug: String)] = []

        func play(slug: String) async { playedSlugs.append(slug) }

        func sendSound(sessionID: UUID, groupID: UUID?, slug: String) async {
            sentSounds.append((sessionID, groupID, slug))
        }
    }

    // MARK: - Helpers

    private struct Harness {
        let bridge: WatchConnectivityBridge
        let session: FakeWatchSession
        let submitter: FakeSetLogSubmitter
        let soundboard: FakeSoundboardBroadcasting
    }

    private func makeHarness(userID: UUID? = UUID()) -> Harness {
        let session = FakeWatchSession()
        let submitter = FakeSetLogSubmitter()
        let soundboard = FakeSoundboardBroadcasting()
        let bridge = WatchConnectivityBridge(
            session: session,
            submitter: submitter,
            userIDProvider: FakeCurrentUserIDProvider(currentUserID: userID),
            soundboard: soundboard
        )
        return Harness(bridge: bridge, session: session, submitter: submitter, soundboard: soundboard)
    }

    /// Seeds `bridge.lastPushedState` the same way `GroupSessionLiveView.
    /// pushWatchSessionState()` does in production — through the real
    /// `updateSessionState(_:)` call, not by poking a private field.
    private func seedSessionState(
        _ harness: Harness,
        sessionID: UUID = UUID(),
        groupID: UUID? = UUID()
    ) -> WatchSessionStatePayload {
        let payload = WatchSessionStatePayload(
            sessionID: sessionID, groupID: groupID, sessionName: "Push Day",
            currentExerciseName: "Bench Press", currentLifterName: "tommy",
            isMyTurn: true, burpeesOwed: 0
        )
        harness.bridge.updateSessionState(payload)
        return payload
    }

    private func reply(from dict: [String: Any]) throws -> WatchActionReply {
        try XCTUnwrap(WatchActionReply.from(message: dict))
    }

    // MARK: - Activation lifecycle

    func testActivateIfNeededIsIdempotent() {
        let h = makeHarness()
        h.bridge.activateIfNeeded()
        h.bridge.activateIfNeeded()
        h.bridge.activateIfNeeded()
        XCTAssertEqual(h.session.activateCallCount, 1)
    }

    // MARK: - updateSessionState

    func testUpdateSessionStatePushesEncodedEnvelope() throws {
        let h = makeHarness()
        let payload = seedSessionState(h)

        XCTAssertEqual(h.session.pushedContexts.count, 1)
        let envelope = try XCTUnwrap(WatchEnvelope.from(message: h.session.pushedContexts[0]))
        XCTAssertEqual(envelope.decodedKind(), .sessionState)
        let decoded = try envelope.decodePayload(as: WatchSessionStatePayload.self)
        XCTAssertEqual(decoded.sessionID, payload.sessionID)
        XCTAssertEqual(decoded.groupID, payload.groupID)
        XCTAssertEqual(decoded.currentExerciseName, payload.currentExerciseName)
    }

    func testUpdateSessionStateSwallowsPushFailure() {
        let h = makeHarness()
        h.session.updateContextError = URLError(.notConnectedToInternet)
        // Must not throw or crash the caller — best-effort per this
        // method's own doc comment.
        _ = seedSessionState(h)
        XCTAssertEqual(h.session.pushedContexts.count, 0, "the fake recorded nothing since the push threw")
    }

    // MARK: - updateIdleState (Task 3)

    func testUpdateIdleStatePushesEncodedEnvelope() throws {
        let h = makeHarness()
        let at = Date()
        let payload = WatchIdleStatePayload(nextSessionName: "Leg Day", nextSessionAt: at)
        h.bridge.updateIdleState(payload)

        XCTAssertEqual(h.session.pushedContexts.count, 1)
        let envelope = try XCTUnwrap(WatchEnvelope.from(message: h.session.pushedContexts[0]))
        XCTAssertEqual(envelope.decodedKind(), .idleState)
        let decoded = try envelope.decodePayload(as: WatchIdleStatePayload.self)
        XCTAssertEqual(decoded.nextSessionName, "Leg Day")
    }

    func testUpdateIdleStateSwallowsPushFailure() {
        let h = makeHarness()
        h.session.updateContextError = URLError(.notConnectedToInternet)
        h.bridge.updateIdleState(WatchIdleStatePayload(nextSessionName: nil, nextSessionAt: nil))
        XCTAssertEqual(h.session.pushedContexts.count, 0, "the fake recorded nothing since the push threw")
    }

    func testUpdateIdleStateDoesNotTouchLastPushedState() {
        // updateIdleState must not clobber lastPushedState — that field
        // resolves sessionID/groupID for INBOUND watch actions, and there's
        // no such action tied to idle state (see updateIdleState's own doc
        // comment).
        let h = makeHarness()
        let sessionPayload = seedSessionState(h)
        h.bridge.updateIdleState(WatchIdleStatePayload(nextSessionName: "Leg Day", nextSessionAt: Date()))
        XCTAssertEqual(h.bridge.lastPushedState?.sessionID, sessionPayload.sessionID)
    }

    // MARK: - logSet routing

    func testLogSetRoutesToSubmitterAndRepliesSuccess() async throws {
        let h = makeHarness()
        let state = seedSessionState(h)
        let exerciseID = UUID()
        let payload = WatchLogSetPayload(exerciseID: exerciseID, reps: 10, weight: 185, rpe: 7, isFailed: false, note: "watch tap")
        let envelope = try WatchEnvelope.encode(kind: .logSet, payload: payload)

        var captured: [String: Any] = [:]
        await h.bridge.handleLogSet(envelope, replyHandler: { captured = $0 })

        XCTAssertEqual(h.submitter.submittedLogs.count, 1)
        let log = try XCTUnwrap(h.submitter.submittedLogs.first)
        XCTAssertEqual(log.sessionID, state.sessionID)
        XCTAssertEqual(log.exerciseID, exerciseID)
        XCTAssertEqual(log.reps, 10)
        XCTAssertEqual(log.weight, 185)
        XCTAssertEqual(log.rpe, 7)
        XCTAssertFalse(log.isFailed)
        XCTAssertFalse(log.isPenalty, "watch taps are always a normal set, never a penalty log")
        XCTAssertEqual(log.note, "watch tap")
        // setIndex: 1 — same "not turn-tracked" precedent GroupSessionLiveView.logSet's
        // penalty path already establishes (GroupSessionLiveView.swift:2108);
        // see WatchConnectivityBridge.handleLogSet's doc comment for the full citation.
        XCTAssertEqual(log.setIndex, 1)

        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .success)
    }

    func testLogSetNetworkFailureQueuesOfflineAndRepliesQueued() async throws {
        let h = makeHarness()
        _ = seedSessionState(h)
        h.submitter.outcome = .failure(.network)
        let payload = WatchLogSetPayload(exerciseID: UUID(), reps: 5, weight: 45, rpe: 6, isFailed: false, note: nil)
        let envelope = try WatchEnvelope.encode(kind: .logSet, payload: payload)

        var captured: [String: Any] = [:]
        await h.bridge.handleLogSet(envelope, replyHandler: { captured = $0 })

        // The submit was ATTEMPTED (matches logSetAndAdvance's own
        // "try the submit first, queue only on .network" ordering) —
        // OfflineSetLogQueue.shared.enqueue(_:) itself is exercised
        // separately by OfflineSetLogQueueTests; this test's job is only
        // to prove the BRIDGE correctly distinguishes `.network` from every
        // other failure and reports `.queued`, not `.failure`.
        XCTAssertEqual(h.submitter.submittedLogs.count, 1)
        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .queued)
    }

    func testLogSetNonNetworkFailureRepliesFailureNotQueued() async throws {
        let h = makeHarness()
        _ = seedSessionState(h)
        h.submitter.outcome = .failure(.validation("bad reps"))
        let payload = WatchLogSetPayload(exerciseID: UUID(), reps: -1, weight: nil, rpe: nil, isFailed: false, note: nil)
        let envelope = try WatchEnvelope.encode(kind: .logSet, payload: payload)

        var captured: [String: Any] = [:]
        await h.bridge.handleLogSet(envelope, replyHandler: { captured = $0 })

        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .failure)
        XCTAssertEqual(outcome.message, "bad reps")
    }

    func testLogSetWithNoSignedInUserRepliesFailure() async throws {
        let h = makeHarness(userID: nil)
        _ = seedSessionState(h)
        let payload = WatchLogSetPayload(exerciseID: UUID(), reps: 5, weight: nil, rpe: nil, isFailed: false, note: nil)
        let envelope = try WatchEnvelope.encode(kind: .logSet, payload: payload)

        var captured: [String: Any] = [:]
        await h.bridge.handleLogSet(envelope, replyHandler: { captured = $0 })

        XCTAssertEqual(h.submitter.submittedLogs.count, 0, "must never attempt a submit with no user to attribute it to")
        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .failure)
    }

    func testLogSetWithNoActiveSessionRepliesFailure() async throws {
        // No seedSessionState call — bridge.lastPushedState is still nil.
        let h = makeHarness()
        let payload = WatchLogSetPayload(exerciseID: UUID(), reps: 5, weight: nil, rpe: nil, isFailed: false, note: nil)
        let envelope = try WatchEnvelope.encode(kind: .logSet, payload: payload)

        var captured: [String: Any] = [:]
        await h.bridge.handleLogSet(envelope, replyHandler: { captured = $0 })

        XCTAssertEqual(h.submitter.submittedLogs.count, 0)
        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .failure)
    }

    func testLogSetWithMalformedPayloadRepliesFailure() async throws {
        let h = makeHarness()
        _ = seedSessionState(h)
        // A well-formed envelope SHELL whose payload bytes don't decode as
        // WatchLogSetPayload — distinct from WatchEnvelopeTests' "unknown
        // kind" case: here the KIND is recognized but the PAYLOAD is bad.
        let envelope = WatchEnvelope(kind: .logSet, payload: Data("not json".utf8))

        var captured: [String: Any] = [:]
        await h.bridge.handleLogSet(envelope, replyHandler: { captured = $0 })

        XCTAssertEqual(h.submitter.submittedLogs.count, 0)
        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .failure)
    }

    // MARK: - soundboardTap routing

    func testSoundboardTapPlaysAndBroadcastsThenRepliesSuccess() async throws {
        let h = makeHarness()
        let state = seedSessionState(h)
        let payload = WatchSoundboardTapPayload(slug: "airhorn")
        let envelope = try WatchEnvelope.encode(kind: .soundboardTap, payload: payload)

        var captured: [String: Any] = [:]
        await h.bridge.handleSoundboardTap(envelope, replyHandler: { captured = $0 })

        XCTAssertEqual(h.soundboard.playedSlugs, ["airhorn"])
        XCTAssertEqual(h.soundboard.sentSounds.count, 1)
        let sent = try XCTUnwrap(h.soundboard.sentSounds.first)
        XCTAssertEqual(sent.sessionID, state.sessionID)
        XCTAssertEqual(sent.groupID, state.groupID)
        XCTAssertEqual(sent.slug, "airhorn")

        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .success)
    }

    func testSoundboardTapWithNoActiveSessionRepliesFailure() async throws {
        let h = makeHarness()
        let payload = WatchSoundboardTapPayload(slug: "airhorn")
        let envelope = try WatchEnvelope.encode(kind: .soundboardTap, payload: payload)

        var captured: [String: Any] = [:]
        await h.bridge.handleSoundboardTap(envelope, replyHandler: { captured = $0 })

        XCTAssertTrue(h.soundboard.playedSlugs.isEmpty)
        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .failure)
    }

    // MARK: - Full dispatch (onMessageReceived -> handle -> handler), incl. envelope-level gates

    /// End-to-end proof that the `.logSet` KIND really does route through
    /// to `handleLogSet` via the SAME `onMessageReceived` closure
    /// `WatchConnectivityBridge.init` wires — the tests above call
    /// `handleLogSet`/`handleSoundboardTap` directly for focused coverage,
    /// this one exercises the actual dispatcher in `handle(message:replyHandler:)`.
    /// Safe against the continuation-before-Task-observability class of
    /// deadlock `VoiceRoomServiceTests`'s `PendingTokenFetcher` doc comment
    /// warns about: the continuation is created and handed to
    /// `withCheckedContinuation` BEFORE anything can resume it, and this
    /// whole test runs `@MainActor`-serialized with the bridge's own
    /// dispatch `Task`, so there is nothing to race.
    func testDispatchRoutesLogSetKindThroughToHandler() async throws {
        let h = makeHarness()
        _ = seedSessionState(h)
        let payload = WatchLogSetPayload(exerciseID: UUID(), reps: 3, weight: 225, rpe: 9, isFailed: false, note: nil)
        let envelope = try WatchEnvelope.encode(kind: .logSet, payload: payload)
        let message = try envelope.asMessage()
        let onMessageReceived = try XCTUnwrap(h.session.onMessageReceived)

        let captured: [String: Any] = await withCheckedContinuation { continuation in
            onMessageReceived(message) { reply in
                continuation.resume(returning: reply)
            }
        }

        XCTAssertEqual(h.submitter.submittedLogs.count, 1)
        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .success)
    }

    /// Malformed-envelope / unsupported-version / unknown-kind all reply
    /// SYNCHRONOUSLY (no `Task` spawned — see `handle`'s guard-return
    /// structure), so these don't need the continuation dance above.
    func testDispatchRepliesFailureForMessageWithNoEnvelope() throws {
        let h = makeHarness()
        let onMessageReceived = try XCTUnwrap(h.session.onMessageReceived)
        var captured: [String: Any] = [:]
        onMessageReceived(["unrelated": "value"], { captured = $0 })

        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .failure)
    }

    func testDispatchRepliesFailureForUnsupportedVersion() throws {
        let h = makeHarness()
        let onMessageReceived = try XCTUnwrap(h.session.onMessageReceived)
        let envelope = WatchEnvelope(kind: .logSet, payload: Data(), v: WatchEnvelope.maxSupportedVersion + 1)
        let message = try envelope.asMessage()

        var captured: [String: Any] = [:]
        onMessageReceived(message, { captured = $0 })

        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .failure)
        XCTAssertEqual(h.submitter.submittedLogs.count, 0, "an unsupported-version envelope must never reach the submit path")
    }

    func testDispatchRepliesFailureForUnknownKind() throws {
        let h = makeHarness()
        let onMessageReceived = try XCTUnwrap(h.session.onMessageReceived)
        // Same RawEnvelopeShell trick WatchEnvelopeTests uses to construct
        // an envelope carrying a kind this build's enum doesn't declare.
        struct RawEnvelopeShell: Codable { let v: Int; let kind: String; let payload: Data }
        let raw = RawEnvelopeShell(v: WatchEnvelope.currentVersion, kind: "somethingFromTheFuture", payload: Data())
        let data = try WatchWire.encoder.encode(raw)
        // Explicit `[String: Any]` annotation — a bare `let message =
        // ["envelope": data]` would infer `[String: Data]` (the literal's
        // only value type), which does NOT implicitly convert to the
        // `[String: Any]` `onMessageReceived` expects (Dictionary's value
        // type is invariant). Passing a literal directly as a call
        // argument gets this for free from the parameter's expected type;
        // an intermediate `let` breaks that inference chain, so it's
        // spelled out here.
        let message: [String: Any] = ["envelope": data]

        var captured: [String: Any] = [:]
        onMessageReceived(message, { captured = $0 })

        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .failure)
    }

    func testDispatchRepliesFailureForSessionStateKindReceivedOnPhone() throws {
        // sessionState is phone->watch ONLY; the phone must never act on
        // receiving one itself (see `handle`'s `.sessionState` case).
        let h = makeHarness()
        let onMessageReceived = try XCTUnwrap(h.session.onMessageReceived)
        let payload = WatchSessionStatePayload(
            sessionID: UUID(), groupID: nil, sessionName: "x",
            currentExerciseName: nil, currentLifterName: nil, isMyTurn: false, burpeesOwed: 0
        )
        let envelope = try WatchEnvelope.encode(kind: .sessionState, payload: payload)
        let message = try envelope.asMessage()

        var captured: [String: Any] = [:]
        onMessageReceived(message, { captured = $0 })

        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .failure)
    }

    func testDispatchRepliesFailureForIdleStateKindReceivedOnPhone() throws {
        // idleState is phone->watch ONLY (Task 3), same reasoning as
        // sessionState immediately above — the phone must never act on
        // receiving one itself (see `handle`'s `.idleState` case).
        let h = makeHarness()
        let onMessageReceived = try XCTUnwrap(h.session.onMessageReceived)
        let payload = WatchIdleStatePayload(nextSessionName: "Leg Day", nextSessionAt: Date())
        let envelope = try WatchEnvelope.encode(kind: .idleState, payload: payload)
        let message = try envelope.asMessage()

        var captured: [String: Any] = [:]
        onMessageReceived(message, { captured = $0 })

        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .failure)
    }

    func testDispatchRepliesFailureForHRSampleKind() throws {
        // T5 scope — not yet implemented; must fail honestly rather than
        // silently vanish (see `handle`'s `.hrSample` case doc comment).
        let h = makeHarness()
        let onMessageReceived = try XCTUnwrap(h.session.onMessageReceived)
        let payload = WatchHRSamplePayload(bpm: 140, recordedAt: Date())
        let envelope = try WatchEnvelope.encode(kind: .hrSample, payload: payload)
        let message = try envelope.asMessage()

        var captured: [String: Any] = [:]
        onMessageReceived(message, { captured = $0 })

        let outcome = try reply(from: captured)
        XCTAssertEqual(outcome.outcome, .failure)
    }
}
