import Foundation

// MARK: - HeartRateThrottle
//
// Phase W Task 5 (watch-hr design §4). Relocated here from
// `GymSync/Services/HeartRateBroadcastService.swift` (T4's stub, where this
// type originally lived file-scope) so the WATCH target can reuse the exact
// same throttle decision the PHONE side already uses — the task brief's own
// instruction: "Throttle watch-side to 1/5s BEFORE sending (reuse the pure
// HeartRateThrottle — it's in GymSyncShared? check; if iOS-only, move it to
// GymSyncShared additively)." It was iOS-only; this is that move. SHARED
// file (same target-membership mechanism as `WatchEnvelope.swift`/
// `WatchDisplayFormatting.swift` — compiled into BOTH `GymSync` and
// `GymSyncWatch` via `project.yml`'s `GymSyncShared` sources entry on each
// target), so `HeartRateBroadcastServiceTests` (`@testable import GymSync`)
// keeps seeing this type with ZERO changes needed on its side — it's still
// compiled directly into the `GymSync` module, just from a different file.
//
// `HeartRatePayload` (the Realtime WIRE shape) stays behind in
// `HeartRateBroadcastService.swift` — it's iOS-only (the watch never talks
// to Supabase Realtime directly, per watch-hr design §1: "the Watch is a
// WatchConnectivity peripheral only"), so it has no reason to compile into
// the watch target.

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
/// The WATCH-side sampler (`GymSyncWatch/HeartRateSampler.swift`) does NOT
/// use the per-user stateful wrapper below — the watch has no per-user
/// concept (it only ever samples the one wrist it's on) — it calls the pure
/// `allowed(lastSentAt:now:minInterval:)` core directly against a single
/// local `Date?`, which is the honest, minimal reuse for a single-stream
/// caller rather than keying a `[UUID: Date]` dictionary with a fabricated
/// sentinel id.
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
