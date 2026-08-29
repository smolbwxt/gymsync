import SwiftUI
import UserNotifications

struct OnboardingCoordinator: View {
    let userID: UUID
    @Environment(AppState.self) private var appState
    @State private var profile: Profile?
    @State private var loading = true

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
                    set: { newProfile in profile = newProfile }
                ))
            } else if let p = profile, p.onboardedAt == nil {
                // O1 (2026-08-28, review-critical): "needs onboarding" is
                // the DURABLE profiles.onboarded_at, not process memory.
                // The old @State isNewSignup meant killing the app after
                // username creation skipped screens 2-4 and the Coach
                // offer forever; now a half-finished signup RESUMES here
                // (every step is skippable, so re-showing them is cheap).
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
                        // The durable end of the arc - a kill anywhere
                        // before this stamp resumes onboarding instead of
                        // skipping it forever. Best-effort: a failed stamp
                        // re-shows skippable screens once, which is
                        // cheaper than the inverse.
                        Task { try? await ProfileRepository.markOnboarded() }
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
            // Setting currentProfile routes to the main app (RootView
            // switches on it) - so only an ONBOARDED profile may set it.
            // This line was O1's actual escape hatch: it fired the moment
            // a username row existed.
            if let p = profile, p.onboardedAt != nil {
                appState.currentProfile = p
            }
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
