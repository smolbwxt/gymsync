import XCTest
@testable import GymSync

/// Hermetic tests for `VoiceRoomService`'s state machine, mic-permission
/// gating, token-fetch failure mapping, mute semantics, and audio-session
/// restoration — all without touching LiveKit, the network, or real system
/// permission prompts (Phase 3e Task 3 brief).
///
/// Fakes below deliberately do NOT `import LiveKit` — they conform to
/// `VoiceRoomConnecting`, the same seam the production `LiveKitRoomConnection`
/// conforms to, so this file never links against the LiveKit SDK.
///
/// The audio session is faked via the `VoiceAudioSessionManaging` seam
/// (`SpyAudioSession` below). The first version of this file asserted against
/// `AudioSessionManager.shared` directly, which coupled tests to run order:
/// once the happy-path test completed it left the process-global
/// `isInVoiceMode` flag true, and the alphabetically-later micDenied test
/// failed against the polluted singleton (CI run 29307177206). Real
/// enter/exit ↔ AVAudioSession behavior is covered by
/// `AudioSessionVoiceModeTests`; these tests own the ORCHESTRATION contract
/// (when enter/exit are called), which the spy captures more precisely.
@MainActor
final class VoiceRoomServiceTests: XCTestCase {

    // MARK: - Fakes

    private final class FakeTokenFetcher: VoiceTokenFetching {
        var result: Result<VoiceTokenResponse, Error> = .success(
            VoiceTokenResponse(token: "test-token", url: "wss://example.livekit.cloud")
        )
        private(set) var requestedSessionIDs: [String] = []

        func fetchToken(sessionID: String) async throws -> VoiceTokenResponse {
            requestedSessionIDs.append(sessionID)
            return try result.get()
        }
    }

    private final class FakeMicPermission: MicPermissionChecking {
        var granted = true
        func requestRecordPermission() async -> Bool { granted }
    }

    /// Spy for the `VoiceAudioSessionManaging` seam — mirrors the real
    /// manager's semantics (enter can throw; exit never does; the flag
    /// tracks the last call) while recording call counts, so tests can
    /// assert not just the end state but that enter was NEVER called on
    /// gated paths. Fresh instance per test: zero shared state.
    private final class SpyAudioSession: VoiceAudioSessionManaging {
        var enterError: Error?
        private(set) var enterCallCount = 0
        private(set) var exitCallCount = 0
        private(set) var isInVoiceMode = false

        func enterVoiceMode() throws {
            if let enterError { throw enterError }
            enterCallCount += 1
            isInVoiceMode = true
        }

        func exitVoiceMode() {
            exitCallCount += 1
            isInVoiceMode = false
        }
    }

    /// Immediate-return fake that also fires an observation hook at the
    /// moment `join()` requests permission — lets a test capture the
    /// transient `.connecting` state deterministically, with no second Task,
    /// no polling, and no continuation that could be left un-resumed. The
    /// method NEVER suspends, so it is provably non-blocking.
    ///
    /// HISTORY (CI deadlock, run 29303069124): the first version of this
    /// fake suspended on a `CheckedContinuation` that the test resumed after
    /// observing a `wasCalled` flag from a MainActor poll loop. Its
    /// nonisolated-async method ran OFF the main actor and set
    /// `wasCalled = true` BEFORE `withCheckedContinuation` stored the
    /// continuation — so the spinning MainActor test could observe the flag
    /// and call `resume()` while `continuation` was still nil (`continuation?
    /// .resume` = silent no-op), leaving the join task suspended forever and
    /// the test awaiting it until the 45-min job timeout. This replacement is
    /// `@MainActor` (legal witness for an async protocol requirement) and
    /// has nothing to race and nothing to resume.
    @MainActor
    private final class RecordingMicPermission: MicPermissionChecking {
        var granted = true
        var onRequest: (@MainActor () -> Void)?

        func requestRecordPermission() async -> Bool {
            onRequest?()
            return granted
        }
    }

    /// Token fetcher that PARKS until the test resumes it — for exercising
    /// leave()-during-join interleavings. Safe against the round-3 deadlock
    /// class: everything is MainActor-serialized and the continuation is
    /// stored BEFORE `pending` is observable, so `resume()` can never race a
    /// nil continuation; tests bound their wait and fail loud, never hang.
    @MainActor
    private final class PendingTokenFetcher: VoiceTokenFetching {
        private var continuation: CheckedContinuation<VoiceTokenResponse, Error>?
        private(set) var pending = false

        func fetchToken(sessionID: String) async throws -> VoiceTokenResponse {
            try await withCheckedThrowingContinuation { cont in
                continuation = cont
                pending = true
            }
        }

        func resume(_ result: Result<VoiceTokenResponse, Error>) {
            pending = false
            continuation?.resume(with: result)
            continuation = nil
        }
    }

    /// Room whose connect PARKS until resumed — same safety pattern as
    /// `PendingTokenFetcher`. Mute/disconnect stay immediate.
    @MainActor
    private final class PendingConnectRoom: VoiceRoomConnecting {
        var onSpeakingParticipantsChanged: ((Set<String>) -> Void)?
        var onRosterChanged: ((Set<String>) -> Void)?
        var onRemoteMuteChanged: ((String, Bool) -> Void)?
        var onUnexpectedDisconnect: ((Error?) -> Void)?
        private var connectContinuation: CheckedContinuation<Void, Never>?
        private(set) var connectPending = false
        private(set) var connectCallCount = 0
        private(set) var disconnectCallCount = 0

        func connectAndPublishMuted(url: String, token: String) async throws {
            connectCallCount += 1
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                connectContinuation = cont
                connectPending = true
            }
        }

        func resumeConnect() {
            connectPending = false
            connectContinuation?.resume()
            connectContinuation = nil
        }

        func setMicrophoneMuted(_ muted: Bool) async throws {}
        func setLocalVolume(_ volume: Double, forParticipantIdentity identity: String) async {}

        func disconnect() async {
            disconnectCallCount += 1
        }
    }

    /// Bounded main-actor wait: yields until `condition` or the bound trips.
    /// Returns the final condition value so callers assert loud instead of
    /// hanging (never an unbounded poll — see RecordingMicPermission HISTORY).
    private func settleUntil(_ condition: () -> Bool) async -> Bool {
        var iterations = 0
        while !condition() && iterations < 50_000 {
            await Task.yield()
            iterations += 1
        }
        return condition()
    }

    private final class FakeRoomConnection: VoiceRoomConnecting {
        var onSpeakingParticipantsChanged: ((Set<String>) -> Void)?
        var onRosterChanged: ((Set<String>) -> Void)?
        var onRemoteMuteChanged: ((String, Bool) -> Void)?
        var onUnexpectedDisconnect: ((Error?) -> Void)?

        var connectError: Error?
        private(set) var connectCallCount = 0
        private(set) var lastConnectURL: String?
        private(set) var lastConnectToken: String?

        var muteError: Error?
        private(set) var muteCalls: [Bool] = []

        private(set) var localVolumeCalls: [(volume: Double, identity: String)] = []

        private(set) var disconnectCallCount = 0

        func connectAndPublishMuted(url: String, token: String) async throws {
            connectCallCount += 1
            lastConnectURL = url
            lastConnectToken = token
            if let connectError { throw connectError }
        }

        func setMicrophoneMuted(_ muted: Bool) async throws {
            if let muteError { throw muteError }
            muteCalls.append(muted)
        }

        func setLocalVolume(_ volume: Double, forParticipantIdentity identity: String) async {
            localVolumeCalls.append((volume, identity))
        }

        func disconnect() async {
            disconnectCallCount += 1
        }
    }

    /// Token fetcher supporting MULTIPLE independent in-flight calls at
    /// once, keyed by sessionID — unlike `PendingTokenFetcher` above (one
    /// shared continuation slot), needed to exercise item 3's "join for a
    /// different session while the previous one is still parked" race,
    /// where BOTH sessions' fetches are genuinely in flight at the same
    /// time. Same safety shape as `PendingTokenFetcher`: `@MainActor`,
    /// continuation stored before `pendingSessionIDs` is observable, so
    /// `resume(sessionID:_:)` can never race a nil continuation.
    @MainActor
    private final class MultiPendingTokenFetcher: VoiceTokenFetching {
        private var continuations: [String: CheckedContinuation<VoiceTokenResponse, Error>] = [:]
        private(set) var pendingSessionIDs: Set<String> = []
        private(set) var requestedSessionIDs: [String] = []

        func fetchToken(sessionID: String) async throws -> VoiceTokenResponse {
            requestedSessionIDs.append(sessionID)
            return try await withCheckedThrowingContinuation { cont in
                continuations[sessionID] = cont
                pendingSessionIDs.insert(sessionID)
            }
        }

        func resume(sessionID: String, _ result: Result<VoiceTokenResponse, Error>) {
            pendingSessionIDs.remove(sessionID)
            continuations[sessionID]?.resume(with: result)
            continuations[sessionID] = nil
        }
    }

    /// Room whose `disconnect()` PARKS until resumed — for item 1's
    /// `leave(timeout:)` test (a hung LiveKit teardown must not block the
    /// caller past the bound). Every other method is immediate. Same
    /// `@MainActor`/continuation-before-observable safety shape as
    /// `PendingConnectRoom` above.
    @MainActor
    private final class PendingDisconnectRoom: VoiceRoomConnecting {
        var onSpeakingParticipantsChanged: ((Set<String>) -> Void)?
        var onRosterChanged: ((Set<String>) -> Void)?
        var onRemoteMuteChanged: ((String, Bool) -> Void)?
        var onUnexpectedDisconnect: ((Error?) -> Void)?
        private var disconnectContinuation: CheckedContinuation<Void, Never>?
        private(set) var disconnectPending = false
        private(set) var disconnectCallCount = 0

        func connectAndPublishMuted(url: String, token: String) async throws {}
        func setMicrophoneMuted(_ muted: Bool) async throws {}
        func setLocalVolume(_ volume: Double, forParticipantIdentity identity: String) async {}

        func disconnect() async {
            disconnectCallCount += 1
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                disconnectContinuation = cont
                disconnectPending = true
            }
        }

        func resumeDisconnect() {
            disconnectPending = false
            disconnectContinuation?.resume()
            disconnectContinuation = nil
        }
    }

    // MARK: - State transitions: idle -> connecting -> connected(muted)

    func testJoinTransitionsThroughConnectingToConnectedMuted() async throws {
        let tokenFetcher = FakeTokenFetcher()
        let micPermission = RecordingMicPermission()
        let audio = SpyAudioSession()
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: micPermission, audioSession: audio, room: room
        )

        guard case .idle = service.state else {
            XCTFail("expected initial state .idle, got \(service.state)"); return
        }

        // Capture the state at the exact moment join() performs its first
        // await (the permission request). join() sets `state = .connecting`
        // synchronously before that call, so this observes the transient
        // state deterministically — no second Task, no polling, no
        // suspension anywhere in the test.
        var stateWhenPermissionRequested: VoiceRoomState?
        micPermission.onRequest = { stateWhenPermissionRequested = service.state }

        let sessionID = UUID()
        await service.join(sessionID: sessionID)

        guard case .connecting? = stateWhenPermissionRequested else {
            XCTFail("expected .connecting at permission-request time, got \(String(describing: stateWhenPermissionRequested))")
            return
        }
        guard case .connected(.muted) = service.state else {
            XCTFail("expected .connected(.muted) after join completes, got \(service.state)")
            return
        }
        XCTAssertEqual(room.connectCallCount, 1)
        XCTAssertEqual(tokenFetcher.requestedSessionIDs, [sessionID.uuidString])
        XCTAssertEqual(room.lastConnectURL, "wss://example.livekit.cloud")
        XCTAssertEqual(room.lastConnectToken, "test-token")
        XCTAssertEqual(audio.enterCallCount, 1, "join must enter voice mode exactly once")
        XCTAssertTrue(audio.isInVoiceMode)
    }

    /// Fix wave 1 (reviewer Finding F3a): the OLD contract treated
    /// already-`.connected` as an unconditional no-op regardless of WHICH
    /// session that connection was for — this test used to lock exactly
    /// that (two different `UUID()`s, still asserting `connectCallCount ==
    /// 1`). The NEW contract only no-ops on a SAME-session re-entrant call
    /// (LobbyView -> GroupSessionLiveView's deliberate re-call across that
    /// push, letting the room persist); a DIFFERENT-session call now
    /// re-joins instead — covered separately by
    /// `testJoinForDifferentSessionWhileConnectedLeavesThenReconnects` below.
    func testJoinIsNoOpWhileAlreadyConnectedToSameSession() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )

        let sessionID = UUID()
        await service.join(sessionID: sessionID)
        XCTAssertEqual(room.connectCallCount, 1)

        await service.join(sessionID: sessionID) // SAME session, already connected
        XCTAssertEqual(room.connectCallCount, 1, "must not re-join for the same session while already connected")
        XCTAssertEqual(room.disconnectCallCount, 0, "a same-session re-entrant join must not route through leave()")
    }

    // MARK: - micDenied path

    func testJoinWithDeniedPermissionSetsMicDeniedAndSkipsRoom() async throws {
        let tokenFetcher = FakeTokenFetcher()
        let micPermission = FakeMicPermission()
        micPermission.granted = false
        let audio = SpyAudioSession()
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: micPermission, audioSession: audio, room: room
        )

        await service.join(sessionID: UUID())

        guard case .micDenied = service.state else {
            XCTFail("expected .micDenied, got \(service.state)"); return
        }
        XCTAssertEqual(room.connectCallCount, 0, "must not attempt to connect when mic permission is denied")
        XCTAssertEqual(tokenFetcher.requestedSessionIDs.count, 0, "must not fetch a token when mic permission is denied")
        XCTAssertEqual(audio.enterCallCount, 0, "must never enter voice mode when mic permission is denied")
    }

    // MARK: - invoke-failure -> unavailable + audio restored

    func testJoinTokenFetchFailureSetsUnavailableAndRestoresAudio() async throws {
        let tokenFetcher = FakeTokenFetcher()
        tokenFetcher.result = .failure(URLError(.notConnectedToInternet))
        let audio = SpyAudioSession()
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: FakeMicPermission(), audioSession: audio, room: room
        )

        await service.join(sessionID: UUID())

        guard case .unavailable = service.state else {
            XCTFail("expected .unavailable, got \(service.state)"); return
        }
        XCTAssertEqual(room.connectCallCount, 0, "must not attempt to connect when the token fetch itself fails")
        XCTAssertFalse(
            audio.isInVoiceMode,
            "audio session must be restored on token-fetch failure — the Edge Function isn't deployed yet (T5), so this is the failure path Task 3 can actually exercise pre-deploy"
        )
        XCTAssertEqual(audio.exitCallCount, 1, "failure path must exit voice mode exactly once")
    }

    func testJoinRoomConnectFailureSetsUnavailableAndRestoresAudio() async throws {
        let room = FakeRoomConnection()
        room.connectError = URLError(.timedOut)
        let audio = SpyAudioSession()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), audioSession: audio, room: room
        )

        await service.join(sessionID: UUID())

        guard case .unavailable = service.state else {
            XCTFail("expected .unavailable, got \(service.state)"); return
        }
        XCTAssertFalse(audio.isInVoiceMode)
    }

    func testRetryReRunsJoinOnceAfterUnavailable() async throws {
        let tokenFetcher = FakeTokenFetcher()
        tokenFetcher.result = .failure(URLError(.notConnectedToInternet))
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )

        let sessionID = UUID()
        await service.join(sessionID: sessionID)
        guard case .unavailable = service.state else { XCTFail("expected .unavailable"); return }

        tokenFetcher.result = .success(VoiceTokenResponse(token: "tok2", url: "wss://example.livekit.cloud"))
        await service.retry()

        guard case .connected(.muted) = service.state else {
            XCTFail("expected retry() to succeed and reach .connected(.muted), got \(service.state)")
            return
        }
        XCTAssertEqual(tokenFetcher.requestedSessionIDs, [sessionID.uuidString, sessionID.uuidString])
    }

    func testRetryIsNoOpWhenNotUnavailable() async throws {
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: FakeRoomConnection()
        )
        await service.retry() // never joined — must not crash or change state
        guard case .idle = service.state else { XCTFail("expected .idle, got \(service.state)"); return }
    }

    // MARK: - beginTransmit/endTransmit mute semantics

    func testBeginAndEndTransmitDriveMuteNotPublish() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())

        await service.beginTransmit()
        guard case .connected(.transmitting) = service.state else {
            XCTFail("expected .connected(.transmitting), got \(service.state)"); return
        }
        XCTAssertEqual(room.muteCalls, [false], "beginTransmit must unmute (false)")
        XCTAssertEqual(room.connectCallCount, 1, "beginTransmit must not reconnect/republish")

        await service.endTransmit()
        guard case .connected(.muted) = service.state else {
            XCTFail("expected .connected(.muted), got \(service.state)"); return
        }
        XCTAssertEqual(room.muteCalls, [false, true], "endTransmit must mute (true)")
    }

    func testBeginTransmitIsNoOpWhenNotConnected() async throws {
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: FakeRoomConnection()
        )
        await service.beginTransmit()
        guard case .idle = service.state else {
            XCTFail("beginTransmit must be a no-op while idle, got \(service.state)"); return
        }
    }

    func testEndTransmitIsNoOpWhenAlreadyMuted() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())
        await service.endTransmit() // already muted
        XCTAssertTrue(room.muteCalls.isEmpty, "endTransmit while already muted must not call setMicrophoneMuted")
    }

    func testBeginTransmitFailureKeepsStateMuted() async throws {
        let room = FakeRoomConnection()
        room.muteError = URLError(.timedOut)
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())
        await service.beginTransmit()
        guard case .connected(.muted) = service.state else {
            XCTFail("a failed unmute must not flip the UI to .transmitting, got \(service.state)")
            return
        }
    }

    func testEndTransmitAlwaysReturnsToMutedEvenOnMuteFailure() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())
        await service.beginTransmit()
        guard case .connected(.transmitting) = service.state else {
            XCTFail("setup: expected .connected(.transmitting)"); return
        }

        room.muteError = URLError(.timedOut)
        await service.endTransmit()
        guard case .connected(.muted) = service.state else {
            XCTFail("endTransmit must return to .muted even if the underlying mute call fails, got \(service.state)")
            return
        }
    }

    // MARK: - leave() restores audio + idle

    func testLeaveDisconnectsRestoresAudioAndReturnsIdle() async throws {
        let room = FakeRoomConnection()
        let audio = SpyAudioSession()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), audioSession: audio, room: room
        )
        await service.join(sessionID: UUID())
        XCTAssertTrue(audio.isInVoiceMode)

        await service.leave()

        guard case .idle = service.state else {
            XCTFail("expected .idle after leave(), got \(service.state)"); return
        }
        XCTAssertEqual(room.disconnectCallCount, 1)
        XCTAssertTrue(service.speakingParticipantIDs.isEmpty)
        XCTAssertFalse(audio.isInVoiceMode)
        XCTAssertEqual(audio.exitCallCount, 1, "leave must exit voice mode exactly once")
    }

    func testLeaveWithoutPriorJoinIsHarmless() async throws {
        let room = FakeRoomConnection()
        let audio = SpyAudioSession()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), audioSession: audio, room: room
        )
        await service.leave()
        guard case .idle = service.state else {
            XCTFail("expected .idle, got \(service.state)"); return
        }
        XCTAssertEqual(room.disconnectCallCount, 1)
        XCTAssertFalse(audio.isInVoiceMode)
    }

    func testJoinAfterLeaveCanReconnect() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())
        await service.leave()

        await service.join(sessionID: UUID())
        guard case .connected(.muted) = service.state else {
            XCTFail("expected re-join after leave() to succeed, got \(service.state)"); return
        }
        XCTAssertEqual(room.connectCallCount, 2)
    }

    // MARK: - leave(timeout:) (Phase O Task 5, item 1 — sign-out bound)

    /// A hung `room.disconnect()` must not block `leave(timeout:)` past its
    /// bound — the whole point of AuthService.signOut() using this over the
    /// plain `leave()`.
    func testLeaveTimeoutReturnsBoundedEvenIfDisconnectHangs() async throws {
        let room = PendingDisconnectRoom()
        let audio = SpyAudioSession()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), audioSession: audio, room: room
        )
        await service.join(sessionID: UUID())

        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await service.leave(timeout: .milliseconds(20))
        }

        XCTAssertLessThan(
            elapsed, .milliseconds(500),
            "leave(timeout:) must return promptly even if room.disconnect() never resolves"
        )
        // The underlying leave() is still parked on the hung disconnect() —
        // its defer (state = .idle, exitVoiceMode) hasn't run yet.
        guard case .connected = service.state else {
            XCTFail("timing out must not fabricate .idle before the real teardown finishes, got \(service.state)")
            return
        }
        XCTAssertTrue(audio.isInVoiceMode, "audio session must still be owned by the in-flight teardown, not reset early")

        // Let the hung disconnect() resolve — leave()'s own state
        // restoration must still land normally once it does; timing out
        // only stopped the CALLER from waiting, not the underlying teardown.
        room.resumeDisconnect()
        let restored = await settleUntil {
            if case .idle = service.state { return true }
            return false
        }
        XCTAssertTrue(restored, "leave()'s own state restoration must still land once the hung disconnect eventually resolves")
        XCTAssertFalse(audio.isInVoiceMode)
    }

    /// The happy path: `leave(timeout:)` behaves exactly like `leave()` when
    /// `room.disconnect()` finishes well within the bound.
    func testLeaveTimeoutBehavesLikePlainLeaveWhenDisconnectIsFast() async throws {
        let room = FakeRoomConnection()
        let audio = SpyAudioSession()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), audioSession: audio, room: room
        )
        await service.join(sessionID: UUID())

        await service.leave(timeout: .seconds(2))

        guard case .idle = service.state else {
            XCTFail("expected .idle after leave(timeout:), got \(service.state)"); return
        }
        XCTAssertEqual(room.disconnectCallCount, 1)
        XCTAssertFalse(audio.isInVoiceMode)
    }

    // MARK: - leave()/join() interleaving (epoch guard)

    /// leave() while join() is parked on the token fetch: the resumed join
    /// must not connect, must not overwrite .idle, and must not touch the
    /// audio session (leave already restored it).
    func testLeaveDuringJoinTokenFetchAbortsJoin() async throws {
        let tokenFetcher = PendingTokenFetcher()
        let audio = SpyAudioSession()
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: FakeMicPermission(), audioSession: audio, room: room
        )

        let joinTask = Task { await service.join(sessionID: UUID()) }
        let reached = await settleUntil { tokenFetcher.pending }
        XCTAssertTrue(reached, "join never reached the token fetch — test harness broken")

        await service.leave()
        XCTAssertEqual(audio.exitCallCount, 1, "leave restores the baseline")

        tokenFetcher.resume(.success(VoiceTokenResponse(token: "late", url: "wss://example.livekit.cloud")))
        await joinTask.value

        guard case .idle = service.state else {
            XCTFail("stale join resurrected state: \(service.state)"); return
        }
        XCTAssertEqual(room.connectCallCount, 0, "stale join must not connect")
        XCTAssertFalse(audio.isInVoiceMode)
        XCTAssertEqual(audio.exitCallCount, 1, "stale join must not exit again — leave() owns the baseline")
    }

    /// leave() while join() is parked INSIDE the connect: the resumed join
    /// must tear its own late-established connection back down.
    func testLeaveDuringJoinConnectDisconnectsStaleConnection() async throws {
        let room = PendingConnectRoom()
        let audio = SpyAudioSession()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), audioSession: audio, room: room
        )

        let joinTask = Task { await service.join(sessionID: UUID()) }
        let reached = await settleUntil { room.connectPending }
        XCTAssertTrue(reached, "join never reached connect — test harness broken")

        await service.leave()
        room.resumeConnect()
        await joinTask.value

        guard case .idle = service.state else {
            XCTFail("stale join resurrected state: \(service.state)"); return
        }
        XCTAssertEqual(room.disconnectCallCount, 2, "leave's disconnect + the stale join's own cleanup")
        XCTAssertFalse(audio.isInVoiceMode)
    }

    /// join() after a leave()-aborted join must work — the epoch guard kills
    /// stale flights, not the service.
    func testJoinAfterAbortedJoinReconnects() async throws {
        let tokenFetcher = PendingTokenFetcher()
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )

        let joinTask = Task { await service.join(sessionID: UUID()) }
        _ = await settleUntil { tokenFetcher.pending }
        await service.leave()
        tokenFetcher.resume(.failure(URLError(.cancelled)))
        await joinTask.value

        // Fresh join on the next epoch: the parked fetcher resolves
        // immediately this time.
        let sessionID = UUID()
        let secondJoin = Task { await service.join(sessionID: sessionID) }
        let pendingAgain = await settleUntil { tokenFetcher.pending }
        XCTAssertTrue(pendingAgain)
        tokenFetcher.resume(.success(VoiceTokenResponse(token: "tok", url: "wss://example.livekit.cloud")))
        await secondJoin.value

        guard case .connected(.muted) = service.state else {
            XCTFail("re-join after aborted join must succeed, got \(service.state)"); return
        }
        XCTAssertEqual(room.connectCallCount, 1)
    }

    // MARK: - join() session-scope guard (Phase O Task 5, item 3)

    /// join(A) is parked on the token fetch (a stale in-flight join, from a
    /// view/session the caller has since moved on from) when join(B) — a
    /// DIFFERENT session — arrives. Unlike
    /// `testJoinIsNoOpWhileAlreadyConnectedToSameSession` (which locks the
    /// SAME-session `.connected` no-op — Lobby -> live-session's deliberate
    /// same-session persistence; fix wave 1 renamed this from
    /// `testJoinIsNoOpWhileAlreadyConnected` once the mismatched-session
    /// case stopped being a no-op too, per Finding F3a), this is the
    /// `.connecting` case: A's flight must be treated as stale and torn
    /// down via the epoch guard, and B's own join must proceed and actually
    /// connect — never silently dropped, and never landing A's connection
    /// for the wrong session.
    func testJoinForDifferentSessionWhileConnectingAbortsStaleJoinAndConnectsNewSession() async throws {
        let tokenFetcher = MultiPendingTokenFetcher()
        let audio = SpyAudioSession()
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: FakeMicPermission(), audioSession: audio, room: room
        )

        let sessionA = UUID()
        let joinATask = Task { await service.join(sessionID: sessionA) }
        let aReached = await settleUntil { tokenFetcher.pendingSessionIDs.contains(sessionA.uuidString) }
        XCTAssertTrue(aReached, "join(A) never reached the token fetch — test harness broken")
        XCTAssertTrue(audio.isInVoiceMode, "join(A) must have entered voice mode before parking")

        // A different session's view now asks to join while A is still in
        // flight — must abort A (via leave()'s epoch bump) and start B.
        let sessionB = UUID()
        let joinBTask = Task { await service.join(sessionID: sessionB) }
        let bReached = await settleUntil { tokenFetcher.pendingSessionIDs.contains(sessionB.uuidString) }
        XCTAssertTrue(bReached, "join(B) never reached its own token fetch — the session-scope guard didn't tear A down and let B proceed")

        // Resolve A's (now-stale) fetch — it must recognize itself as stale
        // and stand down without ever connecting.
        tokenFetcher.resume(sessionID: sessionA.uuidString, .success(
            VoiceTokenResponse(token: "stale-a", url: "wss://example.livekit.cloud")
        ))
        await joinATask.value
        XCTAssertEqual(room.connectCallCount, 0, "stale join(A) must not connect once superseded")

        // Resolve B's fetch — it must proceed to a real connection.
        tokenFetcher.resume(sessionID: sessionB.uuidString, .success(
            VoiceTokenResponse(token: "fresh-b", url: "wss://example.livekit.cloud")
        ))
        await joinBTask.value

        guard case .connected(.muted) = service.state else {
            XCTFail("join(B) must land .connected(.muted) after superseding the stale A flight, got \(service.state)")
            return
        }
        XCTAssertEqual(room.connectCallCount, 1, "exactly one connection — B's, never A's")
        XCTAssertEqual(room.lastConnectToken, "fresh-b")
        XCTAssertEqual(tokenFetcher.requestedSessionIDs, [sessionA.uuidString, sessionB.uuidString])
        XCTAssertTrue(audio.isInVoiceMode)
    }

    /// join() called twice for the SAME session while the first is still
    /// `.connecting` must remain the existing idempotent no-op — the
    /// session-scope guard only engages on a MISMATCHED session id.
    func testJoinForSameSessionWhileConnectingRemainsNoOp() async throws {
        let tokenFetcher = PendingTokenFetcher()
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )

        let sessionID = UUID()
        let firstJoin = Task { await service.join(sessionID: sessionID) }
        _ = await settleUntil { tokenFetcher.pending }

        await service.join(sessionID: sessionID) // same session, still connecting — must no-op immediately
        guard case .connecting = service.state else {
            XCTFail("a same-session re-entrant join() must not have altered state, got \(service.state)")
            return
        }

        tokenFetcher.resume(.success(VoiceTokenResponse(token: "tok", url: "wss://example.livekit.cloud")))
        await firstJoin.value

        guard case .connected(.muted) = service.state else {
            XCTFail("expected .connected(.muted), got \(service.state)"); return
        }
        XCTAssertEqual(room.connectCallCount, 1, "the re-entrant same-session call must not have triggered a second connect")
    }

    /// Finding F3a (Phase O Task 5 fix wave 1): join() while already
    /// `.connected` used to be blind to WHICH session that connection was
    /// for — a join(B) arriving while `.connected` to A silently no-op'd,
    /// stranding the caller on the wrong room. Same treatment as item 3 gave
    /// the `.connecting` case above: `.connected` to a DIFFERENT session now
    /// routes through leave() first. Uses a `PendingDisconnectRoom` (same
    /// parked-continuation shape as `testLeaveDuringJoinConnectDisconnectsStaleConnection`)
    /// to verify the ORDERING guarantee, not just the end state: A's
    /// disconnect must be observably in flight — and B's own connect must
    /// NOT have happened yet — before A's teardown is allowed to resolve.
    func testJoinForDifferentSessionWhileConnectedLeavesThenReconnects() async throws {
        let room = PendingDisconnectRoom()
        let audio = SpyAudioSession()
        let tokenFetcher = FakeTokenFetcher()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: FakeMicPermission(), audioSession: audio, room: room
        )

        let sessionA = UUID()
        await service.join(sessionID: sessionA)
        guard case .connected(.muted) = service.state else {
            XCTFail("setup: expected .connected(.muted) for A, got \(service.state)"); return
        }

        let sessionB = UUID()
        let joinBTask = Task { await service.join(sessionID: sessionB) }
        let disconnectReached = await settleUntil { room.disconnectPending }
        XCTAssertTrue(disconnectReached, "join(B) never routed through leave()'s disconnect — test harness broken")
        XCTAssertEqual(room.disconnectCallCount, 1, "A's teardown, via the routed leave()")

        // A's disconnect must complete before B's own connect is attempted —
        // still .connected (not yet re-entered .connecting for B) while parked.
        guard case .connected = service.state else {
            XCTFail("state moved on before A's disconnect resolved: \(service.state)"); return
        }

        room.resumeDisconnect()
        await joinBTask.value

        guard case .connected(.muted) = service.state else {
            XCTFail("expected B to land .connected(.muted) after superseding A, got \(service.state)")
            return
        }
        XCTAssertEqual(room.disconnectCallCount, 1, "exactly one disconnect — A's, never a second spurious one")
        XCTAssertEqual(tokenFetcher.requestedSessionIDs, [sessionA.uuidString, sessionB.uuidString])
        XCTAssertTrue(audio.isInVoiceMode, "B's join must have re-entered voice mode")
    }

    // MARK: - leave() state-restore epoch-gating (Phase O Task 5 fix wave 1, Finding F3b)

    /// Dedicated fake for Finding F3b: the FIRST `disconnect()` call parks
    /// (simulating an abandoned, timed-out `leave()` whose underlying
    /// `room.disconnect()` never got a chance to resolve before the caller
    /// stopped waiting — the loser of `leave(timeout:)`'s race, left running
    /// in the background per that method's own doc comment) while every
    /// LATER call resolves immediately, mirroring a room that's otherwise
    /// healthy for whatever leave()/join() comes next. `connectAndPublishMuted`
    /// is always immediate; only disconnect()'s first call is special.
    @MainActor
    private final class LateResolvingDisconnectRoom: VoiceRoomConnecting {
        var onSpeakingParticipantsChanged: ((Set<String>) -> Void)?
        var onRosterChanged: ((Set<String>) -> Void)?
        var onRemoteMuteChanged: ((String, Bool) -> Void)?
        var onUnexpectedDisconnect: ((Error?) -> Void)?
        private var disconnectContinuation: CheckedContinuation<Void, Never>?
        private(set) var disconnectPending = false
        private(set) var disconnectCallCount = 0
        private(set) var connectCallCount = 0

        func connectAndPublishMuted(url: String, token: String) async throws {
            connectCallCount += 1
        }
        func setMicrophoneMuted(_ muted: Bool) async throws {}
        func setLocalVolume(_ volume: Double, forParticipantIdentity identity: String) async {}

        func disconnect() async {
            disconnectCallCount += 1
            guard disconnectCallCount == 1 else { return }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                disconnectContinuation = cont
                disconnectPending = true
            }
        }

        func resumeFirstDisconnect() {
            disconnectPending = false
            disconnectContinuation?.resume()
            disconnectContinuation = nil
        }
    }

    /// Finding F3b (Phase O Task 5 fix wave 1): an abandoned `leave()` (the
    /// loser of `leave(timeout:)`'s race, per that method's own doc comment)
    /// that resolves LATE must not clobber a NEWER session's state.
    /// Sequence: join A -> `.connected`; leave() for A starts but parks on
    /// `room.disconnect()` (the "abandoned" call, call #1); while still
    /// parked, join(B) arrives — per F3a, `.connected` with a mismatched
    /// session routes through its OWN leave() first (disconnect call #2,
    /// which this fake resolves immediately) before connecting to B. Only
    /// THEN does the original parked disconnect (call #1) resolve. Its
    /// leave() must recognize a newer epoch has superseded it and skip the
    /// state restore entirely — B's `.connected` state and voice-mode audio
    /// session must survive untouched.
    func testAbandonedLateLeaveDoesNotClobberNewerSessionState() async throws {
        let room = LateResolvingDisconnectRoom()
        let audio = SpyAudioSession()
        let tokenFetcher = FakeTokenFetcher()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: FakeMicPermission(), audioSession: audio, room: room
        )

        let sessionA = UUID()
        await service.join(sessionID: sessionA)
        guard case .connected = service.state else { XCTFail("setup: expected .connected for A"); return }

        // The "abandoned" leave — started but not awaited directly by this
        // test, mirroring leave(timeout:)'s loser continuing in the
        // background after the caller stops waiting.
        let abandonedLeave = Task { await service.leave() }
        let firstDisconnectReached = await settleUntil { room.disconnectPending }
        XCTAssertTrue(firstDisconnectReached, "abandoned leave never reached room.disconnect() — test harness broken")

        // A different session's join arrives while the abandoned leave is
        // still parked. state is still .connected (to A) at this instant —
        // the parked leave's defer hasn't run — so per F3a this routes
        // through its OWN leave() (disconnect call #2, resolved immediately
        // by the fake) before actually connecting to B.
        let sessionB = UUID()
        await service.join(sessionID: sessionB)

        guard case .connected(.muted) = service.state else {
            XCTFail("expected B to be .connected(.muted), got \(service.state)"); return
        }
        XCTAssertTrue(audio.isInVoiceMode, "B's voice mode must be active")
        let enterCountAfterB = audio.enterCallCount
        let exitCountAfterB = audio.exitCallCount

        // NOW let the original abandoned leave's disconnect (call #1)
        // resolve. Its captured epoch is stale (superseded by B's own
        // leave()+join) — its defer must skip the state restore entirely.
        room.resumeFirstDisconnect()
        await abandonedLeave.value

        guard case .connected(.muted) = service.state else {
            XCTFail("abandoned leave's late resolution clobbered B's state: \(service.state)"); return
        }
        XCTAssertTrue(audio.isInVoiceMode, "abandoned leave's late resolution must not have exited B's voice mode")
        XCTAssertEqual(audio.enterCallCount, enterCountAfterB, "no spurious re-enter from the stale leave")
        XCTAssertEqual(audio.exitCallCount, exitCountAfterB, "stale leave must not have called exitVoiceMode again")
        XCTAssertEqual(room.connectCallCount, 2, "A's connect + B's connect")
        XCTAssertEqual(room.disconnectCallCount, 2, "abandoned leave's disconnect (A) + B's own routed leave's disconnect")
    }

    // MARK: - Unexpected disconnect (Phase O Task 5 fix wave 2)
    //
    // `onUnexpectedDisconnect` models LiveKit's
    // `room(_:didDisconnectWithError:)` ("Client disconnected from the room
    // unexpectedly after a successful connection"). The protocol CONTRACT
    // says the conformer never fires it for an intentional teardown or a
    // stale/superseded connection generation — `LiveKitRoomConnection`
    // enforces that via a Room-identity gate that these hermetic fakes
    // cannot (and deliberately do not) model, since the whole point of the
    // seam is that the service knows nothing of Room generations. What IS
    // testable here is the service's side of the contract: the `.connected`
    // state guard (stale-epoch delivery filtered), the `.unavailable`
    // transition + audio restore + retry path, and the epoch bump that
    // stops a parked transmit call from resurrecting `.connected`.

    func testUnexpectedDisconnectWhileConnectedBecomesUnavailableAndRetryRejoins() async throws {
        let tokenFetcher = FakeTokenFetcher()
        let audio = SpyAudioSession()
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: FakeMicPermission(), audioSession: audio, room: room
        )

        let sessionID = UUID()
        await service.join(sessionID: sessionID)
        room.onRosterChanged?(["jordan-uuid"])
        room.onRemoteMuteChanged?("jordan-uuid", true)
        await service.setLocalMute(true, forParticipantIdentity: "jordan-uuid")
        room.onSpeakingParticipantsChanged?(["jordan-uuid"])

        room.onUnexpectedDisconnect?(URLError(.networkConnectionLost))

        guard case .unavailable = service.state else {
            XCTFail("expected .unavailable after an unexpected disconnect, got \(service.state)"); return
        }
        XCTAssertFalse(audio.isInVoiceMode, "ambient baseline must be restored — the room is gone")
        XCTAssertEqual(audio.exitCallCount, 1)
        XCTAssertTrue(service.speakingParticipantIDs.isEmpty, "dead room's speaking set must be cleared")
        XCTAssertTrue(service.connectedParticipantIDs.isEmpty, "dead room's roster must be cleared")
        XCTAssertTrue(service.remoteMutedParticipantIDs.isEmpty)
        XCTAssertTrue(service.locallyMutedParticipantIDs.isEmpty)

        // The whole point of .unavailable over .idle: the user gets a
        // manual retry, and retry() must still know WHICH session to
        // re-join (currentSessionID kept by the handler).
        await service.retry()
        guard case .connected(.muted) = service.state else {
            XCTFail("retry() after an unexpected disconnect must be able to re-join, got \(service.state)")
            return
        }
        XCTAssertEqual(tokenFetcher.requestedSessionIDs, [sessionID.uuidString, sessionID.uuidString])
        XCTAssertEqual(room.connectCallCount, 2)
        XCTAssertTrue(audio.isInVoiceMode)
    }

    /// LiveKit's `didDisconnectWithError` carries `LiveKitError?` — a nil
    /// error must still land `.unavailable` with a concrete `Error`
    /// (`VoiceRoomUnexpectedDisconnectError` fallback), since that state's
    /// associated value is non-optional by contract.
    func testUnexpectedDisconnectWithNilErrorStillMapsToUnavailable() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())

        room.onUnexpectedDisconnect?(nil)

        guard case .unavailable(let error) = service.state else {
            XCTFail("expected .unavailable even with a nil SDK error, got \(service.state)"); return
        }
        XCTAssertTrue(error is VoiceRoomUnexpectedDisconnectError, "nil SDK error must map to the dedicated fallback error")
    }

    func testUnexpectedDisconnectWhileIdleIsIgnored() async throws {
        let audio = SpyAudioSession()
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), audioSession: audio, room: room
        )

        room.onUnexpectedDisconnect?(URLError(.networkConnectionLost))

        guard case .idle = service.state else {
            XCTFail("an unexpected-disconnect event with no connection must be ignored, got \(service.state)"); return
        }
        XCTAssertEqual(audio.exitCallCount, 0, "must not touch the audio session it never entered")
    }

    /// A disconnect event arriving while a join is still `.connecting`
    /// (parked on its token fetch — parked-continuation pattern) belongs to
    /// no established connection and must not disturb the in-flight join.
    func testUnexpectedDisconnectWhileConnectingIsIgnored() async throws {
        let tokenFetcher = PendingTokenFetcher()
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )

        let joinTask = Task { await service.join(sessionID: UUID()) }
        let reached = await settleUntil { tokenFetcher.pending }
        XCTAssertTrue(reached, "join never reached the token fetch — test harness broken")

        room.onUnexpectedDisconnect?(URLError(.networkConnectionLost))
        guard case .connecting = service.state else {
            XCTFail("a disconnect event must not disturb a still-.connecting join, got \(service.state)"); return
        }

        tokenFetcher.resume(.success(VoiceTokenResponse(token: "tok", url: "wss://example.livekit.cloud")))
        await joinTask.value
        guard case .connected(.muted) = service.state else {
            XCTFail("the in-flight join must complete normally, got \(service.state)"); return
        }
    }

    /// The service-side analog of a stale-generation event: a late
    /// disconnect notification landing AFTER `leave()` already reset state.
    /// (A stale event landing after a NEWER session connected is filtered
    /// one layer down, by `LiveKitRoomConnection`'s Room-identity gate —
    /// see this section's MARK comment.)
    func testUnexpectedDisconnectAfterLeaveIsIgnored() async throws {
        let audio = SpyAudioSession()
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), audioSession: audio, room: room
        )
        await service.join(sessionID: UUID())
        await service.leave()
        XCTAssertEqual(audio.exitCallCount, 1)

        room.onUnexpectedDisconnect?(URLError(.networkConnectionLost))

        guard case .idle = service.state else {
            XCTFail("a late disconnect event after leave() must not overwrite .idle, got \(service.state)"); return
        }
        XCTAssertEqual(audio.exitCallCount, 1, "must not exit voice mode a second time")
    }

    /// Room whose `setMicrophoneMuted` PARKS until resumed — for proving
    /// `handleUnexpectedDisconnect`'s epoch bump. Same `@MainActor`/
    /// continuation-before-observable safety shape as `PendingConnectRoom`.
    @MainActor
    private final class PendingMuteRoom: VoiceRoomConnecting {
        var onSpeakingParticipantsChanged: ((Set<String>) -> Void)?
        var onRosterChanged: ((Set<String>) -> Void)?
        var onRemoteMuteChanged: ((String, Bool) -> Void)?
        var onUnexpectedDisconnect: ((Error?) -> Void)?
        private var muteContinuation: CheckedContinuation<Void, Never>?
        private(set) var mutePending = false

        func connectAndPublishMuted(url: String, token: String) async throws {}
        func setLocalVolume(_ volume: Double, forParticipantIdentity identity: String) async {}
        func disconnect() async {}

        func setMicrophoneMuted(_ muted: Bool) async throws {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                muteContinuation = cont
                mutePending = true
            }
        }

        func resumeMute() {
            mutePending = false
            muteContinuation?.resume()
            muteContinuation = nil
        }
    }

    /// The epoch bump in `handleUnexpectedDisconnect` is load-bearing:
    /// without it, a `beginTransmit()` parked on its unmute await when the
    /// transport dies would resume, pass its own epoch check, and resurrect
    /// `.connected(.transmitting)` OVER the `.unavailable` the handler just
    /// set — a zombie state pointing at a dead room. Same discipline
    /// `leave()` already established for its own interleavings.
    func testUnexpectedDisconnectWhileTransmitCallParkedDoesNotResurrectConnected() async throws {
        let room = PendingMuteRoom()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())
        guard case .connected(.muted) = service.state else {
            XCTFail("setup: expected .connected(.muted)"); return
        }

        let transmitTask = Task { await service.beginTransmit() }
        let reached = await settleUntil { room.mutePending }
        XCTAssertTrue(reached, "beginTransmit never reached its unmute call — test harness broken")

        room.onUnexpectedDisconnect?(URLError(.networkConnectionLost))
        guard case .unavailable = service.state else {
            XCTFail("expected .unavailable, got \(service.state)"); return
        }

        room.resumeMute()
        await transmitTask.value

        guard case .unavailable = service.state else {
            XCTFail("resumed transmit call resurrected state over .unavailable: \(service.state)"); return
        }
    }

    // MARK: - Active speakers

    func testSpeakingParticipantsChangedCallbackUpdatesPublishedSet() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())

        XCTAssertTrue(service.speakingParticipantIDs.isEmpty)

        let identities: Set<String> = ["user-a-uuid", "user-b-uuid"]
        room.onSpeakingParticipantsChanged?(identities)

        XCTAssertEqual(service.speakingParticipantIDs, identities)
    }

    // MARK: - Roster / mute surface (Phase O Task 5, items 4 and 5)

    func testRosterChangedCallbackUpdatesConnectedParticipantIDs() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())

        XCTAssertTrue(service.connectedParticipantIDs.isEmpty)

        let roster: Set<String> = ["jordan-uuid", "sam-uuid"]
        room.onRosterChanged?(roster)

        XCTAssertEqual(service.connectedParticipantIDs, roster)
    }

    func testRemoteMuteChangedCallbackTracksPerParticipantMuteState() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())
        room.onRosterChanged?(["jordan-uuid", "sam-uuid"])

        room.onRemoteMuteChanged?("jordan-uuid", true)
        XCTAssertEqual(service.remoteMutedParticipantIDs, ["jordan-uuid"])

        room.onRemoteMuteChanged?("sam-uuid", true)
        XCTAssertEqual(service.remoteMutedParticipantIDs, ["jordan-uuid", "sam-uuid"])

        room.onRemoteMuteChanged?("jordan-uuid", false)
        XCTAssertEqual(service.remoteMutedParticipantIDs, ["sam-uuid"])
    }

    /// A participant leaving the room must drop out of BOTH derived mute
    /// sets — a reconnecting participant (or someone else later reusing
    /// that identity string within the same process, however unlikely)
    /// must not inherit a stale muted badge from a previous stint.
    func testRosterChangedPrunesStaleMuteStateForDepartedParticipants() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())
        room.onRosterChanged?(["jordan-uuid", "sam-uuid"])
        room.onRemoteMuteChanged?("jordan-uuid", true)
        await service.setLocalMute(true, forParticipantIdentity: "sam-uuid")

        XCTAssertEqual(service.remoteMutedParticipantIDs, ["jordan-uuid"])
        XCTAssertEqual(service.locallyMutedParticipantIDs, ["sam-uuid"])

        // Jordan leaves; Sam remains.
        room.onRosterChanged?(["sam-uuid"])

        XCTAssertEqual(service.connectedParticipantIDs, ["sam-uuid"])
        XCTAssertTrue(service.remoteMutedParticipantIDs.isEmpty, "departed participant must be pruned from remote-mute state")
        XCTAssertEqual(service.locallyMutedParticipantIDs, ["sam-uuid"], "a still-present participant's local mute must survive an unrelated roster change")
    }

    func testSetLocalMuteCallsRoomVolumeAndTracksState() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())
        room.onRosterChanged?(["jordan-uuid"])

        await service.setLocalMute(true, forParticipantIdentity: "jordan-uuid")
        XCTAssertEqual(service.locallyMutedParticipantIDs, ["jordan-uuid"])
        XCTAssertEqual(room.localVolumeCalls.count, 1)
        XCTAssertEqual(room.localVolumeCalls.last?.volume, 0)
        XCTAssertEqual(room.localVolumeCalls.last?.identity, "jordan-uuid")

        await service.setLocalMute(false, forParticipantIdentity: "jordan-uuid")
        XCTAssertTrue(service.locallyMutedParticipantIDs.isEmpty)
        XCTAssertEqual(room.localVolumeCalls.count, 2)
        XCTAssertEqual(room.localVolumeCalls.last?.volume, 1)
    }

    func testSetLocalMuteIsNoOpForParticipantNotInRoom() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())
        room.onRosterChanged?(["jordan-uuid"])

        await service.setLocalMute(true, forParticipantIdentity: "nobody-here-uuid")

        XCTAssertTrue(room.localVolumeCalls.isEmpty, "must not call through to the room for an identity that isn't in the roster")
        XCTAssertTrue(service.locallyMutedParticipantIDs.isEmpty)
    }

    func testSetLocalMuteIsNoOpWhenNotConnected() async throws {
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: FakeRoomConnection()
        )
        await service.setLocalMute(true, forParticipantIdentity: "jordan-uuid")
        guard case .idle = service.state else {
            XCTFail("setLocalMute must be a no-op while idle, got \(service.state)"); return
        }
    }

    /// `leave()` must clear the roster and both derived mute sets — a
    /// later join() into a fresh room must never carry over state from a
    /// previous room's participants.
    func testLeaveClearsRosterAndMuteState() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(),
            audioSession: SpyAudioSession(), room: room
        )
        await service.join(sessionID: UUID())
        room.onRosterChanged?(["jordan-uuid"])
        room.onRemoteMuteChanged?("jordan-uuid", true)
        await service.setLocalMute(true, forParticipantIdentity: "jordan-uuid")

        await service.leave()

        XCTAssertTrue(service.connectedParticipantIDs.isEmpty)
        XCTAssertTrue(service.remoteMutedParticipantIDs.isEmpty)
        XCTAssertTrue(service.locallyMutedParticipantIDs.isEmpty)
    }
}
