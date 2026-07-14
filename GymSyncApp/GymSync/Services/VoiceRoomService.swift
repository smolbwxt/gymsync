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

// MARK: - Audio session seam

/// Abstracts the `AudioSessionManager` voice-mode surface so
/// `VoiceRoomService`'s enter/exit discipline is hermetically testable
/// against a spy instead of process-global singleton state (the real
/// manager's `isInVoiceMode` flag survives across tests, so asserting on it
/// couples every test to run order — bitten on CI, task-3-report "CI round
/// 4"). The production conformer is the real `AudioSessionManager` via the
/// retroactive conformance below — it already exposes exactly this surface,
/// so the class itself (and its untouchable tests) is unchanged.
protocol VoiceAudioSessionManaging {
    var isInVoiceMode: Bool { get }
    func enterVoiceMode() throws
    func exitVoiceMode()
}

extension AudioSessionManager: VoiceAudioSessionManaging {}

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
    private let audioSession: VoiceAudioSessionManaging
    private let room: VoiceRoomConnecting
    private var currentSessionID: UUID?

    /// Monotonic lifecycle guard. `leave()` bumps it; `join()`/transmit
    /// re-check it after every suspension. Without this, a `leave()` that
    /// runs while `join()` is parked on the token fetch or the connect lets
    /// the resumed join re-enter voice mode, finish connecting, and
    /// overwrite `.idle` with `.connected` — a live room the caller believes
    /// it left. All access is MainActor-serialized, so an equality check
    /// between awaits is race-free.
    private var lifecycleEpoch = 0

    init(
        tokenFetcher: VoiceTokenFetching = SupabaseVoiceTokenFetcher(),
        micPermission: MicPermissionChecking = SystemMicPermissionChecker(),
        audioSession: VoiceAudioSessionManaging = AudioSessionManager.shared,
        room: VoiceRoomConnecting? = nil
    ) {
        self.tokenFetcher = tokenFetcher
        self.micPermission = micPermission
        self.audioSession = audioSession
        // `LiveKitRoomConnection()` is @MainActor-isolated (Dossier §B.4's
        // `Room`/`AudioManager` surface is iOS/visionOS/tvOS-only and this
        // adapter is written assuming MainActor). Constructing it here, in
        // the init BODY, rather than as the parameter's default-value
        // expression, is required: default-argument expressions are
        // evaluated in a synchronous nonisolated context even when the
        // enclosing initializer's type is @MainActor, so
        // `= LiveKitRoomConnection()` directly on the parameter fails to
        // compile ("call to main actor-isolated initializer in a
        // synchronous nonisolated context").
        self.room = room ?? LiveKitRoomConnection()
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

        let epoch = lifecycleEpoch
        currentSessionID = sessionID
        state = .connecting

        let granted = await micPermission.requestRecordPermission()
        // leave() ran while we were parked on the permission prompt: it
        // already reset state; nothing was entered yet, so just stop.
        guard lifecycleEpoch == epoch else { return }
        guard granted else {
            state = .micDenied
            return
        }

        var joinSucceeded = false
        defer {
            // Epoch-gated: if leave() interleaved, IT restored the baseline
            // (and a newer join may already own voice mode again) — a stale
            // join must not touch the audio session on its way out.
            if !joinSucceeded && lifecycleEpoch == epoch {
                audioSession.exitVoiceMode()
            }
        }

        do {
            try audioSession.enterVoiceMode()
            let response = try await tokenFetcher.fetchToken(sessionID: sessionID.uuidString)
            guard lifecycleEpoch == epoch else { return }
            try await room.connectAndPublishMuted(url: response.url, token: response.token)
            guard lifecycleEpoch == epoch else {
                // leave() interleaved while we were connecting — its
                // disconnect raced our in-flight connect, so undo the
                // connection this stale join just established.
                await room.disconnect()
                return
            }
            state = .connected(.muted)
            joinSucceeded = true
        } catch {
            AppLogger.voice.error(
                "join failed for session \(sessionID.uuidString, privacy: .public): \(error, privacy: .public)"
            )
            // A stale join's failure belongs to a lifecycle the user already
            // left — don't overwrite whatever state the current epoch set.
            guard lifecycleEpoch == epoch else { return }
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
        let epoch = lifecycleEpoch
        do {
            try await room.setMicrophoneMuted(false)
            // leave() interleaved with the unmute — the room is gone; don't
            // resurrect a .connected state over the epoch owner's .idle.
            guard lifecycleEpoch == epoch else { return }
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
        let epoch = lifecycleEpoch
        do {
            try await room.setMicrophoneMuted(true)
        } catch {
            AppLogger.voice.error("endTransmit failed: \(error, privacy: .public)")
        }
        // Same epoch discipline as beginTransmit: a leave() that interleaved
        // with the mute call owns the state now.
        guard lifecycleEpoch == epoch else { return }
        state = .connected(.muted)
    }

    /// Disconnects and restores audio, unconditionally — guaranteed on
    /// session end, view dismiss (Task 4's `.onDisappear` wiring), and
    /// sign-out (`AuthService.signOut()` calls this before tearing down the
    /// Supabase session). Safe to call from `.idle` (never-joined) —
    /// `room.disconnect()`/`exitVoiceMode()` are both no-ops/idempotent in
    /// that case. Also invalidates any in-flight `join()`/transmit call via
    /// `lifecycleEpoch` — a suspended join that resumes after this cannot
    /// reconnect or overwrite the `.idle` state.
    func leave() async {
        lifecycleEpoch += 1
        defer {
            audioSession.exitVoiceMode()
            state = .idle
            currentSessionID = nil
            speakingParticipantIDs = []
        }
        await room.disconnect()
    }
}
