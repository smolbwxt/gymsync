import SwiftUI

// Phase W Task 1 (watch-hr design §1) — infra-only entry point. No
// AuthService/AppState/ThemeStore here (unlike GymSyncApp.swift, the iOS
// equivalent): the design's Component 1 is explicit that the phone owns
// the Supabase session and the Watch is a WatchConnectivity peripheral
// only, so this target has no networking, no auth, and nothing to
// initialize at launch yet. `WatchConnectivityBridge`'s Watch-side
// counterpart (design §3) and its session-state wiring are future work
// (Component 3, not this task).

@main
struct GymSyncWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
