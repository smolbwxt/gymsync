import Foundation

// MARK: - HeartRateZone
//
// Phase W Task 5 (watch-hr design §4 + master spec §5, `docs/superpowers/
// specs/2026-06-28-gymsync-design.md:1047`, quoted verbatim: "Zone mapping
// (client-side computation): zone = 'warmup' | 'moderate' | 'hard' | 'max'
// derived from user's max-HR estimate (either from HealthKit if available,
// or the standard 220 - age formula). Rendered as color on the HR pill."
//
// The master spec is NOT silent here (it names exactly these 4 zone
// labels), so this does NOT fall back to the task brief's generic "5-zone
// %-of-max" suggestion — that fallback only applies when the spec is silent,
// and it isn't.
//
// COMPUTED ONCE, phone-side, by the sharing user's own device, BEFORE the
// sample is ever broadcast (`WatchConnectivityBridge.handleHRSample`) —
// baked into `HeartRatePayload.zone` on the wire
// (`Services/HeartRateBroadcastService.swift`). A receiving client never
// recomputes another participant's zone from their raw bpm; it renders
// whatever zone string arrived on the broadcast
// (`GroupSessionLiveView.heartRateFor(_:)`), because zone reflects the
// SHARING user's own effort relative to THEIR OWN max HR — a viewer has
// neither the data nor the standing to compute that for someone else.
//
// RECORDED ASSUMPTION (Task 5 — no product/design sign-off): the spec
// offers two sources for a max-HR estimate — "from HealthKit if available"
// or "the standard 220 - age formula". Neither is actually available in
// this app today:
//   - `Profile` (`Models/Profile.swift`) has NO birth-date/age field —
//     checked before writing this. Adding one is explicitly out of this
//     task's scope (task-5-brief.md: "do NOT add a profile field this
//     task"), so "220 - age" cannot be computed for any user.
//   - HealthKit has no direct "maximum heart rate" characteristic to read
//     (`HKHealthStore` exposes `dateOfBirthComponents()`, not a max-HR
//     value) — reading it would still need the SAME missing age, just
//     sourced from HealthKit instead of `Profile`, and this app requests
//     HealthKit read access for heart-rate SAMPLES only
//     (`GymSyncWatch/HeartRateSampler.swift`'s authorization request), not
//     `.dateOfBirth`, which is a separate characteristic type this task
//     does not request permission for.
// `defaultMaxBPM` below is therefore a FIXED population estimate (a
// ~30-year-old's 220-30), not a faithful implementation of either named
// source — an honest placeholder pending a real profile age field, per the
// task brief's own explicit instruction for this exact situation ("use a
// fixed sensible default max like 190 and RECORD the assumption").
enum HeartRateZone: String, Codable, Sendable, Equatable, CaseIterable {
    case warmup, moderate, hard, max

    static let defaultMaxBPM = 190

    /// %-of-max-HR boundaries for the spec's 4 NAMED zones. The spec names
    /// the zone LABELS but gives no numeric cut points, so this task assigns
    /// commonly-cited round thresholds for a 4-bucket effort model: <60%
    /// easy/warmup, 60-75% steady aerobic/moderate, 75-90% threshold/hard,
    /// >=90% near-maximal/max. RECORDED ASSUMPTION — no designer/product
    /// sign-off on these exact cut points; see task-5-report.md.
    static func zone(bpm: Int, maxBPM: Int = defaultMaxBPM) -> HeartRateZone {
        guard maxBPM > 0 else { return .warmup }
        let pct = Double(bpm) / Double(maxBPM)
        switch pct {
        case ..<0.60: return .warmup
        case 0.60..<0.75: return .moderate
        case 0.75..<0.90: return .hard
        default: return .max
        }
    }
}

// MARK: - HeartRateFreshness
//
// Roster HR-pill staleness (task-5-brief.md item 4: "pills fade/remove when
// no sample for >15s"). Pure predicate — the GroupSessionLiveView-side
// auto-purge `Task` that actually drives the removal is untestable UI glue
// (same category as that file's own `showReactionOverlay`/`showSoundOverlay`
// sleep-based transient-state clearing); THIS is the authoritative,
// hermetically tested correctness check `heartRateFor(_:)` gates on before
// ever rendering a pill, independent of whether the purge timer has fired
// yet — the render-time gate, not the timer, is what actually guarantees a
// stale reading is never shown.
//
// DEVIATION from master spec §5's own phrasing ("other participants see the
// user's HR pill go to '—' with a small unpaired-watch icon"): this task's
// brief explicitly specifies "fade/remove" instead, which is what's
// implemented — no dash/icon placeholder state. Recorded in
// docs/design/accepted-deviations.json.
enum HeartRateFreshness {
    static func isFresh(receivedAt: Date, now: Date, staleAfter: TimeInterval) -> Bool {
        now.timeIntervalSince(receivedAt) <= staleAfter
    }
}
