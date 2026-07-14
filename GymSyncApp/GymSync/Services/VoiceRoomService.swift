import AVFoundation
import Foundation

/// Room-scoped LiveKit voice state, mirrored 1:1 to the PTT dock's 5 button
/// variants (Dossier §A.2) and the join lifecycle (Dossier §A.1's locked
/// decisions). `.unavailable` carries the underlying failure — the UI
/// contract (task brief) is just a small "voice unavailable" pill + one
/// manual retry, never an automatic retry loop.
enum VoiceRoomState {
    case idle
    case connecting
    case connected(TransmitState)
    case unavailable(Error)
    case micDenied
}

/// Sub-state of `.connected` — whether the published mic track is currently
/// muted (listen-only, the default immediately after join) or transmitting
/// (unmuted, held).
enum TransmitState {
    case muted
    case transmitting
}

// MARK: - Token fetch seam

/// The token-fetch response shape `livekit-token` returns on success
/// (`supabase/functions/livekit-token/index.ts:167`): `{ token, url }`.
struct VoiceTokenResponse: Decodable, Sendable {
    let token: String
    let url: String
}

/// Abstracts the `livekit-token` Edge Function round trip so
/// `VoiceRoomService`'s join/retry/failure-mapping logic is unit-testable
/// without a live Supabase project. The function isn't deployed yet (T5
/// does that) — Task 3 must work with zero live-network access, so this
/// seam is what makes the invoke-failure path hermetically testable.
protocol VoiceTokenFetching {
    func fetchToken(sessionID: String) async throws -> VoiceTokenResponse
}

/// Production `VoiceTokenFetching` conformer. `client.functions.invoke`
/// forwards the signed-in user's Supabase JWT automatically (supabase-swift
/// behavior, confirmed Dossier §B.5) — no manual Authorization header
/// needed, matching how `livekit-token/index.ts` authenticates the caller.
///
/// ASSUMPTION (not verified against the vendored `Supabase` package source —
/// no Mac/Xcode this session): `FunctionsClient.invoke<T: Decodable>(_:options:)`
/// exists with this generic-decode shape and `FunctionInvokeOptions.init(body:)`
/// accepts any `Encodable`. This mirrors supabase-swift's documented usage
/// pattern. If CI's build-test job fails to compile here, this is the first
/// place to check.
struct SupabaseVoiceTokenFetcher: VoiceTokenFetching {
    private struct RequestBody: Encodable {
        let session_id: String
    }

    func fetchToken(sessionID: String) async throws -> VoiceTokenResponse {
        try await SupabaseService.shared.client.functions.invoke(
            "livekit-token",
            options: .init(body: RequestBody(session_id: sessionID))
        )
    }
}

// MARK: - Mic permission seam

/// Abstracts mic-permission status/request so the `.micDenied` path is
/// unit-testable — the real system prompt (`AVAudioApplication`) isn't
/// something a hermetic test can drive deterministically in CI (permission
/// state depends on the simulator/CI environment's TCC database, not
/// anything the test controls).
protocol MicPermissionChecking {
    /// Mirrors 3c's `VoiceRecorder.startRecording()` pattern exactly: shows
    /// the system prompt if undetermined, returns the current status
    /// immediately (no prompt) if already decided. `join()` calls this once
    /// per attempt — no request storm, since `join()` itself is only ever
    /// invoked once per session-enter (and once per `retry()`).
    func requestRecordPermission() async -> Bool
}

struct SystemMicPermissionChecker: MicPermissionChecking {
    func requestRecordPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

// MARK: - Room seam

/// Abstracts the LiveKit `Room` surface `VoiceRoomService` drives (connect +
/// publish-muted, mute/unmute, disconnect, active-speaker events) so the
/// service's state machine is unit-testable without linking LiveKit,
/// touching the network, or opening real audio hardware. The production
/// conformer is `LiveKitRoomConnection` (`Services/LiveKitRoomConnection.swift`);
/// tests supply a fake and never `import LiveKit`.
protocol VoiceRoomConnecting: AnyObject {
    /// Set once by `VoiceRoomService` right after construction. Fired with
    /// the full current set of speaking identities (LiveKit identity = user
    /// UUID string, per T1's token `sub` claim) whenever LiveKit's
    /// `RoomDelegate.room(_:didUpdateSpeakingParticipants:)` fires.
    var onSpeakingParticipantsChanged: ((Set<String>) -> Void)? { get set }

    /// Connects to `url` with `token` and publishes the mic track muted.
    /// Throws on any failure — token rejected, network, SDK-level error.
    func connectAndPublishMuted(url: String, token: String) async throws

    /// Mutes/unmutes the already-published mic track. NOT publish/unpublish
    /// — mute/unmute is the low-latency path for hold-to-talk (Dossier
    /// §B.4/§B.3.5).
    func setMicrophoneMuted(_ muted: Bool) async throws

    /// Disconnects the room. Best-effort — never throws; `leave()` must
    /// always be able to restore audio/state regardless of network state.
    func disconnect() async
}

// MARK: - VoiceRoomService

/// LiveKit room lifecycle for a single voice-eligible session, under our own
/// owned `AVAudioSession` scope (Dossier §B.3).
///
/// **Shape**: singleton (`.shared`) with reference semantics — one room
/// connection exists at a time for the signed-in user, matching the spec's
/// 1:1 session<->room mapping and "no persistent group channels" (Dossier
/// §A.1). `join(sessionID:)`/`leave()` are call-and-response, not tied to
/// any one view's lifetime, so LobbyView and GroupSessionLiveView can both
/// drive the same instance across a session's lobby->live transition without
/// re-creating state (Task 4 wires the actual `.onAppear`/`.onDisappear`
/// hooks on top of this service). The initializer is deliberately NOT
/// private, unlike most `.shared` singletons in this codebase — production
/// code always goes through `.shared`; tests construct their own instance
/// with fake `tokenFetcher`/`micPermission`/`room` collaborators. There's no
/// existing in-repo precedent for this DI shape on an `@Observable`
/// singleton, so it's introduced here matching `livekit-token/index.ts`'s
/// own DI style (`HandleRequestDeps` as plain parameters, never reaching for
/// globals inside the testable logic).
@MainActor
@Observable
final class VoiceRoomService {
    static let shared = VoiceRoomService()

    private(set) var state: VoiceRoomState = .idle
    private(set) var speakingParticipantIDs: Set<String> = []

    private let tokenFetcher: VoiceTokenFetching
    private let micPermission: MicPermissionChecking
    private let audioSession: AudioSessionManager
    private let room: VoiceRoomConnecting
    private var currentSessionID: UUID?

    init(
        tokenFetcher: VoiceTokenFetching = SupabaseVoiceTokenFetcher(),
        micPermission: MicPermissionChecking = SystemMicPermissionChecker(),
        audioSession: AudioSessionManager = .shared,
        room: VoiceRoomConnecting = LiveKitRoomConnection()
    ) {
        self.tokenFetcher = tokenFetcher
        self.micPermission = micPermission
        self.audioSession = audioSession
        self.room = room
        self.room.onSpeakingParticipantsChanged = { [weak self] identities in
            self?.speakingParticipantIDs = identities
        }
    }

    /// Auto-join entry point (LobbyView/GroupSessionLiveView `.onAppear` —
    /// Task 4's wiring). No-op while already `.connecting`/`.connected` for a
    /// session (idempotent re-entry guard); safe to call again from `.idle`,
    /// `.unavailable`, or `.micDenied` (e.g. the user granted mic access in
    /// Settings and re-entered the lobby).
    ///
    /// Mic permission check happens FIRST, before any audio-session or
    /// network work — denied means `.micDenied` and nothing else happens.
    /// Every failure path past that point restores the ambient audio-session
    /// baseline via `defer` — the sacred-rules baseline (`.ambient +
    /// .mixWithOthers`) must never be left stuck on `.playAndRecord` because
    /// of a half-finished join.
    func join(sessionID: UUID) async {
        if case .connecting = state { return }
        if case .connected = state { return }

        currentSessionID = sessionID
        state = .connecting

        let granted = await micPermission.requestRecordPermission()
        guard granted else {
            state = .micDenied
            return
        }

        var joinSucceeded = false
        defer {
            if !joinSucceeded {
                audioSession.exitVoiceMode()
            }
        }

        do {
            try audioSession.enterVoiceMode()
            let response = try await tokenFetcher.fetchToken(sessionID: sessionID.uuidString)
            try await room.connectAndPublishMuted(url: response.url, token: response.token)
            state = .connected(.muted)
            joinSucceeded = true
        } catch {
            AppLogger.voice.error(
                "join failed for session \(sessionID.uuidString, privacy: .public): \(error, privacy: .public)"
            )
            state = .unavailable(error)
        }
    }

    /// Re-runs `join()` once for the last-attempted session. No-op unless
    /// currently `.unavailable` — no retry storms (task brief: "retry()
    /// re-runs join once").
    func retry() async {
        guard case .unavailable = state, let sessionID = currentSessionID else { return }
        state = .idle
        await join(sessionID: sessionID)
    }

    /// Hold-to-talk press. Unmutes the already-published mic track (NOT
    /// publish/unpublish — Dossier §B.4). No-op unless currently
    /// `.connected(.muted)`; a failed unmute leaves the state at `.muted`
    /// rather than lying to the UI about being live.
    func beginTransmit() async {
        guard case .connected(.muted) = state else { return }
        do {
            try await room.setMicrophoneMuted(false)
            state = .connected(.transmitting)
        } catch {
            AppLogger.voice.error("beginTransmit failed: \(error, privacy: .public)")
        }
    }

    /// Hold-to-talk release. Always returns to `.connected(.muted)`
    /// regardless of whether the underlying mute call succeeds — the UI must
    /// never keep showing "transmitting" once the user has released the
    /// button; a failed mute call is a logged reliability concern, not a
    /// reason to keep the button's visual state live. No-op unless currently
    /// `.connected(.transmitting)`.
    func endTransmit() async {
        guard case .connected(.transmitting) = state else { return }
        do {
            try await room.setMicrophoneMuted(true)
        } catch {
            AppLogger.voice.error("endTransmit failed: \(error, privacy: .public)")
        }
        state = .connected(.muted)
    }

    /// Disconnects and restores audio, unconditionally — guaranteed on
    /// session end, view dismiss (Task 4's `.onDisappear` wiring), and
    /// sign-out (`AuthService.signOut()` calls this before tearing down the
    /// Supabase session). Safe to call from `.idle` (never-joined) —
    /// `room.disconnect()`/`exitVoiceMode()` are both no-ops/idempotent in
    /// that case.
    func leave() async {
        defer {
            audioSession.exitVoiceMode()
            state = .idle
            currentSessionID = nil
            speakingParticipantIDs = []
        }
        await room.disconnect()
    }
}
