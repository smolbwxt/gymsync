import SwiftUI

// MARK: - LedgerView
//
// Phase W Task 3 (watch-hr design §2, Component 4 "Ledger glance") —
// read-only burpee owed/paid summary for the current session, sourced
// entirely from `WatchSessionStatePayload.burpeesOwed` (pre-existing, Task
// 2) and `.burpeesPaid` (Task 3 addition) — see that struct's doc comments
// (`GymSyncShared/WatchEnvelope.swift`) for the exact phone-side derivation
// (`GroupSessionLiveView.burpeesRemaining`/`.penaltyLogged`, the SAME two
// numbers that view's own penalty banner renders as "YOU OWE N burpees").
// No write path here at all — the brief is explicit this is read-only; the
// phone's `LogSetView`-equivalent (its own penalty `LogSetSheet`) remains
// the only way to log a burpee, watch or otherwise.
struct LedgerView: View {
    @Environment(\.gsWatchTheme) private var theme
    let store: WatchSessionStore

    var body: some View {
        Group {
            if let state = store.sessionState, state.isActive {
                VStack(spacing: 10) {
                    ledgerStat(label: "OWED", value: state.burpeesOwed, tint: state.burpeesOwed > 0 ? theme.accent : theme.text)
                    Divider().overlay(theme.divider)
                    ledgerStat(label: "PAID", value: state.burpeesPaid, tint: theme.text)
                }
            } else {
                VStack {
                    Spacer(minLength: 0)
                    Text("No active session")
                        .font(.caption)
                        .foregroundStyle(theme.text.opacity(0.6))
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.bg)
        .navigationTitle("Ledger")
    }

    private func ledgerStat(label: String, value: Int, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.text.opacity(0.55))
            Text("\(value)")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(tint)
            Text("burpees")
                .font(.caption2)
                .foregroundStyle(theme.text.opacity(0.55))
        }
    }
}

#Preview {
    LedgerView(store: .shared)
}
