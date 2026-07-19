import SwiftUI

// Phase W Task 1 (watch-hr design §1) — minimal placeholder. Renders the
// design's Component 2 idle state ("no session"); the real whose-turn
// shell (current exercise/lifter/turn state, live-updated via
// WatchConnectivity) is future work once `WatchConnectivityBridge`'s
// Watch-side counterpart (design §3) exists. Uses `GSWatchTheme` (this
// task's other deliverable) so the token port has a real, compiled call
// site rather than sitting unused.

struct ContentView: View {
    @Environment(\.gsWatchTheme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            Text("GymSync")
                .font(.headline)
                .foregroundStyle(theme.text)
            Text("No live session")
                .font(.caption)
                .foregroundStyle(theme.text.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
    }
}

#Preview {
    ContentView()
}
