import SwiftUI

struct OnboardingCoordinator: View {
    let userID: UUID
    @Environment(AppState.self) private var appState
    @State private var profile: Profile?
    @State private var loading = true
    @State private var step: OnboardingStep = .username

    private enum OnboardingStep {
        case username
        case homeGym
        case youreIn
    }

    var body: some View {
        Group {
            if loading {
                ProgressView().controlSize(.large)
            } else if profile == nil {
                UsernameView(chosenProfile: Binding(
                    get: { profile },
                    set: { newProfile in
                        profile = newProfile
                        if newProfile != nil { step = .homeGym }
                    }
                ))
            } else {
                switch step {
                case .username:
                    // Profile already exists — skip straight to home gym
                    Color.clear.onAppear { step = .homeGym }

                case .homeGym:
                    HomeGymSetupView(
                        onSkip: { step = .youreIn },
                        onComplete: { step = .youreIn }
                    )

                case .youreIn:
                    YoureInView(
                        username: profile?.username ?? "",
                        onEnter: { appState.currentProfile = profile }
                    )
                }
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
