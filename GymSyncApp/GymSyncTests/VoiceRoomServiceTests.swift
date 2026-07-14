import XCTest
import AVFoundation
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
/// `AudioSessionManager.shared` is used directly (not faked) — it's already
/// cheaply hermetic on the simulator, exactly like `AudioSessionVoiceModeTests`,
/// so these tests get real audio-session-restoration verification for free
/// rather than trusting a mock's bookkeeping.
@MainActor
final class VoiceRoomServiceTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        try AudioSessionManager.shared.configure()
    }

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

    private final class FakeRoomConnection: VoiceRoomConnecting {
        var onSpeakingParticipantsChanged: ((Set<String>) -> Void)?

        var connectError: Error?
        private(set) var connectCallCount = 0
        private(set) var lastConnectURL: String?
        private(set) var lastConnectToken: String?

        var muteError: Error?
        private(set) var muteCalls: [Bool] = []

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

        func disconnect() async {
            disconnectCallCount += 1
        }
    }

    // MARK: - State transitions: idle -> connecting -> connected(muted)

    func testJoinTransitionsThroughConnectingToConnectedMuted() async throws {
        let tokenFetcher = FakeTokenFetcher()
        let micPermission = RecordingMicPermission()
        let room = FakeRoomConnection()
        let service = VoiceRoomService(tokenFetcher: tokenFetcher, micPermission: micPermission, room: room)

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
        XCTAssertTrue(AudioSessionManager.shared.isInVoiceMode)
    }

    func testJoinIsNoOpWhileAlreadyConnected() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), room: room
        )

        await service.join(sessionID: UUID())
        XCTAssertEqual(room.connectCallCount, 1)

        await service.join(sessionID: UUID()) // different session, already connected
        XCTAssertEqual(room.connectCallCount, 1, "must not re-join while already connected")
    }

    // MARK: - micDenied path

    func testJoinWithDeniedPermissionSetsMicDeniedAndSkipsRoom() async throws {
        let tokenFetcher = FakeTokenFetcher()
        let micPermission = FakeMicPermission()
        micPermission.granted = false
        let room = FakeRoomConnection()
        let service = VoiceRoomService(tokenFetcher: tokenFetcher, micPermission: micPermission, room: room)

        await service.join(sessionID: UUID())

        guard case .micDenied = service.state else {
            XCTFail("expected .micDenied, got \(service.state)"); return
        }
        XCTAssertEqual(room.connectCallCount, 0, "must not attempt to connect when mic permission is denied")
        XCTAssertEqual(tokenFetcher.requestedSessionIDs.count, 0, "must not fetch a token when mic permission is denied")
        XCTAssertFalse(AudioSessionManager.shared.isInVoiceMode, "must never enter voice mode when mic permission is denied")
    }

    // MARK: - invoke-failure -> unavailable + audio restored

    func testJoinTokenFetchFailureSetsUnavailableAndRestoresAudio() async throws {
        let tokenFetcher = FakeTokenFetcher()
        tokenFetcher.result = .failure(URLError(.notConnectedToInternet))
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: FakeMicPermission(), room: room
        )

        await service.join(sessionID: UUID())

        guard case .unavailable = service.state else {
            XCTFail("expected .unavailable, got \(service.state)"); return
        }
        XCTAssertEqual(room.connectCallCount, 0, "must not attempt to connect when the token fetch itself fails")
        XCTAssertFalse(
            AudioSessionManager.shared.isInVoiceMode,
            "audio session must be restored to ambient on token-fetch failure — the Edge Function isn't deployed yet (T5), so this is the failure path Task 3 can actually exercise pre-deploy"
        )
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .ambient)
        XCTAssertTrue(AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers))
    }

    func testJoinRoomConnectFailureSetsUnavailableAndRestoresAudio() async throws {
        let room = FakeRoomConnection()
        room.connectError = URLError(.timedOut)
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), room: room
        )

        await service.join(sessionID: UUID())

        guard case .unavailable = service.state else {
            XCTFail("expected .unavailable, got \(service.state)"); return
        }
        XCTAssertFalse(AudioSessionManager.shared.isInVoiceMode)
    }

    func testRetryReRunsJoinOnceAfterUnavailable() async throws {
        let tokenFetcher = FakeTokenFetcher()
        tokenFetcher.result = .failure(URLError(.notConnectedToInternet))
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: tokenFetcher, micPermission: FakeMicPermission(), room: room
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
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), room: FakeRoomConnection()
        )
        await service.retry() // never joined — must not crash or change state
        guard case .idle = service.state else { XCTFail("expected .idle, got \(service.state)"); return }
    }

    // MARK: - beginTransmit/endTransmit mute semantics

    func testBeginAndEndTransmitDriveMuteNotPublish() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), room: room
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
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), room: FakeRoomConnection()
        )
        await service.beginTransmit()
        guard case .idle = service.state else {
            XCTFail("beginTransmit must be a no-op while idle, got \(service.state)"); return
        }
    }

    func testEndTransmitIsNoOpWhenAlreadyMuted() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), room: room
        )
        await service.join(sessionID: UUID())
        await service.endTransmit() // already muted
        XCTAssertTrue(room.muteCalls.isEmpty, "endTransmit while already muted must not call setMicrophoneMuted")
    }

    func testBeginTransmitFailureKeepsStateMuted() async throws {
        let room = FakeRoomConnection()
        room.muteError = URLError(.timedOut)
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), room: room
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
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), room: room
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
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), room: room
        )
        await service.join(sessionID: UUID())
        XCTAssertTrue(AudioSessionManager.shared.isInVoiceMode)

        await service.leave()

        guard case .idle = service.state else {
            XCTFail("expected .idle after leave(), got \(service.state)"); return
        }
        XCTAssertEqual(room.disconnectCallCount, 1)
        XCTAssertTrue(service.speakingParticipantIDs.isEmpty)
        XCTAssertFalse(AudioSessionManager.shared.isInVoiceMode)
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .ambient)
        XCTAssertTrue(AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers))
    }

    func testLeaveWithoutPriorJoinIsHarmless() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), room: room
        )
        await service.leave()
        guard case .idle = service.state else {
            XCTFail("expected .idle, got \(service.state)"); return
        }
        XCTAssertEqual(room.disconnectCallCount, 1)
        XCTAssertFalse(AudioSessionManager.shared.isInVoiceMode)
    }

    func testJoinAfterLeaveCanReconnect() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), room: room
        )
        await service.join(sessionID: UUID())
        await service.leave()

        await service.join(sessionID: UUID())
        guard case .connected(.muted) = service.state else {
            XCTFail("expected re-join after leave() to succeed, got \(service.state)"); return
        }
        XCTAssertEqual(room.connectCallCount, 2)
    }

    // MARK: - Active speakers

    func testSpeakingParticipantsChangedCallbackUpdatesPublishedSet() async throws {
        let room = FakeRoomConnection()
        let service = VoiceRoomService(
            tokenFetcher: FakeTokenFetcher(), micPermission: FakeMicPermission(), room: room
        )
        await service.join(sessionID: UUID())

        XCTAssertTrue(service.speakingParticipantIDs.isEmpty)

        let identities: Set<String> = ["user-a-uuid", "user-b-uuid"]
        room.onSpeakingParticipantsChanged?(identities)

        XCTAssertEqual(service.speakingParticipantIDs, identities)
    }
}
