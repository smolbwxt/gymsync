import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @State private var appState = AppState()

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Dock stays pinned at the physical bottom edge — it must NOT ride
            // up on the keyboard (matches system TabView chrome behavior).
            // Ignoring keyboard here only (not on an ancestor of the tab
            // content) keeps this opt-out scoped to the dock, so content
            // above it (ChatView compose bar, HomeView join-code field)
            // still receives the keyboard safe-area inset normally.
            GSTabBar(selection: $appState.selectedTab)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }
}
