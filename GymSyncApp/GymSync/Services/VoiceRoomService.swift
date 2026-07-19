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

    /// Set once by `VoiceRoomService` right after construction. Fired with
    /// the full current set of REMOTE participant identities in the room
    /// (self excluded, same lowercased-UUID-string identity shape as
    /// `onSpeakingParticipantsChanged`) whenever a participant joins or
    /// leaves. Phase O Task 5 (3e follow-up queue item 4, "muted-others
    /// roster rows" — the ledger's own "needs room-roster service surface"
    /// note): `VoiceRoomService` previously exposed no roster at all, so
    /// callers couldn't tell "not speaking" apart from "not even in the
    /// room."
    var onRosterChanged: ((Set<String>) -> Void)? { get set }

    /// Set once by `VoiceRoomService` right after construction. Fired with
    /// `(identity, isMuted)` whenever a REMOTE participant's OWN published
    /// mic track's mute state changes (they muted/unmuted themselves) —
    /// distinct from `setLocalVolume`'s muted-BY-YOU below, which is a pure
    /// local override nobody else observes.
    var onRemoteMuteChanged: ((String, Bool) -> Void)? { get set }

    /// Connects to `url` with `token` and publishes the mic track muted.
    /// Throws on any failure — token rejected, network, SDK-level error.
    func connectAndPublishMuted(url: String, token: String) async throws

    /// Mutes/unmutes the already-published mic track. NOT publish/unpublish
    /// — mute/unmute is the low-latency path for hold-to-talk (Dossier
    /// §B.4/§B.3.5).
    func setMicrophoneMuted(_ muted: Bool) async throws

    /// Sets LOCAL playback volume (0...1) for one remote participant's
    /// audio — client-side only; doesn't touch what they publish or what
    /// anyone else hears. Powers the voice mixer sheet's per-person
    /// "tap to mute" (volume 0) and level control (Phase O Task 5 item 5).
    /// Best-effort — never throws; a failed volume change degrades to "the
    /// mixer's mute toggle didn't take" (device-QA-visible), never a torn
    /// room. No-op for an identity that isn't currently in the room.
    func setLocalVolume(_ volume: Double, forParticipantIdentity identity: String) async

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

    /// REMOTE participants currently in the room (self excluded). Phase O
    /// Task 5 item 4 — the roster surface `PTTDockRow`'s roster rows and
    /// the voice mixer sheet both need to tell "not speaking" apart from
    /// "not even in the room."
    private(set) var connectedParticipantIDs: Set<String> = []
    /// Subset of `connectedParticipantIDs` who have muted THEIR OWN mic
    /// (LiveKit publish-mute state — a fact about them, visible to
    /// everyone in the room, not just you).
    private(set) var remoteMutedParticipantIDs: Set<String> = []
    /// Subset of `connectedParticipantIDs` YOU have locally silenced via
    /// the voice mixer sheet (`setLocalMute`) — a pure client-side
    /// override nobody else observes, distinct from
    /// `remoteMutedParticipantIDs` above.
    private(set) var locallyMutedParticipantIDs: Set<String> = []

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
        self.room.onRosterChanged = { [weak self] identities in
            guard let self else { return }
            self.connectedParticipantIDs = identities
            // A participant who left the room can no longer be "muted" in
            // either sense — drop them from both derived sets so a
            // reconnecting participant starts from a clean slate rather
            // than inheriting a stale badge from their previous stint.
            self.remoteMutedParticipantIDs.formIntersection(identities)
            self.locallyMutedParticipantIDs.formIntersection(identities)
        }
        self.room.onRemoteMuteChanged = { [weak self] identity, isMuted in
            guard let self else { return }
            if isMuted {
                self.remoteMutedParticipantIDs.insert(identity)
            } else {
                self.remoteMutedParticipantIDs.remove(identity)
            }
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
        // Phase O Task 5 (3e follow-up queue item 3, "join session-scope
        // guard"): the two no-op guards below are SESSION-BLIND — they
        // treat "already connecting/connected" as reason enough to return,
        // regardless of which session that flight is FOR. That's correct
        // (and load-bearing — `testJoinIsNoOpWhileAlreadyConnected` locks
        // it) once already `.connected`: LobbyView -> GroupSessionLiveView
        // deliberately re-calls join() for the SAME session to let the room
        // persist across that push, and a second view's spurious call with
        // a stale/different id must not steal or duplicate that connection.
        // But while still `.connecting` FOR A DIFFERENT SESSION, that
        // in-flight join is stale relative to THIS call — if left alone it
        // can still land its own connect a moment later and silently
        // establish the WRONG session's room. Extend the SAME
        // `lifecycleEpoch` machinery `leave()` already uses to guard
        // resumption-after-suspension (see that var's doc comment): route
        // through `leave()` here too, which bumps the epoch, disconnects
        // whatever the stale flight has connected so far (nothing yet, at
        // this point), and resets state to `.idle` — so when the stale
        // join resumes past its next epoch check (right after the token
        // fetch, or right after connect), it recognizes itself as stale and
        // stands down exactly like a leave()-during-join race today.
        if case .connecting = state, currentSessionID != sessionID {
            await leave()
        }
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

    /// Voice mixer sheet's per-person "tap to mute" (Phase O Task 5, item
    /// 5) — a pure LOCAL playback override, never touching what `identity`
    /// publishes or what anyone else in the room hears. No-op unless
    /// currently connected AND `identity` is actually in the room —
    /// silently dropping a stale toggle for someone who already left is
    /// safer than surfacing an error for a UI action that's already moot.
    func setLocalMute(_ muted: Bool, forParticipantIdentity identity: String) async {
        guard case .connected = state, connectedParticipantIDs.contains(identity) else { return }
        await room.setLocalVolume(muted ? 0 : 1, forParticipantIdentity: identity)
        if muted {
            locallyMutedParticipantIDs.insert(identity)
        } else {
            locallyMutedParticipantIDs.remove(identity)
        }
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
    /// session end and view dismiss (Task 4's `.onDisappear` wiring). Safe
    /// to call from `.idle` (never-joined) — `room.disconnect()`/
    /// `exitVoiceMode()` are both no-ops/idempotent in that case. Also
    /// invalidates any in-flight `join()`/transmit call via
    /// `lifecycleEpoch` — a suspended join that resumes after this cannot
    /// reconnect or overwrite the `.idle` state. `AuthService.signOut()`
    /// calls `leave(timeout:)` below instead of this directly (Phase O
    /// Task 5, 3e follow-up queue item 1) — sign-out must never hang on a
    /// wedged `room.disconnect()`.
    func leave() async {
        lifecycleEpoch += 1
        defer {
            audioSession.exitVoiceMode()
            state = .idle
            currentSessionID = nil
            speakingParticipantIDs = []
            // Phase O Task 5 item 4/5: the roster and both derived mute sets
            // are meaningless once the room is gone — a later join() into a
            // fresh room must start from an empty roster, not carry over
            // whoever was in the PREVIOUS room.
            connectedParticipantIDs = []
            remoteMutedParticipantIDs = []
            locallyMutedParticipantIDs = []
        }
        await room.disconnect()
    }

    /// `leave()`, bounded to `timeout`. `room.disconnect()` is LiveKit's own
    /// network teardown — `leave()`'s contract says it "must always be able
    /// to restore audio/state" but makes no promise about HOW LONG that
    /// takes. Sign-out (`AuthService.signOut()`, the one caller of this
    /// method — Phase O Task 5, 3e follow-up queue item 1; final review's
    /// minor 4 flagged the previous unbounded duration as brief-sanctioned
    /// but worth revisiting) is a user-initiated action that must never
    /// hang on a wedged network teardown.
    ///
    /// Races the real `leave()` against a hard timeout — the same
    /// "whichever fires first wins" idiom `CheckInService.fetchLocation()`
    /// already establishes for its CLLocationManager-delegate-vs-timeout
    /// race (CheckInService.swift), adapted here for `leave()` vs a sleep.
    /// Both spawned `Task`s inherit this method's `@MainActor` isolation
    /// (this class is `@MainActor`), so `ContinuationBox`'s guard against a
    /// double-resume needs no lock — a single nil-check is race-free.
    ///
    /// Deliberately does NOT cancel the losing `leave()` call on timeout:
    /// LiveKit's `Room.disconnect()` isn't cancellation-aware and
    /// `leave()` itself never checks `Task.isCancelled`, so cancelling it
    /// would only set a flag nothing reads. The real `leave()` keeps
    /// running in the background and still restores state/audio via its
    /// own `defer` whenever `room.disconnect()` eventually resolves —
    /// timing out here means "the caller stops waiting," not "voice
    /// teardown was aborted."
    func leave(timeout: Duration) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let box = ContinuationBox(continuation)
            Task { @MainActor in
                await self.leave()
                box.resume()
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if box.resume() {
                    AppLogger.voice.error("leave(timeout:) exceeded its bound — caller is proceeding; teardown continues in the background")
                }
            }
        }
    }
}

/// MainActor-isolated single-resume guard for a `CheckedContinuation` two
/// independent unstructured `Task`s race to finish (Swift traps at runtime
/// on a double-resume). See `VoiceRoomService.leave(timeout:)`'s doc
/// comment for why a lock isn't needed here.
@MainActor
private final class ContinuationBox {
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    /// Resumes the continuation exactly once across however many callers
    /// race to call this. Returns whether THIS call was the one that fired
    /// it — callers use that to know whether they won the race (e.g. to
    /// decide whether to log a timeout).
    @discardableResult
    func resume() -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        continuation.resume()
        return true
    }
}

#if DEBUG
extension VoiceRoomService {
    /// Debug-only seam for the design-parity screen catalog (Task 4):
    /// forces `state` so `CatalogHostView` can force-present each of
    /// `PTTDockRow`'s 5 button variants (GSComponents.swift:1155) without a
    /// live LiveKit connection. `state` is `private(set)` above; this
    /// extension can assign it only because it lives in the SAME FILE as
    /// that declaration (Swift's `private` access rule). Compiled out of
    /// release entirely.
    func debugSetState(_ newState: VoiceRoomState) {
        state = newState
    }
}
#endif
