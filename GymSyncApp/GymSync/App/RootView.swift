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
            case .signedIn:
                MainTabView()
                    .environment(appState)
            }
        }
    }
}

private struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppState.Tab.home)

            LibraryTabView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .tag(AppState.Tab.library)

            Text("Social — Phase 2")  // placeholder in Phase 1
                .tabItem { Label("Social", systemImage: "person.2.fill") }
                .tag(AppState.Tab.social)

            StatsTabView()
                .tabItem { Label("Stats", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppState.Tab.stats)

            YouTabView()
                .tabItem { Label("You", systemImage: "person.crop.circle.fill") }
                .tag(AppState.Tab.you)
        }
    }
}
