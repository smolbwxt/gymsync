import SwiftUI
import UserNotifications

/// Push notification permission priming interstitial (Designer brief
/// Feature 1, Dossier §A.7) — reuses the mic permission priming frame's
/// visual pattern (accent-filled square + icon, headline, bullets, CTA
/// stack) with `bell.badge` iconography; the bell variant is not separately
/// designed (recorded assumption per task-6-brief.md).
///
/// `isOnboarding` mirrors `HomeGymSetupView`'s pattern: `true` when shown
/// directly by `OnboardingCoordinator` (no surrounding `NavigationStack`, so
/// there's no system back button to worry about); `false` for a
/// nav-pushed re-entry from the You tab, where the system back button shows
/// automatically because the caller pushes it inside a `NavigationStack`.
///
/// NOTE: per task-6-brief.md, `YouTabView`'s "Notifications" row currently
/// pushes `NotificationPreferencesView` directly (its own system-denied
/// banner + "Open Settings" serves as the "re-entry when denied" surface),
/// not this view. The `isOnboarding: false` path below is implemented to
/// the full contract (denied variant, visible back button, no "Not now")
/// for completeness/future wiring, but has no current production call site
/// — documented in task-6-report.md.
struct PushPrimingView: View {
    var isOnboarding: Bool = true

    /// Onboarding only: called for "Not now", a granted prompt, and (when
    /// denied) the onboarding-only "Continue" button — advances to the next
    /// onboarding screen. Re-entry mode (`isOnboarding == false`) ignores
    /// this and dismisses (pops) instead, mirroring HomeGymSetupView.
    var onAdvance: (() -> Void)?

    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var isRequesting = false

    private var pushReceiver: PushReceiver { PushReceiver.shared }

    private var isDenied: Bool {
        pushReceiver.authorizationStatus == .denied
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    iconBadge
                        .padding(.horizontal, 20)
                        .padding(.top, isOnboarding ? 72 : 32)

                    if isDenied {
                        deniedContent
                    } else {
                        prePromptContent
                    }

                    Spacer().frame(height: 120)
                }
            }

            footer
        }
        .navigationBarBackButtonHidden(isOnboarding)
        // Full-screen interstitial with its own bottom CTA stack — see
        // GSComponents.swift's GSHidesDock. No-op during onboarding, since
        // OnboardingCoordinator renders outside MainTabView's dock entirely.
        .gsHidesDock()
        .task { await checkInitialState() }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await handleForegroundReturn() }
        }
    }

    // MARK: - Icon badge

    private var iconBadge: some View {
        ZStack {
            Rectangle().fill(theme.accent).frame(width: 64, height: 64)
            Image(systemName: "bell.badge")
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(theme.bg)
        }
    }

    // MARK: - Pre-prompt state

    private var prePromptContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Never miss your turn on the bar")
                .font(GSFont.bold(28, relativeTo: .title))
                .foregroundColor(theme.text)
                .padding(.horizontal, 20)
                .padding(.top, 24)

            Text("Gym Sync uses notifications to keep you in the loop during sessions and with your crew.")
                .font(GSFont.body(14, relativeTo: .subheadline))
                .foregroundColor(theme.neutral700)
                .padding(.horizontal, 20)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 14) {
                benefitRow("Get pinged the second the lobby opens")
                benefitRow("Know instantly when it's your turn")
                benefitRow("Never miss a friend request")
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(theme.accent)
            Text(text)
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundColor(theme.text)
        }
    }

    // MARK: - Denied state

    private var deniedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notifications are off")
                .font(GSFont.bold(28, relativeTo: .title))
                .foregroundColor(theme.text)
                .padding(.horizontal, 20)
                .padding(.top, 24)

            Text("You can turn them on anytime in iOS Settings.")
                .font(GSFont.body(14, relativeTo: .subheadline))
                .foregroundColor(theme.neutral700)
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 0) {
            GSDivider()
            VStack(spacing: 10) {
                if isDenied {
                    Button {
                        openSettings()
                    } label: {
                        Text("Open Settings").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GSPrimaryButtonStyle())
                    .frame(minHeight: 44)

                    // DECISION (documented in task-6-report.md): the brief
                    // explicitly omits "Not now" from the denied state
                    // ("nothing to defer"), but onboarding has no back
                    // button, so a denied user would otherwise be stuck with
                    // only "Open Settings" and no way to proceed. "Continue"
                    // is deliberately NOT "Not now": it doesn't skip a
                    // still-pending decision (the decision — denied — is
                    // already resolved), it just moves onboarding forward.
                    // Re-entry mode (isOnboarding: false) omits this button
                    // because the system back button already provides an
                    // exit, matching the brief's "no Not now" rule exactly.
                    if isOnboarding {
                        Button {
                            advance()
                        } label: {
                            Text("Continue").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GSGhostButtonStyle())
                        .frame(minHeight: 44)
                    }
                } else {
                    Button {
                        Task { await handleTurnOn() }
                    } label: {
                        if isRequesting {
                            ProgressView().tint(theme.bg)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Turn on notifications").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(GSPrimaryButtonStyle())
                    .frame(minHeight: 44)
                    .disabled(isRequesting)

                    Button {
                        advance()
                    } label: {
                        Text("Not now").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GSGhostButtonStyle())
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(.bottom, 22)
        }
        .background(theme.bg)
    }

    // MARK: - Actions

    private func advance() {
        if isOnboarding {
            onAdvance?()
        } else {
            dismiss()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    private func handleTurnOn() async {
        isRequesting = true
        defer { isRequesting = false }
        let granted = await pushReceiver.requestAuthorization()
        if granted {
            await pushReceiver.registerTokenIfAuthorized()
            advance()
        }
        // Denial falls through with no further action here: authorizationStatus
        // is now .denied on the @Observable PushReceiver, and `isDenied`
        // reads it directly, so the view re-renders into the denied state
        // automatically.
    }

    /// Covers the "granted (auto-advance silently)" state on mount — mostly
    /// a defensive re-check, since `OnboardingCoordinator` already skips
    /// this screen entirely when authorization is already determined.
    @MainActor
    private func checkInitialState() async {
        await pushReceiver.refreshAuthorizationStatus()
        if pushReceiver.authorizationStatus == .authorized {
            await pushReceiver.registerTokenIfAuthorized()
            advance()
        }
    }

    /// "Still advanceable after returning" (task-6-brief.md): re-checks
    /// authorization whenever the app returns to foreground (covers
    /// returning from "Open Settings") and silently auto-advances if the
    /// user granted it there — the same behavior as granting via the native
    /// prompt. If still denied, the onboarding-only "Continue" button (or,
    /// in re-entry mode, the back button) remains the way forward.
    @MainActor
    private func handleForegroundReturn() async {
        guard isDenied else { return }
        await pushReceiver.refreshAuthorizationStatus()
        if pushReceiver.authorizationStatus == .authorized {
            await pushReceiver.registerTokenIfAuthorized()
            advance()
        }
    }
}
