import SwiftUI
import UserNotifications

struct OnboardingCoordinator: View {
    let userID: UUID
    @Environment(AppState.self) private var appState
    @State private var profile: Profile?
    @State private var loading = true

    // Only set true when `profile` was just created via UsernameView in
    // this session — drives the home-gym + priming + welcome screens. A
    // `profile` loaded from `loadProfile()` (a returning user who already
    // completed onboarding previously) skips straight to completion, as
    // before.
    @State private var isNewSignup = false
    @State private var onboardingStep: OnboardingStep = .gym

    /// gym -> lifts -> priming -> welcome. Lifts (STEP 4 OF 4, owner
    /// 2026-08-12) collects confident 5-rep anchors for the primary
    /// compounds — skippable, seeds WorkingWeight's `.seeded` rung.
    /// Priming stays an unnumbered interstitial — see `advancePastLifts()`
    /// for the "skip entirely if authorization already determined" rule
    /// (task-6-brief.md).
    private enum OnboardingStep {
        case gym, lifts, priming, welcome
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
                        isNewSignup = newProfile != nil
                    }
                ))
            } else if isNewSignup, let p = profile {
                switch onboardingStep {
                case .gym:
                    HomeGymSetupView(isOnboarding: true, onAdvance: {
                        onboardingStep = .lifts
                    })
                case .lifts:
                    LiftAnchorsView(onAdvance: {
                        Task { await advancePastLifts() }
                    })
                case .priming:
                    PushPrimingView(isOnboarding: true, onAdvance: {
                        onboardingStep = .welcome
                    })
                case .welcome:
                    WelcomeView(profile: p) {
                        appState.currentProfile = p
                    }
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

    /// Skips the priming interstitial entirely when the user has already
    /// resolved the permission prompt through some other path (e.g. a
    /// reinstall where iOS remembers a prior decision) — only
    /// `.notDetermined` shows the priming screen, per task-6-brief.md.
    /// (Was `advancePastGym` — the lifts step now sits between gym and
    /// priming, so this decision moved one step later.)
    @MainActor
    private func advancePastLifts() async {
        await PushReceiver.shared.refreshAuthorizationStatus()
        onboardingStep = PushReceiver.shared.authorizationStatus == .notDetermined ? .priming : .welcome
    }
}
