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
        soundboard: SoundboardBroadcasting? = nil
    ) {
        // `WCSessionProvider()`/`LiveSoundboardBroadcasting(...)` are
        // constructed HERE, in the init BODY, not as the parameters'
        // default-value expressions — same trap `LiveKitRoomConnection`'s
        // own doc comment documents (`Services/LiveKitRoomConnection.swift:260-269`):
        // default-argument expressions evaluate in a synchronous
        // nonisolated context even inside a `@MainActor` initializer, and
        // both of these production conformers touch `@MainActor`-isolated
        // state at construction time (`WCSessionProvider` sets itself as
        // `WCSession.default.delegate`; `SessionBroadcastService` is itself
        // `@MainActor`).
        self.session = session ?? WCSessionProvider()
        self.submitter = submitter
        self.userIDProvider = userIDProvider
        self.soundboard = soundboard ?? LiveSoundboardBroadcasting(broadcastService: SessionBroadcastService())
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
        case .hrSample:
            // T5 scope (design §4) — schema defined now, handler not yet
            // built. Explicit failure reply rather than silent drop so a
            // future watch-side sender (once T5 exists) gets an honest
            // signal during any transition period rather than a message
            // that silently vanishes.
            reply(.failure, message: "Not yet implemented", to: replyHandler)
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
    /// DELIBERATELY NOT WIRED (out of this task's scope): PR detection
    /// (`PersonalRecordRepository.record`) and turn-advance
    /// (`SessionRepository.advanceTurn`) — both of those are
    /// `logSetAndAdvance`'s OWN additional concerns on top of the bare
    /// submit, tied to `GroupSessionLiveView`'s live turn-rotation UI
    /// state (`isPR`/`priorBest`/`didQueueSetOffline` machinery,
    /// GroupSessionLiveView.swift:2005-2110). This task builds the
    /// PLUMBING (design §3); the actual Watch "Tap-to-log-set" surface
    /// (design §2, Component 2 — `GymSyncWatch/ContentView.swift` is still
    /// Task 1's placeholder) is separate, future scope, and is the right
    /// place to decide how (or whether) a watch-submitted set should also
    /// trigger PR checks / turn advancement once a real Watch UI exists to
    /// show that outcome. Noted here so this is a known, intentional
    /// boundary — not a silent omission.
    ///
    /// `setIndex: 1` — same "not turn-tracked" value
    /// `GroupSessionLiveView.logSet`'s OWN penalty-log path already uses
    /// unconditionally (GroupSessionLiveView.swift:2158), not a new
    /// invented shortcut. `set_index` has no uniqueness constraint
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
