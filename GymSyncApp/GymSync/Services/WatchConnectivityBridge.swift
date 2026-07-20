import Foundation
import WatchConnectivity

// MARK: - WatchConnectivityBridge
//
// Phase W Task 2 (watch-hr design §3, "Phone↔Watch plumbing" —
// `docs/superpowers/specs/2026-07-19-watch-hr-design.md:17-18`). Phone-side
// half of the WatchConnectivity link — the Watch-side counterpart is
// `GymSyncWatch/WatchSessionStore.swift`.
//
// SHAPE CHOICE (task brief's judgment call — read the existing service
// shapes first): NOT the static-namespace-enum idiom `HealthKitBridge`/
// `EventKitBridge` use (`Services/HealthKitBridge.swift:4`,
// `Services/EventKitBridge.swift:40`) — those wrap a single system store
// object with no delegate callbacks to route and no per-instance state a
// test would ever need to substitute. This is closer to `VoiceRoomService`
// (`Services/VoiceRoomService.swift:209`): a stateful, `@MainActor
// @Observable` singleton fronting an SDK object that talks back via a
// delegate, with a protocol seam (`WatchSessionProviding` below) so the
// service's routing/lifecycle logic is unit-testable without linking
// WatchConnectivity or touching a real `WCSession`. `LiveKitRoomConnection`
// (`Services/LiveKitRoomConnection.swift:101`) is the matching production-
// conformer half of that same shape: a small `@MainActor` class that wraps
// the SDK type 1:1 and hops its (non-`@MainActor`) delegate callbacks back
// to the main actor via `Task { @MainActor in ... }` — `WCSessionProvider`
// below does the identical hop for `WCSessionDelegate`.
//
// ACTIVATION LIFECYCLE (task brief: "activates WCSession when a session
// goes live (NOT at launch)"): `activateIfNeeded()` is called from
// `GroupSessionLiveView.onAppear` (GroupSessionLiveView.swift, right next
// to `appState.activeSessionID = liveSession.id` — the exact app-wide
// "session went live" signal already used to suppress push banners for a
// session the user is actively looking at, `App/AppState.swift:51`'s doc
// comment). Judgment call on the brief's OTHER named trigger
// ("...OR when the counterpart app installs, WCSession.isWatchAppInstalled"):
// NOT implemented as a separate trigger. `isWatchAppInstalled` is only
// meaningful to read AFTER activation (Apple's docs: the property reflects
// state populated by activation) — wiring "activate when the watch app is
// installed" would mean either activating unconditionally at launch just
// to read the property (defeating the whole "not at launch" instruction)
// or polling a property that isn't valid yet, which is circular. The
// live-session trigger alone satisfies BOTH halves of the brief's actual
// requirement: it's lazy (fires only for users who actually start a live
// session, not on every launch), and it's the ONLY app state transition
// that genuinely needs the watch link (nothing else in this app pushes
// state to or receives actions from a Watch). `WCSession.activate()`
// itself is documented prompt-free (no system permission dialog — it's
// not gated by anything a user has to approve, unlike HealthKit/EventKit/
// mic) and cheap, so laziness here is purely about not doing unnecessary
// SETUP work for the majority of launches with no paired Watch or no live
// session that launch, not about avoiding a prompt.
//
// SESSION-STATE PUSH (task brief: "build the state dict from the live-
// session models... the bridge should tap the underlying models/services,
// not the view"): `updateSessionState(_:)` below accepts an ALREADY-BUILT
// `WatchSessionStatePayload` rather than re-deriving "current exercise +
// current lifter" itself. This app has no service that independently
// computes that concept — `GroupSessionLiveView`'s own `currentExerciseForSheet`/
// `rotationOrder` computed properties (GroupSessionLiveView.swift:1675,
// :257) are themselves derived straight from the underlying models
// (`WorkoutSession`, `SessionParticipant`, `Profile`, `Exercise` —
// `Models/Session.swift`, `Models/Exercise.swift`) — the view holds no
// bridge-inaccessible private state that isn't ALSO just those models. A
// bridge-internal re-derivation would be a SECOND, divergence-prone copy of
// that same logic (exactly what this codebase's existing "not a
// reimplementation" comments elsewhere warn against — e.g.
// `SupabaseSetLogSubmitter`'s doc comment, `Services/OfflineSetLogQueue.swift:17-20`).
// So `GroupSessionLiveView.pushWatchSessionState()` builds the payload from
// its own model-derived properties and hands it to this bridge, which
// itself holds no View reference and knows nothing about SwiftUI.
@MainActor
@Observable
final class WatchConnectivityBridge {
    /// Not `private` — production code always goes through `.shared`
    /// (mirrors `VoiceRoomService.shared`'s identical convention and its
    /// doc comment's exact reasoning, `Services/VoiceRoomService.swift:200-206`);
    /// tests construct their own instance with fake collaborators.
    static let shared = WatchConnectivityBridge()

    private let session: WatchSessionProviding
    private let submitter: SetLogSubmitting
    private let userIDProvider: CurrentUserIDProviding
    private let soundboard: SoundboardBroadcasting
    /// Phase W Task 5 (watch-hr design §4) — the send-only
    /// `HeartRateBroadcastService` instance for `handleHRSample` below. Same
    /// "separate instance per direction" shape `soundboard` above already
    /// establishes via `LiveSoundboardBroadcasting`'s own
    /// `SessionBroadcastService()` — `GroupSessionLiveView` owns a SECOND,
    /// separate `HeartRateBroadcastService` instance for SUBSCRIBING/
    /// rendering pills; this one only ever calls `publish`.
    private let heartRateBroadcast: HeartRateBroadcasting
    /// Phase W gate finding I-2 (adjudicated) — best-effort turn-advance
    /// seam for `handleLogSet`'s post-submit `attemptTurnAdvance` below.
    /// Same "protocol + production conformer + test fake" idiom as
    /// `submitter` (`SetLogSubmitting`, `Services/OfflineSetLogQueue.swift:13-25`)
    /// — sibling-seamed rather than folded into `SetLogSubmitting` itself
    /// since the two wrap distinct repository calls with distinct
    /// signatures (`logSet(_:)` vs `advanceTurn(sessionID:)`). See
    /// `TurnAdvancing`'s own declaration at the bottom of this file.
    private let turnAdvancer: TurnAdvancing

    private var didActivate = false

    /// The most recent state this bridge pushed to the watch — doubles as
    /// this bridge's only notion of "what session/group is currently live,"
    /// consumed by `handleLogSet`/`handleSoundboardTap` below to fill in
    /// `sessionID`/`groupID` for an inbound watch action (the watch payload
    /// itself carries only what's specific to the action — exerciseID,
    /// reps, slug — not session identity, since the phone already told the
    /// watch which session is live via this exact same push). `nil` until
    /// the first push of a given process lifetime; an action received
    /// before any push (should be unreachable — the watch can't know about
    /// a session it was never told about) is rejected with `.failure`
    /// rather than guessed at.
    private(set) var lastPushedState: WatchSessionStatePayload?

    init(
        session: WatchSessionProviding? = nil,
        submitter: SetLogSubmitting = SupabaseSetLogSubmitter(),
        userIDProvider: CurrentUserIDProviding = AuthServiceCurrentUserIDProvider(),
        soundboard: SoundboardBroadcasting? = nil,
        heartRateBroadcast: HeartRateBroadcasting? = nil,
        turnAdvancer: TurnAdvancing = SupabaseTurnAdvancer()
    ) {
        // `WCSessionProvider()`/`LiveSoundboardBroadcasting(...)`/
        // `HeartRateBroadcastService()` are constructed HERE, in the init
        // BODY, not as the parameters' default-value expressions — same
        // trap `LiveKitRoomConnection`'s own doc comment documents
        // (`Services/LiveKitRoomConnection.swift:260-269`): default-argument
        // expressions evaluate in a synchronous nonisolated context even
        // inside a `@MainActor` initializer, and all three of these
        // production conformers touch `@MainActor`-isolated state at
        // construction time (`WCSessionProvider` sets itself as
        // `WCSession.default.delegate`; `SessionBroadcastService`/
        // `HeartRateBroadcastService` are themselves `@MainActor`).
        self.session = session ?? WCSessionProvider()
        self.submitter = submitter
        self.userIDProvider = userIDProvider
        self.soundboard = soundboard ?? LiveSoundboardBroadcasting(broadcastService: SessionBroadcastService())
        self.heartRateBroadcast = heartRateBroadcast ?? HeartRateBroadcastService()
        self.turnAdvancer = turnAdvancer
        self.session.onMessageReceived = { [weak self] message, replyHandler in
            self?.handle(message: message, replyHandler: replyHandler)
        }
    }

    /// Lazy activation entry point — see this type's header doc comment for
    /// the full "why here, why not launch, why not isWatchAppInstalled"
    /// reasoning. Idempotent within one process lifetime via `didActivate`;
    /// `WCSession.activate()` itself is ALSO safe to call repeatedly per
    /// Apple's own docs, so the guard here is purely "don't do redundant
    /// work," not a correctness requirement.
    func activateIfNeeded() {
        guard !didActivate else { return }
        didActivate = true
        session.activate()
    }

    /// Pushes `payload` via `updateApplicationContext` — "latest wins,"
    /// per design §3 (no queueing: a watch that was unreachable for the
    /// last 3 pushes only ever sees the newest on reconnect, which is
    /// exactly right for a "current session state" concept, unlike
    /// `sendMessage`'s per-call delivery). Best-effort: logs and swallows
    /// its own encode/send failures, matching this codebase's established
    /// "never let a bridge/service failure propagate into the caller's own
    /// flow" convention (`HealthKitBridge.replaceWorkout`'s doc comment,
    /// `Services/HealthKitBridge.swift:88-90`, is the clearest statement of
    /// this norm elsewhere in the codebase) — a Watch-push failure must
    /// never block or error `GroupSessionLiveView`'s own session flow.
    func updateSessionState(_ payload: WatchSessionStatePayload) {
        lastPushedState = payload
        do {
            let envelope = try WatchEnvelope.encode(kind: .sessionState, payload: payload)
            let message = try envelope.asMessage()
            try session.updateApplicationContext(message)
        } catch {
            AppLogger.watch.error("updateSessionState failed: \(error, privacy: .public)")
        }
    }

    /// Pushes `payload` via `updateApplicationContext` — Task 3 (watch-hr
    /// design §2, "Idle state"). Same "latest wins" mechanics as
    /// `updateSessionState` above, and the SAME best-effort swallow
    /// (`HealthKitBridge.replaceWorkout`'s established convention, cited on
    /// `updateSessionState`'s own doc comment). Deliberately does NOT touch
    /// `lastPushedState` — that field only exists to resolve
    /// `sessionID`/`groupID` for an INBOUND watch action
    /// (`handleLogSet`/`handleSoundboardTap`), and there is no such action
    /// tied to idle state (no live session means nothing to log or tap
    /// sound into). Callers (`HomeView`) are expected to only call this when
    /// no session is genuinely live — see that call site's own guard.
    func updateIdleState(_ payload: WatchIdleStatePayload) {
        do {
            let envelope = try WatchEnvelope.encode(kind: .idleState, payload: payload)
            let message = try envelope.asMessage()
            try session.updateApplicationContext(message)
        } catch {
            AppLogger.watch.error("updateIdleState failed: \(error, privacy: .public)")
        }
    }

    // MARK: - Inbound message routing

    /// Wired to `WatchSessionProviding.onMessageReceived` in `init` above.
    /// Every code path calls `replyHandler` EXACTLY ONCE — `sendMessage`'s
    /// counterpart on the watch side is waiting on this reply (or its own
    /// timeout/error handler) for every one of the paths below, including
    /// the malformed/unsupported/unknown ones; leaving any path silent
    /// would strand the watch-side caller until WatchConnectivity's own
    /// internal timeout, not a clean, fast failure.
    private func handle(message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let envelope = WatchEnvelope.from(message: message) else {
            AppLogger.watch.error("received message with no decodable envelope")
            reply(.failure, message: "Malformed message", to: replyHandler)
            return
        }
        guard envelope.isSupportedVersion else {
            AppLogger.watch.notice("ignoring envelope v\(envelope.v, privacy: .public) — newer than this build supports (max \(WatchEnvelope.maxSupportedVersion, privacy: .public))")
            reply(.failure, message: "Unsupported version", to: replyHandler)
            return
        }
        guard let kind = envelope.decodedKind() else {
            AppLogger.watch.notice("ignoring unknown envelope kind \(envelope.kind, privacy: .public)")
            reply(.failure, message: "Unknown message kind", to: replyHandler)
            return
        }
        switch kind {
        case .logSet:
            Task { await self.handleLogSet(envelope, replyHandler: replyHandler) }
        case .soundboardTap:
            Task { await self.handleSoundboardTap(envelope, replyHandler: replyHandler) }
        case .sessionState:
            // Phone→watch only; the phone should never RECEIVE this kind.
            AppLogger.watch.error("received unexpected sessionState message (phone→watch only)")
            reply(.failure, message: "Unsupported on phone", to: replyHandler)
        case .idleState:
            // Task 3 addition — phone→watch only, same reasoning as
            // .sessionState immediately above (mutually exclusive on the
            // wire with it; see WatchIdleStatePayload's doc comment).
            AppLogger.watch.error("received unexpected idleState message (phone→watch only)")
            reply(.failure, message: "Unsupported on phone", to: replyHandler)
        case .hrSample:
            Task { await self.handleHRSample(envelope, replyHandler: replyHandler) }
        }
    }

    /// `logSet` action — routes into the EXISTING submit path, INCLUDING
    /// the offline queue, exactly mirroring `GroupSessionLiveView.logSetAndAdvance`'s
    /// own try/catch shape (GroupSessionLiveView.swift:2027-2074): the
    /// SAME `SetLogSubmitting` seam `OfflineSetLogQueue` defines
    /// (`Services/OfflineSetLogQueue.swift:13-25`) — production `submitter`
    /// default is `SupabaseSetLogSubmitter`, which itself delegates to
    /// `SessionRepository.logSet(_:)` (`Models/SessionRepository.swift:73`,
    /// `try await client.from("set_logs").insert(set).execute()`) — so a
    /// watch-submitted set is byte-identical, submission-wise, to a phone-
    /// submitted one. On `.network` failure, enqueues into
    /// `OfflineSetLogQueue.shared.enqueue(log)` — the SAME queue instance
    /// (and dedupe-by-id, replay-on-reconnect behavior) the phone's own
    /// offline sets already use, per the design doc's explicit "deferred"
    /// note: "Watch-side offline set queue (phone's queue covers it — Watch
    /// requires phone reachability for logging, honest v1)".
    ///
    /// TURN-ADVANCE PARITY (Phase W gate finding I-2, ADJUDICATED — a
    /// watch-logged set now advances the turn, on parity with a
    /// phone-logged one): after a SUCCESSFUL ONLINE submit (the `try`
    /// branch below only — NOT the `.network`/queued branch), this method
    /// attempts `turnAdvancer.advanceTurn(sessionID:)` best-effort via
    /// `attemptTurnAdvance` below, mirroring `logSetAndAdvance`'s own
    /// online-only call: `guard !didQueueSetOffline else { return };
    /// try await SessionRepository.advanceTurn(sessionID: session.id)`
    /// (GroupSessionLiveView.swift:2415-2416). That method's own comment
    /// block immediately above it (GroupSessionLiveView.swift:2350-2378)
    /// documents why a queued-OFFLINE set does NOT auto-advance, even once
    /// the queued row replays — `OfflineSetLogQueue.replay()` only ever
    /// resubmits the INSERT, advanceTurn was never part of replay. This
    /// bridge inherits that identical limitation for the identical reason:
    /// there is no separate watch-side replay path to wire an advance into
    /// either. Per the T3-era offline law that same phone comment states —
    /// "the organizer (or this lifter, once back online, by logging their
    /// next set...) advances manually" — the turn simply does not move
    /// until a genuine online logSet happens, watch or phone.
    ///
    /// NOT gated on `lastPushedState.currentTurnUserID`: that field is a
    /// phone-side PUSH snapshot that can go stale the instant a turn
    /// changes elsewhere — the exact "second net sharing one stale input"
    /// trap `handleHRSample`'s own Fix-wave-1 doc comment below diagnoses
    /// for `shareHeartRate` (fixed there by reading LIVE `ThemeStore.shared
    /// .shareHeartRate` instead of the pushed snapshot). The authority here
    /// is the server-side `advance_turn` RPC instead — it re-validates
    /// against the CURRENT session row under `FOR UPDATE`, independent of
    /// whatever this bridge last pushed
    /// (`supabase/migrations/20260714000002_live_plumbing.sql`, "Fix-forward:
    /// advance_turn with liveness guard" — the migration that added the
    /// liveness check on top of the original 20260714000001 definition).
    /// Concretely, `advance_turn(p_session_id)`:
    ///   - `RAISE EXCEPTION 'not your turn'` (SQLSTATE P0001) unless
    ///     `auth.uid()` is either the row's CURRENT `current_turn_user_id`
    ///     OR its `organizer_id`;
    ///   - `RAISE EXCEPTION 'session is not in progress'` (P0001) unless
    ///     `sessions.state = 'in_progress'`;
    ///   - `RAISE EXCEPTION 'no active participants remain'` (P0001) — the
    ///     liveness-hole fix itself — if every remaining participant is
    ///     `no_show`.
    /// None of those is a silent no-op: each is a genuine thrown Postgres
    /// exception, and `ErrorMapping.map` turns it into
    /// `GymSyncError.validation(pg.message)`
    /// (`Models/SessionRepository.swift:388-397`,
    /// `Utilities/ErrorMapping.swift:48-56`). A watch tap that lands
    /// out-of-turn (stale watch UI, a race with another lifter's own
    /// advance, session ended between logSet and advance, etc.) therefore
    /// THROWS here — caught by `attemptTurnAdvance` and deliberately NOT
    /// surfaced as a reply failure: the SET itself already committed via
    /// `submitter.submit(log)` above, so failing the reply would tell the
    /// watch "your set didn't save" when it did. Every outcome (advanced,
    /// or rejected/failed and why) is logged at `.info` — an out-of-turn
    /// rejection is an ordinary, EXPECTED outcome of a best-effort
    /// attempt, not an error condition this bridge caused or must alert on.
    ///
    /// A turn-advance that fails from a network drop AFTER a successful
    /// `submitter.submit(log)` — as opposed to a genuine RPC rejection —
    /// gets the identical "documented, not retried" posture
    /// `logSetAndAdvance`'s own catch block already accepts on the phone
    /// (GroupSessionLiveView.swift:2417-2425: any `GymSyncError` here
    /// surfaces as `logSetErrorText`, no automatic retry of JUST the
    /// advance): this bridge has no separate advance-retry queue either,
    /// for the same reason cited on the phone's own comment
    /// (GroupSessionLiveView.swift:2372-2378) — the closest existing
    /// unstick mechanism is unchanged on both surfaces.
    ///
    /// The reply shape to the watch is UNCHANGED by any of this — still
    /// exactly `.success` on a saved set regardless of the turn-advance
    /// outcome (`LogSetView.replyBadge`, `GymSyncWatch/LogSetView.swift:94-106`,
    /// renders only `.success`/`.queued`/`.failure` — no 4th "saved, but
    /// turn didn't move" state was added; judged minimally: that's
    /// additive wire/UI surface for a best-effort side effect the watch UI
    /// has no actionable response to, not worth gold-plating this ruling
    /// with).
    ///
    /// PR detection (`PersonalRecordRepository.record`) remains
    /// DELIBERATELY NOT WIRED, unchanged from before — that is
    /// `logSetAndAdvance`'s own additional concern tied to its live
    /// celebratory-overlay UI state (`isPR`/`priorBest`,
    /// GroupSessionLiveView.swift:2315-2404), which has no watch-side
    /// equivalent surface to render into. Only the turn-advance half of
    /// the original "DELIBERATELY NOT WIRED" note is resolved by I-2; PR
    /// detection was never in that finding's scope.
    ///
    /// `setIndex: 1` — same "not turn-tracked" value
    /// `GroupSessionLiveView.logSet`'s OWN penalty-log path already uses
    /// unconditionally (GroupSessionLiveView.swift:2464 — debt-zero sprint
    /// citation fix; the SAME `SetLog(... setIndex: 1 ...)` literal sat at
    /// line 2158 when this comment was originally written (commit a3c3acc,
    /// confirmed via `git show a3c3acc:...GroupSessionLiveView.swift`),
    /// but later commits inserted ~300 lines earlier in the file and this
    /// citation was never updated to follow), not a new invented shortcut.
    /// `set_index` has no uniqueness constraint
    /// (`supabase/migrations/20260709000007_create_set_logs.sql:6`,
    /// `CHECK (set_index >= 1)` only) and — grepped across this entire
    /// target — is written in 6 places but never READ back by any query or
    /// UI logic (`GroupSessionLiveView`'s own set-count/rotation math all
    /// derives from filtering `allSessionSets`/`SetLog.userID`+`.exerciseID`,
    /// never `.setIndex`). A correct per-lifter running count (mirroring
    /// `mySetCount(for:)`, GroupSessionLiveView.swift) would need either a
    /// live re-fetch per watch tap or a second cache this bridge doesn't
    /// otherwise need to hold — not worth the added round trip / state for
    /// a field with no read-side consumer.
    func handleLogSet(_ envelope: WatchEnvelope, replyHandler: @escaping ([String: Any]) -> Void) async {
        guard let payload = try? envelope.decodePayload(as: WatchLogSetPayload.self) else {
            reply(.failure, message: "Malformed set", to: replyHandler)
            return
        }
        guard let userID = userIDProvider.currentUserID else {
            reply(.failure, message: "Not signed in", to: replyHandler)
            return
        }
        guard let sessionID = lastPushedState?.sessionID else {
            reply(.failure, message: "No active session", to: replyHandler)
            return
        }
        let log = SetLog(
            id: UUID(), userID: userID, sessionID: sessionID,
            exerciseID: payload.exerciseID,
            setIndex: 1,
            reps: payload.reps, weight: payload.weight, rpe: payload.rpe,
            isFailed: payload.isFailed, isPenalty: false,
            note: payload.note, loggedAt: Date()
        )
        do {
            try await submitter.submit(log)
            // Cheap drain — same fire-and-forget convention every ONLINE
            // set-log submit site already follows (`RootView`'s trigger
            // enumeration, App/RootView.swift:169-177, explicitly lists
            // this as "trigger 4/4").
            Task { await OfflineSetLogQueue.shared.replay() }
            // I-2 ruling — ONLY reached on a successful ONLINE submit (this
            // `do` block never runs the advance for the `.network`/queued
            // branch below); see this method's own TURN-ADVANCE PARITY doc
            // comment above for the full rationale.
            await attemptTurnAdvance(sessionID: sessionID)
            reply(.success, message: nil, to: replyHandler)
        } catch let error as GymSyncError {
            guard case .network = error else {
                reply(.failure, message: error.errorDescription, to: replyHandler)
                return
            }
            OfflineSetLogQueue.shared.enqueue(log)
            reply(.queued, message: nil, to: replyHandler)
        } catch {
            reply(.failure, message: error.localizedDescription, to: replyHandler)
        }
    }

    /// Best-effort turn-advance after a successful ONLINE `logSet` — see
    /// `handleLogSet`'s TURN-ADVANCE PARITY doc comment above for the full
    /// I-2 ruling and the `advance_turn` RPC contract this attempt is
    /// subject to. Never throws out of this function and never touches
    /// `replyHandler`: every outcome is logged at `.info` and otherwise
    /// swallowed, so `handleLogSet`'s `.success` reply can never depend on
    /// this call's result — the set already saved regardless of whether
    /// the turn actually moved.
    private func attemptTurnAdvance(sessionID: UUID) async {
        do {
            try await turnAdvancer.advanceTurn(sessionID: sessionID)
            AppLogger.watch.info("advanceTurn succeeded after watch logSet (session \(sessionID, privacy: .public))")
        } catch {
            AppLogger.watch.info("advanceTurn did not apply after watch logSet (session \(sessionID, privacy: .public)): \(error, privacy: .public)")
        }
    }

    /// `soundboardTap` action — routes into the EXISTING play/broadcast
    /// flow, mirroring `GroupSessionLiveView.tapSound(slug:)` verbatim
    /// (GroupSessionLiveView.swift:1957-1969): local play
    /// (`SoundboardPlayer.shared.play(slug:)`) + broadcast send
    /// (`SessionBroadcastService.sendSound(sessionID:groupID:slug:)`,
    /// GroupSessionLiveView.swift:1962-1967) as concurrent `async let`s,
    /// both awaited together. Routed through the
    /// `SoundboardBroadcasting` seam (below) rather than calling
    /// `SoundboardPlayer.shared`/a `SessionBroadcastService` instance
    /// directly, so this routing is hermetically testable without linking
    /// AVFoundation or Supabase.
    ///
    /// NOT rate-limited a second time here: `SessionBroadcastService.sendSound`
    /// already enforces the spec's shared 1/s send limit internally
    /// (`rateAllowed()`, Services/SessionBroadcastService.swift:170-175) —
    /// duplicating that gate here would just silently drop a legitimate tap
    /// at the wrong layer with no way for the caller (this bridge) to tell
    /// "rate-limited" apart from "sent." `GroupSessionLiveView.tapSound`
    /// layers its OWN separate 1s LOCAL gate on top
    /// (`lastSoundTapAt`, GroupSessionLiveView.swift:1958-1960) purely to
    /// prevent a double-tap from firing the local `SoundboardPlayer` twice
    /// before the network round trip even starts — that's a UI-debounce
    /// concern belonging to whichever surface owns the tap gesture (the
    /// phone's own soundboard dock today; the Watch's future soundboard
    /// buttons, T2+ scope per design §2, would own the equivalent debounce
    /// on ITS side once built), not this bridge's routing layer.
    func handleSoundboardTap(_ envelope: WatchEnvelope, replyHandler: @escaping ([String: Any]) -> Void) async {
        guard let payload = try? envelope.decodePayload(as: WatchSoundboardTapPayload.self) else {
            reply(.failure, message: "Malformed soundboard tap", to: replyHandler)
            return
        }
        guard let sessionID = lastPushedState?.sessionID else {
            reply(.failure, message: "No active session", to: replyHandler)
            return
        }
        let groupID = lastPushedState?.groupID
        async let playTask: Void = soundboard.play(slug: payload.slug)
        async let sendTask: Void = soundboard.sendSound(sessionID: sessionID, groupID: groupID, slug: payload.slug)
        _ = await (playTask, sendTask)
        // Both legs are already best-effort/non-throwing at their own
        // layer (`SoundboardPlayer.play`'s doc comment: "Never throws:
        // errors are logged + swallowed"; `SessionBroadcastService.sendSound`
        // likewise never throws out of `broadcastRaw`'s catch) — there is
        // no failure signal to distinguish here, so `.success` is honest:
        // "the tap was routed," not "the sound definitely played and
        // definitely broadcast," matching what the phone's OWN soundboard
        // dock already tells the user (no error UI exists for a failed
        // `tapSound` either — same fire-and-forget contract, unchanged).
        reply(.success, message: nil, to: replyHandler)
    }

    /// `hrSample` action (Phase W Task 5, watch-hr design §4) — watch→phone
    /// relay, `sendMessage` with a reply expected, same shape as
    /// `handleSoundboardTap` above. Computes `zone` from the sample's raw
    /// `bpm` (`HeartRateZone.zone(bpm:)`, `Services/HeartRateZone.swift`)
    /// BEFORE handing off to `heartRateBroadcast.publish` — zone is baked
    /// into the wire payload once, phone-side, per that type's own doc
    /// comment on why a receiver never recomputes it for someone else.
    ///
    /// RELAY GATING (task-5-brief.md item 2: "Only while in the live
    /// session"; the design's opt-in law): this is the SECOND gate — the
    /// Watch-side sampler (`GymSyncWatch/HeartRateSampler.swift`) already
    /// starts/stops itself from the SAME `isActive`/`shareHeartRate`
    /// signals it received in `WatchSessionStatePayload`, so in the honest
    /// case this guard never fires. It exists anyway as defense in depth
    /// (same "second net" philosophy as the throttle two layers down,
    /// `HeartRateBroadcastService.publish`'s own doc comment) against a
    /// stale/racing watch build that hasn't caught up to a just-flipped
    /// `shareHeartRate` or a just-ended session yet.
    ///
    /// Fix wave 1 (reviewer finding, CRITICAL): the `isActive` half of this
    /// still reads `lastPushedState` — there is no independent phone-side
    /// notion of "is this session live" to read instead, and staleness here
    /// is bounded by the SAME triggers that already re-push session state
    /// (turn change, session end, foreground). The `shareHeartRate` half no
    /// longer does: it now reads the LIVE `ThemeStore.shared.shareHeartRate`
    /// (`DesignSystem/ThemeStore.swift`) — the same source of truth
    /// `YouTabView.setShareHeartRate` writes directly and
    /// `pushWatchSessionState()` reads live for the OUTBOUND push. Reading
    /// `lastPushedState.shareHeartRate` here would make this "second net"
    /// share ONE un-refreshed input with the Watch's own gate — exactly the
    /// reviewer's criticism: both nets going stale together defeats the
    /// point of having two. Reading the live value instead means an
    /// opt-out drops samples on THIS gate immediately, even before a fresh
    /// `updateSessionState` push ever reaches (or is acknowledged by) the
    /// Watch — genuinely independent of `lastPushedState`'s own staleness.
    ///
    /// EPHEMERAL LAW: no branch in this function ever logs `payload.bpm` or
    /// the computed `zone` — only ids and fixed strings, matching every
    /// other `reply(...)` call site in this file.
    func handleHRSample(_ envelope: WatchEnvelope, replyHandler: @escaping ([String: Any]) -> Void) async {
        guard let payload = try? envelope.decodePayload(as: WatchHRSamplePayload.self) else {
            reply(.failure, message: "Malformed heart rate sample", to: replyHandler)
            return
        }
        guard let userID = userIDProvider.currentUserID else {
            reply(.failure, message: "Not signed in", to: replyHandler)
            return
        }
        guard let state = lastPushedState else {
            reply(.failure, message: "No active session", to: replyHandler)
            return
        }
        guard state.isActive else {
            reply(.failure, message: "Session is not live", to: replyHandler)
            return
        }
        guard ThemeStore.shared.shareHeartRate else {
            reply(.failure, message: "Heart rate sharing is off", to: replyHandler)
            return
        }
        let zone = HeartRateZone.zone(bpm: payload.bpm)
        await heartRateBroadcast.publish(sessionID: state.sessionID, userID: userID, bpm: payload.bpm, zone: zone.rawValue)
        reply(.success, message: nil, to: replyHandler)
    }

    private func reply(_ outcome: WatchActionReply.Outcome, message: String?, to handler: @escaping ([String: Any]) -> Void) {
        let r = WatchActionReply(outcome: outcome, message: message)
        guard let dict = try? r.asMessage() else {
            handler([:])
            return
        }
        handler(dict)
    }
}

// MARK: - WatchSessionProviding (WCSession seam)

/// Abstracts the WCSession surface `WatchConnectivityBridge` drives —
/// activation, applicationContext push, and inbound message routing — so
/// the bridge's lifecycle/routing logic is unit-testable without linking
/// WatchConnectivity or touching a real session. Same "protocol abstracts
/// the SDK type, production conformer wraps it 1:1, tests supply a fake"
/// shape as `VoiceRoomConnecting` (`Services/VoiceRoomService.swift:124`).
///
/// Deliberately MINIMAL — no `isReachable`/`isWatchAppInstalled` surface:
/// nothing in this task's scope reads either. Reachability-driven UI (the
/// design doc's "stale-state indicator when phone unreachable") is a
/// WATCH-SIDE concern read directly off `WCSession.default.isReachable`
/// there (`WatchSessionStore`, `GymSyncWatch/`) — the PHONE never needs to
/// know whether the watch can currently hear it for anything this task
/// builds. Extend this protocol (and `WCSessionProvider` below) if a
/// future task needs the phone to react to reachability too, rather than
/// adding unused surface now.
@MainActor
protocol WatchSessionProviding: AnyObject {
    /// Fired on the main actor whenever a `sendMessage` arrives expecting a
    /// reply. Set once by `WatchConnectivityBridge` right after
    /// construction — same "owner sets one closure per event, right after
    /// init" convention as every `VoiceRoomConnecting` callback
    /// (`Services/VoiceRoomService.swift:271-294`).
    var onMessageReceived: (([String: Any], @escaping ([String: Any]) -> Void) -> Void)? { get set }

    func activate()
    func updateApplicationContext(_ context: [String: Any]) throws
}

/// Production `WatchSessionProviding` conformer — the one file that talks
/// directly to `WCSession`. `WatchConnectivityBridge` never imports
/// WatchConnectivity or touches `WCSession` itself. Explicitly `@MainActor`
/// (matches `WatchSessionStore`'s identical explicit marker,
/// `GymSyncWatch/WatchSessionStore.swift`) rather than relying on
/// per-member isolation inference from `WatchSessionProviding` alone
/// (the shape `AuthServiceCurrentUserIDProvider` uses, `Services/
/// OfflineSetLogQueue.swift:52-64`, for a plain, non-`NSObject` struct) —
/// with `WCSessionDelegate` ALSO conformed here directly, being explicit
/// removes any ambiguity about which members are isolated by default, and
/// every `WCSessionDelegate` requirement is marked `nonisolated` below to
/// opt back out where the SDK's plain (non-actor) protocol demands it —
/// the standard, documented use of `nonisolated` for exactly this
/// "actor-isolated type conforms to a non-isolated delegate protocol" case.
@MainActor
final class WCSessionProvider: NSObject, WatchSessionProviding, WCSessionDelegate {
    private let wcSession: WCSession = .default

    var onMessageReceived: (([String: Any], @escaping ([String: Any]) -> Void) -> Void)?

    override init() {
        super.init()
        wcSession.delegate = self
    }

    func activate() {
        guard WCSession.isSupported() else {
            // Not every iOS device model supports WatchConnectivity at all
            // (`WCSession.isSupported()`'s documented purpose) — a no-op
            // here, not an error: this device simply has no Watch story,
            // same as `HealthKitBridge.requestPermission`'s
            // `HKHealthStore.isHealthDataAvailable()` guard
            // (`Services/HealthKitBridge.swift:8`).
            return
        }
        wcSession.activate()
    }

    func updateApplicationContext(_ context: [String: Any]) throws {
        try wcSession.updateApplicationContext(context)
    }

    // MARK: - WCSessionDelegate
    //
    // `WCSessionDelegate` callbacks are invoked on a background thread per
    // Apple's own documentation ("your app's WCSessionDelegate methods are
    // called on a background thread") — every method below is `nonisolated`
    // and hops to the main actor via `Task { @MainActor in ... }` before
    // touching `onMessageReceived` or any other MainActor-isolated state,
    // identical to `SpeakingParticipantsForwarder`'s hop for `RoomDelegate`
    // (`Services/LiveKitRoomConnection.swift:320-336`).

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            AppLogger.watch.error("WCSession activation failed: \(error, privacy: .public)")
        }
    }

    // iOS-only WCSessionDelegate requirements (a phone can pair with
    // multiple Watches across its lifetime; watchOS has no equivalent
    // requirement) — this file lives ONLY in the iOS `GymSync` target
    // (unlike `WatchEnvelope.swift`, which is shared), so both are always
    // available to implement here without any `#if os(iOS)` guard.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Apple's documented required behavior: re-activate for the NEXT
        // paired Watch once the current one deactivates.
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor [weak self] in
            self?.onMessageReceived?(message, replyHandler)
        }
    }

    /// Fix wave 2 (found while adjudicating the hrSample dispatch test) —
    /// the NO-reply variant. WatchConnectivity delivers a `sendMessage`
    /// sent WITHOUT a reply handler to THIS delegate method, not the
    /// reply-expecting one above (Apple's documented pairing: the delegate
    /// method invoked matches whether the sender supplied a
    /// `replyHandler`), and `WCSessionDelegate`'s message methods are
    /// optional — an unimplemented variant means the message is silently
    /// dropped. The watch's HR sampler sends hrSample EXACTLY this way
    /// (`GymSyncWatch/HeartRateSampler.swift`, `send(bpm:recordedAt:)`:
    /// `sendMessage(message, replyHandler: nil, errorHandler:)` — honest
    /// fire-and-forget for a high-frequency ephemeral stream, per its own
    /// doc comment), so before this method existed, every production HR
    /// sample died right here: delivered to an unimplemented delegate
    /// method, never reaching `handleHRSample` at all. (`logSet`/
    /// `soundboardTap` are unaffected — the watch sends both WITH a reply
    /// handler, `WatchSessionStore.logSet`/`tapSoundboard`, so they arrive
    /// via the variant above.)
    ///
    /// Routes into the SAME `onMessageReceived` seam with a no-op reply
    /// closure: `handle`'s "every code path calls `replyHandler` EXACTLY
    /// ONCE" contract is satisfied harmlessly — for a fire-and-forget
    /// send there is no counterpart waiting, so the reply goes nowhere by
    /// design, and no second seam callback (with all its fake/test
    /// plumbing) is needed for what is only a difference in delivery, not
    /// in routing.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.onMessageReceived?(message, { _ in })
        }
    }
}

// MARK: - SoundboardBroadcasting (soundboard-tap routing seam)

/// Abstracts the two side effects `handleSoundboardTap` triggers — local
/// playback + broadcast send — mirroring `GroupSessionLiveView.tapSound`'s
/// own pair of calls (GroupSessionLiveView.swift:1962-1967) behind one
/// small protocol, so `WatchConnectivityBridge`'s routing is hermetically
/// testable without linking AVFoundation (`SoundboardPlayer`) or Supabase
/// (`SessionBroadcastService`).
@MainActor
protocol SoundboardBroadcasting {
    func play(slug: String) async
    func sendSound(sessionID: UUID, groupID: UUID?, slug: String) async
}

/// Production conformer — delegates to the SAME two call sites
/// `GroupSessionLiveView.tapSound` already uses, so a watch-originated tap
/// is byte-identical, side-effect-wise, to a phone-originated one.
struct LiveSoundboardBroadcasting: SoundboardBroadcasting {
    let broadcastService: SessionBroadcastService

    func play(slug: String) async {
        await SoundboardPlayer.shared.play(slug: slug)
    }

    func sendSound(sessionID: UUID, groupID: UUID?, slug: String) async {
        await broadcastService.sendSound(sessionID: sessionID, groupID: groupID, slug: slug)
    }
}

// MARK: - TurnAdvancing (best-effort turn-advance seam, Phase W gate finding I-2)

/// Abstracts `SessionRepository.advanceTurn(sessionID:)` for `handleLogSet`'s
/// `attemptTurnAdvance` — same "protocol seam, production conformer
/// delegates 1:1 to the real repository call, test fake substitutes" idiom
/// as `SetLogSubmitting` (`submitter` above, `Services/
/// OfflineSetLogQueue.swift:13-25`). NOT `@MainActor`: unlike
/// `SoundboardBroadcasting` immediately above (whose production conformer
/// touches the `@MainActor` `SoundboardPlayer.shared`/`SessionBroadcastService`),
/// `SessionRepository.advanceTurn` is a plain nonisolated `static func`
/// (`enum SessionRepository`, `Models/SessionRepository.swift:4,388`), so
/// this protocol stays nonisolated too — same shape `SetLogSubmitting`
/// itself already uses for the same reason (`SessionRepository.logSet`).
protocol TurnAdvancing {
    func advanceTurn(sessionID: UUID) async throws
}

/// Production conformer — delegates to the SAME repository call
/// `GroupSessionLiveView.logSetAndAdvance`'s own online path already uses
/// (GroupSessionLiveView.swift:2416, `SessionRepository.advanceTurn(sessionID:)`),
/// so a watch-triggered advance is byte-identical, RPC-wise, to a
/// phone-triggered one — same `advance_turn` RPC, same server-side
/// authorization/liveness validation
/// (`supabase/migrations/20260714000002_live_plumbing.sql`).
struct SupabaseTurnAdvancer: TurnAdvancing {
    func advanceTurn(sessionID: UUID) async throws {
        try await SessionRepository.advanceTurn(sessionID: sessionID)
    }
}
