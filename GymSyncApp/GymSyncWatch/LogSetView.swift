import SwiftUI

// MARK: - LogSetView
//
// Phase W Task 3 (watch-hr design §2, Component 2 "Tap-to-log-set") — reps
// stepper (+/- watchOS idiom, `Stepper`), weight adjustable via Digital
// Crown, log button. Sends through `WatchSessionStore.logSet(...)` ->
// `WatchConnectivityBridge.handleLogSet` on the phone (design §3: "sends
// the set to the phone, which routes it through the EXISTING submit path").
//
// Digital Crown usage pattern (cited, not guessed — the exact API and
// modifier-ORDER requirement below): `.focusable(true)` MUST precede
// `.digitalCrownRotation(...)` in the modifier chain — putting it after
// silently breaks crown routing (the crown otherwise drives the enclosing
// `.verticalPage` TabView's page-swipe instead of this control). The crown
// binds to a `Double` (`digitalCrownRotation<V: BinaryFloatingPoint>`);
// `weightLbs` below is that binding, converted to `Decimal` only when
// building the outbound payload.
struct LogSetView: View {
    @Environment(\.gsWatchTheme) private var theme
    let store: WatchSessionStore

    @State private var reps: Int = 8
    @State private var weightLbs: Double = 45
    @State private var isSending = false
    /// Transient reply feedback — cleared after 2s, same "brief transient
    /// overlay" idiom `GroupSessionLiveView.showSoundOverlay`/
    /// `.showReactionOverlay` use phone-side (2-2.5s clear), applied here
    /// independently since watch-side code shares no target with that file.
    @State private var lastReply: WatchActionReply?

    private var canLog: Bool {
        store.sessionState?.isActive == true && store.sessionState?.currentExerciseID != nil
    }

    var body: some View {
        VStack(spacing: 6) {
            if !canLog {
                Spacer(minLength: 0)
                Text("No active set to log")
                    .font(.caption)
                    .foregroundStyle(theme.text.opacity(0.6))
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            } else {
                Stepper(value: $reps, in: 0...50) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Reps").font(.caption2).foregroundStyle(theme.text.opacity(0.6))
                        Text("\(reps)").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.text)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Weight (lbs)").font(.caption2).foregroundStyle(theme.text.opacity(0.6))
                    Text(weightLbs.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(theme.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Modifier ORDER matters (see this file's header doc
                // comment) — focusable() must precede digitalCrownRotation.
                .focusable(true)
                .digitalCrownRotation(
                    $weightLbs, from: 0, through: 500, by: 2.5,
                    sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true
                )

                Button {
                    Task { await submit() }
                } label: {
                    if isSending {
                        ProgressView().tint(theme.bg)
                    } else {
                        Text("Log Set")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(isSending)

                if let lastReply {
                    replyBadge(lastReply)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(theme.bg)
        .navigationTitle("Log Set")
    }

    @ViewBuilder
    private func replyBadge(_ reply: WatchActionReply) -> some View {
        switch reply.outcome {
        case .success:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .queued:
            Label("Saved on phone", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2).foregroundStyle(theme.accent)
        case .failure:
            Label(reply.message ?? "Failed", systemImage: "exclamationmark.circle.fill")
                .font(.caption2).foregroundStyle(.red)
        }
    }

    /// Respects the reply's 3-outcome shape honestly (per `WatchSessionStore.
    /// logSet`'s own doc comment): `.success`/`.queued`/`.failure` render as
    /// 3 DISTINCT badges above, never collapsed into a single "done" state.
    /// Does NOT reset `reps`/`weightLbs` on success — the next set at the
    /// same exercise is often the same weight/reps (matches the phone's own
    /// inline log card, which only resets on a genuine turn change, not
    /// every log).
    private func submit() async {
        guard let exerciseID = store.sessionState?.currentExerciseID else { return }
        isSending = true
        lastReply = nil
        let reply = await store.logSet(
            exerciseID: exerciseID,
            // Fix wave 1 (reviewer finding, MINOR 2) — sent AS-IS, no
            // zero-to-nil conversion. Matches the phone's own contract:
            // `SetLog.reps: Int?` (`GymSync/Models/SetLog.swift:9`) and its
            // DB column (`supabase/migrations/20260709000007_create_set_logs.sql:7`,
            // `CHECK (reps IS NULL OR reps >= 0)`) both treat `0` as a
            // valid, meaningful value, not a stand-in for "none" — and the
            // phone's own inline log card sends exactly what it parses
            // (`Int(logReps)`, `GroupSessionLiveView.commitInlineLog`,
            // `GroupSessionLiveView.swift:~1734`) with no nil-on-zero rule of
            // its own. `reps` here can never actually be nil on this
            // surface (the `Stepper` above always holds a concrete `Int` in
            // its `0...50` range) — this is the honest "send what the UI
            // holds" shape, not a guessed convention.
            reps: reps,
            // MINOR 3 (note-only, reviewer finding) — `Decimal(weightLbs)`
            // via a `Double` intermediate is exact for THIS control's
            // 2.5-step increments (`.digitalCrownRotation(..., by: 2.5, ...)`
            // above — every reachable value is a multiple of 2.5, which has
            // an exact binary-fraction `Double` representation). If a future
            // change ever introduces a step size without an exact `Double`
            // representation (e.g. thirds), this conversion would need to
            // go through `String` (`Decimal(string:)`) instead to avoid
            // inheriting `Double`'s rounding error.
            weight: weightLbs > 0 ? Decimal(weightLbs) : nil,
            rpe: nil,
            isFailed: false,
            note: nil
        )
        isSending = false
        lastReply = reply
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        // Same "still the same value I set, clear it" guard
        // `GroupSessionLiveView.showSoundOverlay` already uses phone-side
        // (`if soundOverlayText == text { soundOverlayText = nil }`) — a
        // second submit landing during this sleep would have overwritten
        // `lastReply` with a NEWER value this check must not clobber.
        if lastReply == reply { lastReply = nil }
    }
}

#Preview {
    LogSetView(store: .shared)
}
