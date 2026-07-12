import SwiftUI

struct OnboardingCoordinator: View {
    let userID: UUID
    @Environment(AppState.self) private var appState
    @State private var profile: Profile?
    @State private var loading = true

    // Only set true when `profile` was just created via UsernameView in
    // this session — drives the home-gym + welcome screens. A `profile`
    // loaded from `loadProfile()` (a returning user who already completed
    // onboarding previously) skips straight to completion, as before.
    @State private var isNewSignup = false
    @State private var showWelcome = false

    var body: some View {
        Group {
            if loading {
                ProgressView().controlSize(.large)
            } else if profile == nil {
                UsernameView(chosenProfile: Binding(
                    get: { profile },
                    set: { newProfile in
                        profile = newProfile
                        isNewSignup = newProfile != nil
                    }
                ))
            } else if isNewSignup, let p = profile {
                if showWelcome {
                    WelcomeView(profile: p) {
                        appState.currentProfile = p
                    }
                } else {
                    HomeGymSetupView(isOnboarding: true, onAdvance: {
                        showWelcome = true
                    })
                }
            } else {
                Color.clear.onAppear { appState.currentProfile = profile }
            }
        }
        .task { await loadProfile() }
    }

    @MainActor
    private func loadProfile() async {
        loading = true
        defer { loading = false }
        do {
            profile = try await ProfileRepository.fetch(userID: userID)
            if let p = profile { appState.currentProfile = p }
        } catch {
            AppLogger.auth.error("profile load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
