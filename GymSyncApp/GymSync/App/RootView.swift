import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    // AppState is now a singleton (Phase 3d Task 5) so AppDelegate can reach
    // the same instance from outside the view tree — see AppState.shared's
    // doc comment.
    @State private var appState = AppState.shared

    var body: some View {
        Group {
            switch auth.state {
            case .pending:
                ProgressView().controlSize(.large)
            case .signedOut:
                SignInView()
            case .signedIn(let userID):
                if appState.currentProfile == nil {
                    OnboardingCoordinator(userID: userID)
                        .environment(appState)
                } else {
                    MainTabView()
                        .environment(appState)
                }
            }
        }
        // ── Midnight chrome ──
        .preferredColorScheme(.dark)
        .environment(\.gsTheme, .midnight)
        .background(GSTheme.midnight.bg.ignoresSafeArea())
    }
}

private struct MainTabView: View {
    @Environment(AppState.self) private var appState

    // Set true whenever a pushed descendant (LobbyView, ChatView, etc.) reports
    // `.gsHidesDock()` — see GSComponents.swift for the full rationale. Popping
    // back to a tab root (no more `.gsHidesDock()` contributors mounted) flips
    // this back to false via the same onPreferenceChange callback, restoring
    // the dock reliably regardless of push depth.
    @State private var isDockHidden = false

    var body: some View {
        @Bindable var appState = appState
        ZStack {
            switch appState.selectedTab {
            case .home:    HomeView()
            case .library: LibraryTabView()
            case .social:  SocialTabView()
            case .stats:   StatsTabView()
            case .you:     YouTabView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(GSHidesDock.self) { hides in
            withAnimation(.easeInOut(duration: 0.2)) {
                isDockHidden = hides
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Dock stays pinned at the physical bottom edge — it must NOT ride
            // up on the keyboard (matches system TabView chrome behavior).
            // Ignoring keyboard here only (not on an ancestor of the tab
            // content) keeps this opt-out scoped to the dock, so content
            // above it (ChatView compose bar, HomeView join-code field)
            // still receives the keyboard safe-area inset normally.
            if !isDockHidden {
                GSTabBar(selection: $appState.selectedTab)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
