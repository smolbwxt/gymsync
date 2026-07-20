import Foundation

// ── BroadcastChannelDecision ────────────────────────────────────────────
//
// Debt-zero sprint, I-1 channel-collision defensive fix
// (`.superpowers/sdd/task-2-brief.md`). Pure decision core behind the
// disposable-channel-vs-reuse choice `HeartRateBroadcastService.publish`
// and `SessionBroadcastService.broadcastRaw` each make before sending a
// broadcast on a topic they don't already hold a subscription for — same
// "static pure function extracted for hermetic testing" shape
// `HeartRateThrottle.allowed(lastSentAt:now:minInterval:)` already
// establishes (`GymSyncShared/HeartRateThrottle.swift:58-61`).
//
// THE HAZARD (quoted from the SDK source, supabase-swift, fetched via
// `gh api` at v2.52.0 — the latest stable tag, which is what this
// project's `project.yml` `from: 2.5.0` floor currently resolves to per
// `gh api repos/supabase/supabase-swift/releases`):
//
//   `RealtimeClientV2.channel(_:options:)`
//   (Sources/RealtimeV2/RealtimeClientV2.swift:395-410):
//   "Returns an existing channel for the given topic or creates a new
//   one... If a channel with the same topic already exists, it is
//   returned without modification."
//
//   `RealtimeClientV2.removeChannel(_:)`
//   (Sources/RealtimeV2/RealtimeClientV2.swift:459-479):
//   "Unsubscribes from and removes a channel. If the channel is currently
//   subscribed, it is unsubscribed first."
//
// Both `HeartRateBroadcastService` and `SessionBroadcastService` are
// constructed TWICE for the same session — once as a receive-side
// instance that calls `subscribe()` and holds the resulting channel for
// the session's lifetime (`GroupSessionLiveView`), and once as a
// SEND-ONLY instance whose `channel` field stays `nil` forever
// (`WatchConnectivityBridge.soundboard` / `.heartRateBroadcast`,
// `Services/WatchConnectivityBridge.swift:91,129`). Before this fix,
// every send from the send-only instance unconditionally created a
// "disposable" channel via `client.channel(topic)` — but on the SAME
// topic string the receive-side instance already holds, the SDK quote
// above means that call silently returned the RECEIVE side's own live
// channel object, not a fresh one — and the send-only instance's
// subsequent `removeChannel` then tore that subscription down. Gate
// finding I-1: the sharing phone's roster pills freeze after the first
// watch-relayed HR sample; the sibling soundboard path goes silent the
// same way after a watch-relayed tap.
//
// THE FIX: before creating a disposable channel, check the client's own
// topic registry — `RealtimeClientV2.channels: [String: RealtimeChannelV2]`
// (Sources/RealtimeV2/RealtimeClientV2.swift:126-132): "All managed
// channels indexed by their topics... The dictionary key is the
// fully-qualified topic string (e.g. `realtime:room:lobby`)." — reached
// via `SupabaseClient.realtimeV2` (NOT `SupabaseClient.channels`: that
// convenience wrapper's own implementation, `Sources/Supabase/
// SupabaseClient.swift:333-335` at this same version, references
// `realtimeV2.subscriptions` — which is NOT in `Sources/RealtimeV2/` but
// is a deprecated back-compat alias in `Sources/Realtime/Deprecated/
// Deprecated.swift:13-17`: `@available(*, deprecated, renamed:
// "channels") public var subscriptions: ... { channels }` — i.e. it
// literally returns `channels`. Resolved by the T2 re-review after this
// audit's search was scoped one directory too narrow. We still read
// `realtimeV2.channels` directly: same data, no deprecated shim).
enum BroadcastChannelDecision: Equatable {
    /// Reuse a channel this SAME service instance already holds
    /// (`self.channel`, set by its own prior `subscribe()` call). Never
    /// remove it here — `unsubscribe()` owns that channel's lifecycle.
    case reuseHeld

    /// Reuse a channel some OTHER holder already registered for this
    /// exact topic on the shared `RealtimeClientV2` (found via the
    /// registry check above). Never subscribe (it may already be
    /// subscribed/subscribing) or remove it (not this call's channel to
    /// own) — just broadcast on it.
    case reuseRegistry

    /// Nobody — not this instance, not the client-wide registry — holds
    /// this topic right now. Safe to create, subscribe, broadcast, and
    /// remove: the original "disposable channel" behavior, now gated on
    /// having actually confirmed the topic is free.
    case createDisposable

    /// - Parameters:
    ///   - hasHeldChannel: `true` when `self.channel != nil` — this
    ///     instance's own prior `subscribe()` call.
    ///   - topicRegistered: `true` when the client's topic registry
    ///     (`client.realtimeV2.channels["realtime:\(topic)"]`) already has
    ///     an entry for this exact topic, checked BEFORE calling
    ///     `client.channel(topic)` — so the check reflects state that
    ///     predates this call, not a channel this call itself is about to
    ///     create.
    ///
    ///   Residual risk (documented, not eliminated): the registry check
    ///   and the subsequent `client.channel(topic)` call are both
    ///   synchronous, non-`await`ing calls made back-to-back from a
    ///   single `@MainActor` method, so no OTHER `@MainActor`-isolated
    ///   code in this app can interleave between them (Swift actor
    ///   reentrancy only occurs at suspension points) — but the SDK's own
    ///   channel registry is guarded by a cross-thread lock
    ///   (`LockIsolated`), not an actor, so a same-instant race with a
    ///   genuinely concurrent non-MainActor SDK-internal mutation is not
    ///   provably closed by application code alone. GATE CORRECTION
    ///   (debt-zero whole-branch review, MINOR-1): the window is wider
    ///   than SDK-internal — the `createDisposable` arm itself SUSPENDS
    ///   at `await subscribe()`/`broadcast()` before its removeChannel
    ///   Task, and MainActor reentrancy during those suspensions lets the
    ///   view's own `subscribe()` adopt the SAME disposable object (the
    ///   SDK returns the registered instance), which the send path then
    ///   tears down. Reachable at EVERY subscribe boundary (view re-entry
    ///   mid-session while the watch relays), not only session startup —
    ///   still sub-second and strictly better than pre-fix. This narrows
    ///   the I-1 hazard from "reproduces on virtually every relayed
    ///   sample/tap" (the steady-state bug this fix targets and closes)
    ///   to subscribe-boundary windows; device QA (gate finding I-1's
    ///   named check) remains the empirical arbiter per the debt-zero
    ///   sprint's brief.
    static func decide(hasHeldChannel: Bool, topicRegistered: Bool) -> BroadcastChannelDecision {
        if hasHeldChannel { return .reuseHeld }
        if topicRegistered { return .reuseRegistry }
        return .createDisposable
    }
}
