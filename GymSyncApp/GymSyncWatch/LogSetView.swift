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
            reps: reps > 0 ? reps : nil,
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
