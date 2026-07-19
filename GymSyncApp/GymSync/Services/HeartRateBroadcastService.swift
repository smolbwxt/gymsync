import Foundation
import Supabase

// ── HeartRateBroadcastService ───────────────────────────────────────────────
//
// Phase W Task 4 (watch-hr design §4, "Heart-rate broadcast" —
// `docs/superpowers/specs/2026-07-19-watch-hr-design.md:20-24`), wired for
// real by Task 5. Phone-side broadcaster for the `session:{id}:hr` Realtime
// channel.
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
// TASK 4 STUB / TASK 5 WIRING: the channel-name builder, payload struct, and
// throttle were built in T4 and are hermetically tested — everything a
// caller needs to reason about this channel's shape without touching the
// network. T5 fills in the actual Realtime subscribe/publish bodies below,
// fed by the Watch-side `HKAnchoredObjectQuery` sampler
// (`GymSyncWatch/HeartRateSampler.swift`) via `WatchConnectivityBridge
// .handleHRSample` (the real producer) and rendered by `GroupSessionLiveView`
// (the real roster-pill consumer — `GSHeartRatePill`,
// `DesignSystem/GSComponents.swift`). `subscribe`/`publish`/`unsubscribe`
// below follow the EXACT SAME call shape `SessionBroadcastService.subscribe`/
// `sendSound`/`broadcastRaw` already establishes for the sibling
// `session:{id}` broadcast channel (`Services/SessionBroadcastService.swift:
// 53-107,128-145,179-211`) — same disposable-channel-fallback send path, same
// `channel.broadcastStream(event:)` receive path, same best-effort
// (never-throws-into-the-caller) error handling. `HeartRateThrottle` itself
// moved to `GymSyncShared/HeartRateThrottle.swift` this task (T5) so the
// Watch-side sampler can reuse the identical pure decision core — see that
// file's own header comment.
//
// EPHEMERAL LAW (design §4, master spec §6.5): heart rate is biometric
// data that is NEVER persisted anywhere in this app — no DB table, no logs
// of bpm values. `HeartRatePayload` below is `Encodable` for the Realtime
// broadcast wire ONLY — see that struct's own doc comment for why it must
// never be given a route into a Postgrest `.insert()`/`.upsert()` call.
//
// ISOLATION NOTE: `HeartRatePayload` is declared at FILE SCOPE, not nested
// inside the `@MainActor` class below, even though only this service uses
// it today. Global-actor isolation (`@MainActor` on `HeartRateBroadcastService`)
// applies to that type's OWN members (methods/properties/initializers); it
// does NOT recursively apply to a type nested inside it — but keeping it
// file-scope removes any ambiguity about that rule entirely, rather than
// relying on it, so it stays freely constructible/testable from a plain,
// non-actor test context with no `nonisolated`/actor-hop bookkeeping needed
// anywhere. (`HeartRateThrottle` used to live here too, same reasoning —
// it's now in `GymSyncShared/HeartRateThrottle.swift`, also file-scope,
// same isolation-avoidance rationale.)

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

extension HeartRatePayload {
    /// Manual `AnyJSON` dict construction, field-by-field from `self` —
    /// matches `SessionBroadcastService.sendSound`/`sendReaction`'s own
    /// literal-dictionary style EXACTLY (`Services/SessionBroadcastService.
    /// swift:135-139,159-163`: `.string`/`.double` cases, no `.null` case
    /// used anywhere in this codebase — grepped before writing this) rather
    /// than routing through `JSONEncoder` + a `JSONObject: Decodable` bridge,
    /// which has no precedent anywhere in this codebase and is unverifiable
    /// here (Swift compiles ONLY in CI on this task — see task-5-brief.md —
    /// so an unproven SDK API surface is a real risk, not a style
    /// preference). `zone` is OMITTED (not encoded as an explicit JSON
    /// null) when `nil` — `subscribe`'s own receive side below already
    /// treats an absent key and an explicit null identically
    /// (`payload["zone"]?.stringValue` returns `nil` either way), so this
    /// loses no information a receiver can act on. This computed property
    /// keeps `HeartRatePayload` the single place the outgoing field mapping
    /// is defined — `publish` below calls this, not a second hand-built
    /// dict — while `HeartRatePayload`'s own `Encodable` conformance (used
    /// only by `HeartRateBroadcastServiceTests`' wire-shape tests) stays
    /// untouched as the documented/tested reference for what the JSON KEYS
    /// must be.
    var wireMessage: JSONObject {
        var message: JSONObject = [
            "user_id": .string(userID.uuidString),
            "bpm": .double(Double(bpm)),
            "ts": .double(ts)
        ]
        if let zone { message["zone"] = .string(zone) }
        return message
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

    /// Mirrors `SessionBroadcastService`'s own `channel`/`broadcastTask`
    /// pair (`Services/SessionBroadcastService.swift:38-39`) — held only by
    /// whichever instance called `subscribe`. `WatchConnectivityBridge`
    /// owns a SEPARATE `HeartRateBroadcastService` instance purely for
    /// SENDING (constructed in its own init body, same "two instances, one
    /// per direction" shape `SessionBroadcastService` already has via
    /// `LiveSoundboardBroadcasting`'s own separate instance) — that
    /// instance's `channel` stays `nil` forever, so its `publish` calls
    /// always take the disposable-channel fallback below, exactly like
    /// `SessionBroadcastService.sendSound`/`sendReaction` do from that same
    /// send-only instance.
    private var channel: RealtimeChannelV2?
    private var broadcastTask: Task<Void, Never>?

    // MARK: - Subscribe

    /// Subscribe to `heart_rate` broadcast events for a session — GroupSessionLiveView's
    /// receive side, called from `subscribeBroadcast()` alongside
    /// `SessionBroadcastService.subscribe`'s soundboard/reaction subscribe
    /// (`Features/Sessions/GroupSessionLiveView.swift`, `subscribeBroadcast()`).
    /// Same shape as that method (`Services/SessionBroadcastService.swift:53-107`):
    /// register the broadcast stream BEFORE `await ch.subscribe()` (same
    /// ordering rule), one `Task` iterating the stream on the main actor.
    ///
    /// Self-echo: this channel receives the CURRENT phone's own published
    /// samples too (Realtime broadcast's default behavior). Confirmed by
    /// `GroupSessionLiveView`'s own `onSoundboard` CALLBACK closure
    /// (`Features/Sessions/GroupSessionLiveView.swift:~2090-2092`, its call
    /// site of `SessionBroadcastService.subscribe`), which explicitly
    /// guards `userID != selfID` to skip its own echo — that guard lives in
    /// the CALLER's closure, not inside `SessionBroadcastService.subscribe`'s
    /// own body (Fix wave 1, MINOR: the original citation here attributed
    /// it to the wrong file — `subscribe`'s own body forwards every
    /// received broadcast to its `onSoundboard` parameter unconditionally,
    /// `Services/SessionBroadcastService.swift:86`; it does no filtering of
    /// its own). The guard's mere EXISTENCE at that call site is still the
    /// right evidence: it wouldn't be needed at all if this codebase's
    /// Realtime SDK/config didn't already deliver self-sent broadcasts back
    /// to the sender. `GroupSessionLiveView`'s own `onHeartRate` callback
    /// relies on the same self-echo: it's the SAME path that feeds both the
    /// Spotlight hero's own-HR pill (frame 2A) and every OTHER
    /// participant's roster pill (frame 2B) — one subscription, no special
    /// self-only mechanism needed.
    func subscribe(
        sessionID: UUID,
        onHeartRate: @escaping @MainActor (UUID, Int, String?) -> Void
    ) async {
        await unsubscribe()

        let ch = SupabaseService.shared.client
            .channel(Self.channelName(sessionID: sessionID))

        let stream = ch.broadcastStream(event: "heart_rate")

        self.channel = ch
        await ch.subscribe()

        broadcastTask = Task { @MainActor in
            for await payload in stream {
                // EPHEMERAL LAW: never log `bpm`/`zone` — the malformed-payload
                // branch below logs only that decoding failed, never the
                // payload's own values.
                guard
                    let rawUID = payload["user_id"]?.stringValue,
                    let uid = UUID(uuidString: rawUID),
                    let bpmRaw = payload["bpm"]?.doubleValue
                else {
                    AppLogger.heartRate.error("broadcast: malformed heart_rate payload")
                    continue
                }
                let zone = payload["zone"]?.stringValue
                onHeartRate(uid, Int(bpmRaw.rounded()), zone)
            }
        }
    }

    // MARK: - Unsubscribe

    func unsubscribe() async {
        broadcastTask?.cancel()
        broadcastTask = nil
        if let ch = channel {
            await SupabaseService.shared.client.removeChannel(ch)
        }
        channel = nil
    }

    // MARK: - Publish

    /// Broadcast a `HeartRatePayload` on `channelName(sessionID:)`, gated by
    /// `throttle.rateAllowed(userID:)` — same "drop, don't queue" ephemeral
    /// semantics `SessionBroadcastService.sendSound`/`sendReaction` already
    /// use for their own 1/s gate (`Services/SessionBroadcastService.swift:
    /// 128-129,152-153`). This is the SECOND throttle net: the Watch-side
    /// sampler (`GymSyncWatch/HeartRateSampler.swift`) already throttles to
    /// 1/5s before ever sending over WatchConnectivity, but this gate stays
    /// live regardless (task-5-brief.md: "the service's own throttle gate
    /// stays as the second net") — defense in depth against a future
    /// caller that doesn't go through the Watch sampler, or a Watch/phone
    /// version skew where an older watch build throttles differently.
    ///
    /// Caller: `WatchConnectivityBridge.handleHRSample` — this is a SEND-ONLY
    /// call site (see `channel`'s own doc comment above), so this method
    /// always takes the same disposable-channel-fallback path
    /// `SessionBroadcastService.broadcastRaw`'s `else` branch does
    /// (`Services/SessionBroadcastService.swift:184-203`), rather than
    /// duplicating that fallback as a separate private helper for a single
    /// call site.
    func publish(sessionID: UUID, userID: UUID, bpm: Int, zone: String?) async {
        guard throttle.rateAllowed(userID: userID) else { return }
        let payload = HeartRatePayload(userID: userID, bpm: bpm, zone: zone)
        let message = payload.wireMessage

        let ch: RealtimeChannelV2
        if let active = channel {
            ch = active
        } else {
            let tmp = SupabaseService.shared.client
                .channel(Self.channelName(sessionID: sessionID))
            await tmp.subscribe()
            defer {
                Task { await SupabaseService.shared.client.removeChannel(tmp) }
            }
            do {
                try await tmp.broadcast(event: "heart_rate", message: message)
            } catch {
                AppLogger.heartRate.error("broadcast send failed: \(error, privacy: .public)")
            }
            return
        }
        do {
            try await ch.broadcast(event: "heart_rate", message: message)
        } catch {
            AppLogger.heartRate.error("broadcast send failed: \(error, privacy: .public)")
        }
    }
}

// MARK: - HeartRateBroadcasting (send-side seam)
//
// Abstracts `publish` so `WatchConnectivityBridge.handleHRSample`'s relay
// gating (opt-in check, active-session check, decoded-payload check) is
// hermetically testable without linking Supabase/Realtime — same
// "protocol abstracts the production type, tests supply a fake" shape as
// `SoundboardBroadcasting` (`Services/WatchConnectivityBridge.swift`).
@MainActor
protocol HeartRateBroadcasting {
    func publish(sessionID: UUID, userID: UUID, bpm: Int, zone: String?) async
}

extension HeartRateBroadcastService: HeartRateBroadcasting {}
