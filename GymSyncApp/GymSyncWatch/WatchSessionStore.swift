import Foundation
import WatchConnectivity
import os

// MARK: - WatchSessionStore
//
// Phase W Task 2 (watch-hr design §3) — Watch-side counterpart to the
// phone's `WatchConnectivityBridge` (`GymSync/Services/WatchConnectivityBridge.swift`
// — that file's header doc comment covers the shared design reasoning;
// not duplicated here).
//
// NO protocol seam here, unlike the phone side. Per the task brief
// ("Hermetic tests: ... watch-only code isn't unit-testable in CI without
// a watch test target — do NOT create one, note the gap honestly"): this
// target has no unit-test target at all (`GymSyncApp/project.yml` defines
// `GymSyncTests`/`GymSyncUITests` against the `GymSync` iOS target only,
// nothing against `GymSyncWatch`), so a `WatchSessionProviding`-style seam
// here would have no test ever exercising the fake side of it — pure
// unused abstraction. This class talks to `WCSession.default` directly.
// KNOWN GAP: everything in this file is therefore unverifiable except by
// CI's compilation proof (`build-test` builds this target transitively —
// see task-1-report.md's "CI reasoning") and eventual device-QA (the
// design doc's own acceptance bar: "device-QA list (real Watch flows can't
// run in CI)").
//
// @Observable (not ObservableObject/@Published): watchOS 10's minimum
// Swift version here is the SAME `SWIFT_VERSION: "5.9"` the whole project
// pins (`GymSyncApp/project.yml:14`, project-wide `settings.base`, not
// overridden per-target) — `@Observable` has been available since iOS
// 17/watchOS 10, exactly this project's deployment floor
// (`options.deploymentTarget.watchOS: "10.0"`, `project.yml:9`), so there's
// no Swift-level reason to fall back to the older `ObservableObject`
// idiom. Matches the iOS side's own convention throughout (`AppState`,
// `VoiceRoomService`, `WatchConnectivityBridge` above — all `@Observable`).
@MainActor
@Observable
final class WatchSessionStore: NSObject {
    static let shared = WatchSessionStore()

    /// The latest `sessionState` push received from the phone, or `nil`
    /// before the first one arrives this launch (`ContentView`'s existing
    /// Task 1 "No live session" placeholder already covers that case —
    /// see this file's `ContentView.swift` wiring).
    private(set) var sessionState: WatchSessionStatePayload?

    /// Task 3 addition (watch-hr design §2, "Idle state") — the latest
    /// `idleState` push, or `nil`. Mutually exclusive with `sessionState`
    /// (both cleared/set as a pair in `didReceiveApplicationContext` below)
    /// since `updateApplicationContext` replaces the phone's ENTIRE pushed
    /// context on every call — see `WatchIdleStatePayload`'s own doc
    /// comment (`GymSyncShared/WatchEnvelope.swift`) for why only one of
    /// the two can ever be "current" at a time.
    private(set) var idleState: WatchIdleStatePayload?

    /// `true` once `WCSession.default.isReachable` has been observed
    /// `false`, OR the last-received `sessionState` is older than
    /// `staleThreshold` — design §3's "Watch reachability degradations
    /// handled honestly (phone app not reachable → Watch shows stale-state
    /// indicator)". Recomputed on every reachability change AND lazily via
    /// `refreshStaleness()` (age can cross the threshold with NO WCSession
    /// event at all — nothing fires on the clock simply advancing — so
    /// `ContentView` calls this on a timer/appear rather than relying only
    /// on the reachability-changed push).
    private(set) var isStale = false

    /// Threshold past which a `sessionState` is considered stale by AGE
    /// alone, independent of reachability. 90s: generously above
    /// `pushWatchSessionState`'s two real-world trigger cadences on the
    /// phone side (`.onAppear` once, `.onChange(of: currentTurnUserID)` on
    /// every turn pass — turns are commonly single-digit minutes apart,
    /// per-rep tap-to-log-set has no independent push of its own in this
    /// task's scope), while still being short enough that "phone app was
    /// force-quit or the session ended 10 minutes ago" reads as stale
    /// rather than confidently wrong.
    static let staleThreshold: TimeInterval = 90

    private var isReachable = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Re-evaluates `isStale` from the CURRENT wall-clock age of
    /// `sessionState` plus the last-known reachability. Deliberately public
    /// (not just recomputed inside the delegate callbacks) — see this
    /// property's own doc comment: age alone can cross the threshold with
    /// no WCSession event to trigger a recompute, so `ContentView` needs to
    /// be able to ask "is this still fresh?" on its own cadence (e.g. on
    /// appear, or a periodic timer once a real live-session UI exists —
    /// T2's `ContentView` wiring below calls this once on appear, which is
    /// enough to prove the mechanism without inventing a Watch-side timer
    /// this task's placeholder UI has no other use for).
    func refreshStaleness() {
        guard let sessionState else {
            isStale = false // "no session" isn't "stale" — it's simply empty; ContentView distinguishes the two.
            return
        }
        let age = Date().timeIntervalSince(sessionState.updatedAt)
        isStale = !isReachable || age > Self.staleThreshold
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionStore: WCSessionDelegate {
    // watchOS's `WCSessionDelegate` requires ONLY `activationDidCompleteWith`
    // — unlike the iOS side (`WCSessionProvider`,
    // `GymSync/Services/WatchConnectivityBridge.swift`), there is no
    // `sessionDidBecomeInactive`/`sessionDidDeactivate` pair to implement
    // (those two are iOS-only requirements in Apple's SDK, for the
    // multiple-paired-Watches case that has no watchOS-side equivalent).

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            Logger(subsystem: "app.gymsync.ios.watchkitapp", category: "watch")
                .error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isReachable = session.isReachable
            self.refreshStaleness()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isReachable = reachable
            self.refreshStaleness()
        }
    }

    /// `updateApplicationContext` delivery — the phone's `sessionState` OR
    /// `idleState` push (`WatchConnectivityBridge.updateSessionState`/
    /// `.updateIdleState`, both "latest wins" — Task 3 extended this method
    /// to route `idleState` too, previously `sessionState`-only).
    /// Unknown-kind/unsupported-version messages are dropped silently here
    /// (mirrored logging would need this file's own AppLogger-equivalent —
    /// out of scope to build for a single log line; the phone-side
    /// `WatchConnectivityBridge` is the side with hermetic test coverage
    /// proving this tolerance, see `WatchEnvelopeTests`/
    /// `WatchConnectivityBridgeTests` in `GymSyncTests`).
    ///
    /// Each recognized kind clears the OTHER stored payload — since only
    /// one context is ever active on the wire at a time (see
    /// `WatchIdleStatePayload`'s doc comment), the property this build
    /// ISN'T currently receiving must not keep showing a stale value from
    /// whatever it held before.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let envelope = WatchEnvelope.from(message: applicationContext), envelope.isSupportedVersion else { return }
        switch envelope.decodedKind() {
        case .sessionState:
            guard let payload = try? envelope.decodePayload(as: WatchSessionStatePayload.self) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sessionState = payload
                self.idleState = nil
                self.refreshStaleness()
            }
        case .idleState:
            guard let payload = try? envelope.decodePayload(as: WatchIdleStatePayload.self) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.idleState = payload
                self.sessionState = nil
                self.refreshStaleness()
            }
        case .logSet, .soundboardTap, .hrSample, nil:
            // Not applicable via applicationContext (the first two are
            // watch→phone sendMessage actions; hrSample is T5, also
            // sendMessage-based) / unrecognized kind — silent drop, same
            // tolerance as this method's pre-Task-3 behavior.
            return
        }
    }
}

// MARK: - Outbound actions (Phase W Task 3, watch-hr design §2)
//
// `logSet`/`tapSoundboard` — the Watch's half of `WatchConnectivityBridge.
// handleLogSet`/`.handleSoundboardTap` (`GymSync/Services/
// WatchConnectivityBridge.swift`). NO protocol seam here, same reasoning as
// this file's top-of-file doc comment (no watch-side test target exists) —
// talks to `WCSession.default` directly, same as every other member of this
// class.
extension WatchSessionStore {

    /// Sends a `logSet` action, awaiting the phone's reply. Reply semantics
    /// are respected honestly, not collapsed: `.success` means the set is
    /// saved server-side; `.queued` means the PHONE is offline and enqueued
    /// it into `OfflineSetLogQueue` (safe on the phone, not yet synced —
    /// NOT the same guarantee as `.success`); `.failure` means neither
    /// happened. `LogSetView` renders these as three distinct states.
    func logSet(exerciseID: UUID, reps: Int?, weight: Decimal?, rpe: Decimal?, isFailed: Bool, note: String?) async -> WatchActionReply {
        let payload = WatchLogSetPayload(exerciseID: exerciseID, reps: reps, weight: weight, rpe: rpe, isFailed: isFailed, note: note)
        return await sendAction(kind: .logSet, payload: payload)
    }

    /// Sends a `soundboardTap` action. Per `handleSoundboardTap`'s own doc
    /// comment this always replies `.success` once routed (both the local-
    /// play and broadcast-send legs are already best-effort at their own
    /// layer) — `.queued` is not a real outcome here, but `SoundboardView`
    /// still switches on the full `WatchActionReply.Outcome` rather than
    /// assuming, since the reply shape is shared with `logSet`.
    func tapSoundboard(slug: String) async -> WatchActionReply {
        let payload = WatchSoundboardTapPayload(slug: slug)
        return await sendAction(kind: .soundboardTap, payload: payload)
    }

    /// Shared `sendMessage` + reply-decode plumbing for both actions above.
    /// `WCSession.sendMessage`'s `errorHandler` fires for exactly the
    /// failure modes `WatchActionReply.Outcome.failure` already exists to
    /// describe (unreachable phone, timeout, delivery error) — mapped here
    /// rather than left to hang or crash the caller. Apple's documented
    /// contract guarantees exactly ONE of replyHandler/errorHandler fires
    /// per call, so the continuation below resumes exactly once.
    private func sendAction<T: Encodable>(kind: WatchMessageKind, payload: T) async -> WatchActionReply {
        guard let envelope = try? WatchEnvelope.encode(kind: kind, payload: payload),
              let message = try? envelope.asMessage() else {
            return WatchActionReply(outcome: .failure, message: "Couldn't build request")
        }
        guard WCSession.default.activationState == .activated else {
            return WatchActionReply(outcome: .failure, message: "Not connected to phone")
        }
        return await withCheckedContinuation { continuation in
            WCSession.default.sendMessage(message, replyHandler: { replyDict in
                let reply = WatchActionReply.from(message: replyDict)
                    ?? WatchActionReply(outcome: .failure, message: "Malformed reply")
                continuation.resume(returning: reply)
            }, errorHandler: { error in
                continuation.resume(returning: WatchActionReply(outcome: .failure, message: error.localizedDescription))
            })
        }
    }
}
