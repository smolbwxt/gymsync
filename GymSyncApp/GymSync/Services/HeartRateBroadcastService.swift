import Foundation

// ── HeartRateBroadcastService ───────────────────────────────────────────────
//
// Phase W Task 4 (watch-hr design §4, "Heart-rate broadcast" —
// `docs/superpowers/specs/2026-07-19-watch-hr-design.md:20-24`). Phone-side
// broadcaster for the `session:{id}:hr` Realtime channel.
//
// Wire shape (quoted verbatim, master spec §5 —
// `docs/superpowers/specs/2026-06-28-gymsync-design.md:1033-1047`):
//
//   channel: session:{session_id}:hr
//   {
//     "type": "broadcast",
//     "event": "heart_rate",
//     "payload": { "user_id": "...", "bpm": 172, "zone": "hard", "ts": 1741800000123 }
//   }
//   "Sample rate: one broadcast per 5 seconds per user."
//
// STUB SCOPE (task-4-brief.md item 4): the channel-name builder, payload
// struct, and throttle below are REAL and hermetically tested — everything
// a caller needs to reason about this channel's shape without touching the
// network. Actual Realtime subscribe/publish wiring is DELIBERATELY
// deferred to T5: that task also builds the Watch-side `HKAnchoredObjectQuery`
// sampler (design §4 "Watch side") this service would be fed by, and wiring
// a `publish` path with no real producer upstream — or a `subscribe` path
// with no roster UI to render into yet — would be untested, unreachable
// code today. `subscribe`/`publish`/`unsubscribe` below are sketched with
// the SAME call shape `SessionBroadcastService.subscribe`/`sendSound`
// already establishes for the sibling `session:{id}` broadcast channel
// (`Services/SessionBroadcastService.swift:53-107,128-145`), so T5 can fill
// in the `channel(...).broadcastStream`/`.broadcast` bodies without
// redesigning this service's call surface.
//
// EPHEMERAL LAW (design §4, master spec §6.5): heart rate is biometric
// data that is NEVER persisted anywhere in this app — no DB table, no logs
// of bpm values. `HeartRatePayload` below is `Encodable` for the Realtime
// broadcast wire ONLY — see that struct's own doc comment for why it must
// never be given a route into a Postgrest `.insert()`/`.upsert()` call.
//
// ISOLATION NOTE: `HeartRatePayload` and `HeartRateThrottle` are declared
// at FILE SCOPE, not nested inside the `@MainActor` class below, even
// though only this service uses them today. Global-actor isolation
// (`@MainActor` on `HeartRateBroadcastService`) applies to that type's OWN
// members (methods/properties/initializers); it does NOT recursively apply
// to a type nested inside it — but keeping them file-scope removes any
// ambiguity about that rule entirely, rather than relying on it, so both
// types stay freely constructible/testable from a plain, non-actor test
// context with no `nonisolated`/actor-hop bookkeeping needed anywhere.

/// Wire shape for the `heart_rate` broadcast event — field names match the
/// spec's payload EXACTLY: `{user_id, bpm, zone, ts}`
/// (`docs/superpowers/specs/2026-06-28-gymsync-design.md:1041`, `"payload":
/// { "user_id": "...", "bpm": 172, "zone": "hard", "ts": 1741800000123 }`).
/// `zone` is optional on the wire (spec's own shorthand elsewhere: "{user_id,
/// bpm, zone?}") — computing it is a T5 concern (design §4: "zones per the
/// spec's formula... record the choice"; §5: "derived from user's max-HR
/// estimate... rendered as color on the HR pill"), so this stub carries it
/// as `String?` with no producer yet. `ts` is epoch-milliseconds (`Double`),
/// matching `SessionBroadcastService.sendSound`/`sendReaction`'s own `"ts":
/// .double(Date().timeIntervalSince1970 * 1000)` convention for this exact
/// non-Codable Realtime-broadcast wire path (`Services/
/// SessionBroadcastService.swift:138,163` — `WatchWire`'s `.iso8601` `Date`
/// strategy is a DIFFERENT wire, the WatchConnectivity envelope, not this
/// one).
///
/// EPHEMERAL LAW: this struct is `Encodable` for the Realtime broadcast wire
/// ONLY. It must NEVER be given a `CodingKeys`-compatible route into a
/// Supabase Postgrest `.insert()`/`.upsert()`/`.update()` call against any
/// table — there is no `heart_rate_samples` table anywhere in this schema,
/// and none should ever be added (design §4: "no DB table, no logs of bpm
/// values"; §6.5: "Ephemeral broadcast + zero persistence"). Any future call
/// site that logs this payload (or its `bpm`/`zone` fields individually)
/// violates that law — `AppLogger` call sites in this phase already avoid
/// logging set weights/reps for the same PII-avoidance discipline
/// (`WatchConnectivityBridge`'s error logs carry only ids/error
/// descriptions); `bpm`/`zone` must get the identical treatment once T5
/// adds real log sites here.
struct HeartRatePayload: Encodable, Sendable, Equatable {
    let userID: UUID
    let bpm: Int
    let zone: String?
    let ts: Double

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case bpm, zone, ts
    }

    init(userID: UUID, bpm: Int, zone: String?, at date: Date = Date()) {
        self.userID = userID
        self.bpm = bpm
        self.zone = zone
        self.ts = date.timeIntervalSince1970 * 1000
    }
}

/// 1 broadcast per 5s PER USER (spec: "Sample rate: one broadcast per 5
/// seconds per user"). Same SHAPE as `SessionBroadcastService.rateAllowed()`
/// (`Services/SessionBroadcastService.swift:170-175` — a single `lastSentAt`
/// gate, "≥ interval since last send" check, "drop, don't queue" semantics)
/// but keyed PER `user_id` rather than one shared timestamp, matching the
/// spec's literal "per user" phrasing. A single phone only ever broadcasts
/// its OWN signed-in user's samples in v1 (one paired Watch, one phone, one
/// user) — the per-user keying is headroom for correctness, not a v1
/// requirement, and costs nothing.
///
/// `allowed(lastSentAt:now:minInterval:)` is the pure decision core behind
/// `rateAllowed(userID:now:)`'s stateful wrapper — the same "pure function
/// behind a stateful convenience" shape `ThemeStore.mergeExternalSettingsWrite`
/// uses for its own merge rule (`DesignSystem/ThemeStore.swift`) — so every
/// edge case (no prior send, exactly at the boundary, just under, just
/// over) is trivial to unit test without constructing anything stateful.
struct HeartRateThrottle {
    private var lastSentAt: [UUID: Date] = [:]
    let minInterval: TimeInterval

    init(minInterval: TimeInterval = 5.0) {
        self.minInterval = minInterval
    }

    /// Pure decision core — no mutation.
    static func allowed(lastSentAt: Date?, now: Date, minInterval: TimeInterval) -> Bool {
        guard let lastSentAt else { return true }
        return now.timeIntervalSince(lastSentAt) >= minInterval
    }

    /// Stateful convenience: checks + records atomically, mirroring
    /// `SessionBroadcastService.rateAllowed()`'s own check-and-record call
    /// shape for its callers.
    mutating func rateAllowed(userID: UUID, now: Date = Date()) -> Bool {
        guard Self.allowed(lastSentAt: lastSentAt[userID], now: now, minInterval: minInterval) else {
            return false
        }
        lastSentAt[userID] = now
        return true
    }
}

@MainActor
final class HeartRateBroadcastService {

    /// `session:{id}:hr` — the spec's literal channel name
    /// (`docs/superpowers/specs/2026-06-28-gymsync-design.md:965`), a
    /// SIBLING of (a different channel from) plain `session:{id}` — the
    /// soundboard/reaction channel `SessionBroadcastService` owns. A pure
    /// static function (no instance state) so both this service and any
    /// test can build the exact wire name without constructing a live
    /// channel.
    static func channelName(sessionID: UUID) -> String {
        "session:\(sessionID.uuidString):hr"
    }

    private var throttle = HeartRateThrottle()

    // MARK: - Subscribe / publish (T5 scope — signatures sketched only)
    //
    // NOT WIRED to Supabase Realtime (task-4-brief.md item 4: "NO actual
    // Realtime wiring yet (T5)"). No production call site exists for any of
    // the three methods below yet either — nothing samples HR to feed
    // `publish` and nothing renders a roster pill to consume `subscribe`
    // until T5 exists. Bodies are intentionally empty; see this file's
    // header comment for the full reasoning.

    /// T5: subscribe to `channelName(sessionID:)`'s `heart_rate` broadcast
    /// event, decode into `(userID, bpm, zone)`, invoke `onHeartRate` on
    /// the main actor — same shape as `SessionBroadcastService.subscribe`'s
    /// `onSoundboard`/`onReaction` callbacks
    /// (`Services/SessionBroadcastService.swift:53-57`).
    func subscribe(
        sessionID: UUID,
        onHeartRate: @escaping @MainActor (UUID, Int, String?) -> Void
    ) async {
        // Intentionally not implemented — T5 scope, see header comment.
    }

    /// T5: broadcast a `HeartRatePayload` on `channelName(sessionID:)`,
    /// gated by `throttle.rateAllowed(userID:)` — same "drop, don't queue"
    /// ephemeral semantics `SessionBroadcastService.sendSound`/`sendReaction`
    /// already use for their own 1/s gate
    /// (`Services/SessionBroadcastService.swift:128-129,152-153`). The
    /// throttle check is real and live even in this stub — only the actual
    /// network send below it is deferred.
    func publish(sessionID: UUID, userID: UUID, bpm: Int, zone: String?) async {
        guard throttle.rateAllowed(userID: userID) else { return }
        // Intentionally not implemented — T5 scope, see header comment.
    }

    func unsubscribe() async {
        // Intentionally not implemented — T5 scope, see header comment.
    }
}
