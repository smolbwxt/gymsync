import SwiftUI

// Phase W Task 1 (watch-hr design §1) placeholder, extended by Phase W
// Task 2 (design §3) to actually render `WatchSessionStore`'s state: the
// idle "No live session" case (Task 1's original placeholder, unchanged
// wording), a minimal live-session summary once a `sessionState` push has
// arrived, and a stale-state indicator per the design doc's explicit
// requirement ("Watch reachability degradations handled honestly — phone
// app not reachable → Watch shows stale-state indicator").
//
// STILL a placeholder, deliberately: the real whose-turn SHELL (design §2
// Component 2's actual visual design — exercise headline, turn-state
// chrome, crown-adjustable steppers, etc.) is Phase D / a future Watch-UI
// task's scope, not this one. This task's bar is "show the (placeholder)
// state + stale indicator" (task brief, Task 2 item 3) — proving the data
// actually reaches the watch and the staleness signal actually works, not
// designing the final screen.

struct ContentView: View {
    @Environment(\.gsWatchTheme) private var theme
    @State private var store = WatchSessionStore.shared

    var body: some View {
        VStack(spacing: 8) {
            Text("GymSync")
                .font(.headline)
                .foregroundStyle(theme.text)

            if let state = store.sessionState {
                VStack(spacing: 4) {
                    Text(state.currentExerciseName ?? state.sessionName)
                        .font(.subheadline.bold())
                        .foregroundStyle(theme.text)
                        .lineLimit(2)
                    if let lifter = state.currentLifterName {
                        Text(state.isMyTurn ? "Your turn" : "\(lifter)'s turn")
                            .font(.caption2)
                            .foregroundStyle(theme.accent)
                    }
                    if store.isStale {
                        // "wifi.slash" (long-established SF Symbol, present
                        // since SF Symbols 1.0) rather than a guessed
                        // "iphone.slash"-style name this session can't
                        // verify against a live SF Symbols catalog —
                        // conveys "no connection to the phone" without
                        // risking an unrecognized symbol name.
                        Label("Phone unreachable", systemImage: "wifi.slash")
                            .font(.caption2)
                            .foregroundStyle(theme.text.opacity(0.6))
                    }
                }
            } else {
                Text("No live session")
                    .font(.caption)
                    .foregroundStyle(theme.text.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .onAppear {
            // Age-based staleness (WatchSessionStore.refreshStaleness's doc
            // comment) can't self-trigger on the clock alone — re-check
            // whenever this screen becomes visible, same "recompute
            // on-appear" idiom the iOS side uses throughout
            // (`GroupSessionLiveView`'s own `.onAppear`/`.onChange(of: scenePhase)`
            // hooks).
            store.refreshStaleness()
        }
    }
}

#Preview {
    ContentView()
}
