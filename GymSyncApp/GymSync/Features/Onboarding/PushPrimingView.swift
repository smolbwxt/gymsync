import SwiftUI
import UserNotifications

/// Push notification permission priming interstitial (Designer brief
/// Feature 1, Dossier §A.7; redrawn per new-canvas-section.diff's "Notif
/// Priming" / "Notif · Denied" frames, Jul 2026 — Canvas Completion Task 1).
///
/// `isOnboarding` mirrors `HomeGymSetupView`'s pattern: `true` when shown
/// directly by `OnboardingCoordinator` (no surrounding `NavigationStack`, so
/// there's no system back button to worry about); `false` for a nav-pushed
/// re-entry from the You tab's Notifications preferences screen (see
/// `NotificationPreferencesView.deniedBanner`'s "Open" action).
///
/// The system back button is hidden unconditionally now — the canvas draws
/// its own small back-arrow affordance (30x30, 44pt hit target) rather than
/// relying on system nav-bar chrome, and per Designer ruling #1 ("small
/// drawn boxes, 44pt invisible hit areas") we match that for the ONE case
/// where a back button is reachable at all: the denied state in re-entry
/// mode. Onboarding never shows a back button (nothing to go back to from
/// this screen in the onboarding step machine — matches the pre-existing
/// "Continue" reasoning below).
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

    #if DEBUG
    /// Debug-only: when true (screen catalog only, via the fixture init
    /// below), `body`'s `.task` skips `checkInitialState()`'s live
    /// UNUserNotificationCenter query, which would otherwise immediately
    /// overwrite a forced `PushReceiver.shared.authorizationStatus` with the
    /// simulator's real permission decision. Always false in every other
    /// path (including normal debug builds); compiled out of release
    /// entirely.
    var catalogSkipCheckInitialState = false
    #endif

    private var pushReceiver: PushReceiver { PushReceiver.shared }

    private var isDenied: Bool {
        pushReceiver.authorizationStatus == .denied
    }

    // Fix wave 1 (Task 6 review, scope correction from CI run 29679007547 on
    // b358748): `isRestricted`/`isBlocked`/`restrictedContent` (added by
    // b88ec93 for the original "`.restricted` auth status falls to
    // pre-prompt branch" audit item) are REMOVED here — the item's premise
    // was a false API assumption. `PushReceiver.authorizationStatus` is
    // `UNUserNotificationCenter`'s `UNAuthorizationStatus`
    // (Services/PushReceiver.swift:16), whose full case list is
    // `.notDetermined`, `.denied`, `.authorized`, `.provisional`,
    // `.ephemeral` — there is no `.restricted` case. (`.restricted` is a
    // real case on `CLAuthorizationStatus` in Core Location, which is
    // almost certainly how the original audit note's wording got crossed
    // with this framework.) `pushReceiver.authorizationStatus ==
    // .restricted` therefore does not compile
    // ("type 'UNAuthorizationStatus' has no member 'restricted'"). Reverted
    // to the pre-b88ec93 `isDenied`-only gating throughout this file; see
    // task-6-report.md's "Fix wave 1" section for the full writeup.
    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Drawn back affordance — denied + re-entry only (see
                    // type doc). Onboarding-denied keeps its "Continue"
                    // ghost button in the footer instead.
                    if isDenied && !isOnboarding {
                        backButton
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                    }

                    iconBadge
                        .padding(.horizontal, 20)
                        .padding(.top, iconBadgeTopPadding)

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
        .navigationBarBackButtonHidden(true)
        // Full-screen interstitial with its own bottom CTA stack — see
        // GSComponents.swift's GSHidesDock. No-op during onboarding, since
        // OnboardingCoordinator renders outside MainTabView's dock entirely.
        .gsHidesDock()
        .task {
            #if DEBUG
            if catalogSkipCheckInitialState { return }
            #endif
            await checkInitialState()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await handleForegroundReturn() }
        }
    }

    // MARK: - Back button (denied + re-entry only)

    private var backButton: some View {
        Button {
            advance()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(theme.text)
                .frame(width: 30, height: 30)
                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    private var iconBadgeTopPadding: CGFloat {
        // When the back-button row is present, it already carries the
        // screen's top spacing — the badge only needs a small gap under it.
        if isDenied && !isOnboarding { return 20 }
        return isOnboarding ? 72 : 32
    }

    // MARK: - Icon badge

    @ViewBuilder
    private var iconBadge: some View {
        if isDenied {
            ZStack {
                Rectangle()
                    .strokeBorder(theme.divider, lineWidth: 2)
                    .frame(width: 60, height: 60)
                Image(systemName: "bell.slash")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(theme.text.opacity(0.5))
            }
        } else {
            ZStack {
                Rectangle().fill(theme.accent).frame(width: 60, height: 60)
                Image(systemName: "bell")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(theme.bg)
            }
        }
    }

    // MARK: - Pre-prompt state

    private var prePromptContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Never miss your turn on the bar")
                .font(GSFont.bold(34, relativeTo: .title))
                .foregroundColor(theme.text)
                .padding(.horizontal, 20)
                .padding(.top, 22)

            Text("We'll ping you only for the things that matter mid-training. You can fine-tune every category later.")
                .font(GSFont.body(15, relativeTo: .subheadline))
                .foregroundColor(theme.neutral700)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 10) {
                benefitRow("A heads-up when the lobby opens")
                benefitRow("A nudge the moment it's your turn")
                benefitRow("A ping when a friend adds you")
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
        }
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(theme.accent700)
            Text(text)
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundColor(theme.text)
        }
    }

    // MARK: - Denied state

    private var deniedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notifications are off")
                .font(GSFont.bold(34, relativeTo: .title))
                .foregroundColor(theme.text)
                .padding(.horizontal, 20)
                .padding(.top, 24)

            Text("Turn them back on in iOS Settings to get turn alerts, session reminders, and friend pings. Your category preferences are saved and waiting.")
                .font(GSFont.body(15, relativeTo: .subheadline))
                .foregroundColor(theme.neutral700)
                .padding(.horizontal, 20)
                .padding(.top, 14)
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
                        HStack {
                            Text("Open Settings")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 14))
                    .frame(minHeight: 44)

                    // DECISION (documented in task-1-report.md): the canvas
                    // frame for "Notif · Denied" shows only "Open Settings"
                    // — it's designed around the re-entry use case, which
                    // always has the drawn back button above as its exit.
                    // Onboarding has no such back button (nothing to go
                    // back to in the onboarding step machine), so it keeps
                    // "Continue" as its way forward — same reasoning as
                    // shipped v1, preserved rather than removed.
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
                    .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 14))
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
    /// in re-entry mode, the drawn back button) remains the way forward.
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

#if DEBUG
extension PushPrimingView {
    /// Debug-only seam for the design-parity screen catalog (Task 4): forces
    /// `PushReceiver.shared.authorizationStatus` (via the `debugSet
    /// AuthorizationStatus(_:)` seam on PushReceiver.swift) and skips
    /// `checkInitialState()` (see `catalogSkipCheckInitialState` above), so
    /// `CatalogHostView` can render the pre-prompt and denied states
    /// deterministically. Added here (rather than in CatalogHostView.swift)
    /// because `_isRequesting` is `private` @State — this extension can
    /// touch it only because it lives in the SAME FILE as that declaration.
    /// Compiled out of release entirely.
    init(catalogAuthorizationStatus status: UNAuthorizationStatus) {
        self.init(isOnboarding: true)
        PushReceiver.shared.debugSetAuthorizationStatus(status)
        catalogSkipCheckInitialState = true
    }
}
#endif
