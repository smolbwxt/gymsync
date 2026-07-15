import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    // AppState is now a singleton (Phase 3d Task 5) so AppDelegate can reach
    // the same instance from outside the view tree — see AppState.shared's
    // doc comment.
    @State private var appState = AppState.shared
    // Singleton (Canvas Completion Task 5), same convention as `appState`
    // above — reading `themeStore.current` here (rather than a hardcoded
    // `.midnight`) is what makes the whole app re-render live when
    // `AppearanceView` calls `ThemeStore.select(_:)`.
    @State private var themeStore = ThemeStore.shared

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
        // ── Live theme chrome ──
        // `isDark` covers modernist/ink (light palettes) alongside
        // midnight/arena (dark) — see GSTheme.isDark's doc comment for the
        // luminance-based determination.
        .preferredColorScheme(themeStore.current.isDark ? .dark : .light)
        .environment(\.gsTheme, themeStore.current)
        // Tint every NavigationStack's bar items — chiefly the back button —
        // with the theme accent. Without this, SwiftUI falls back to the
        // system-blue environment tint, so pushed screens (Appearance,
        // Notifications, …) showed an iOS-blue "‹ Back" against the themed
        // chrome. UINavigationBar.appearance().tintColor alone does NOT reach
        // the SwiftUI back button; this environment tint does.
        .tint(themeStore.current.accent)
        .background(themeStore.current.bg.ignoresSafeArea())
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
        .task {
            // Re-register the APNs token for users who have ALREADY granted
            // push authorization, on every launch that reaches the signed-
            // in + profile-loaded state (MainTabView) — covers reinstall/
            // restore, where the OS hands out a fresh token but the user
            // never revisits onboarding to trigger the original
            // registration. registerTokenIfAuthorized() is a no-op when
            // authorization is .notDetermined/.denied (no prompt fires) —
            // the initial permission prompt stays owned by onboarding
            // (Task 6), which this deliberately does not touch.
            await PushReceiver.shared.registerTokenIfAuthorized()
        }
        .task {
            // Best-effort load of the persisted palette (Canvas Completion
            // Task 5) — same "runs on every launch that reaches signed-in +
            // profile-loaded state" timing as the push-token registration
            // above, since that's the earliest point a `user_settings` row
            // is guaranteed to be readable for the signed-in user.
            await ThemeStore.shared.load()
        }
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
