import SwiftUI

// Phase W Task 1 (watch-hr design §1) — infra-only entry point. Still no
// AuthService/ThemeStore here (unlike GymSyncApp.swift, the iOS
// equivalent): the design's Component 1 is explicit that the phone owns
// the Supabase session and the Watch is a WatchConnectivity peripheral
// only, so this target has no auth and no networked data fetch of its own
// — WatchConnectivity (added Phase W Task 2, design §3) is NOT "networking"
// in that sense, it's the local phone<->watch link, carrying only what the
// phone already fetched. `WatchSessionStore` (`WatchSessionStore.swift`,
// Task 2) activates `WCSession` lazily on first access from
// `ContentView`'s `@State` — see that class's doc comment — rather than
// explicitly here, so this file still has nothing to initialize at launch.

@main
struct GymSyncWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
