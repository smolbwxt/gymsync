import HealthKit
import SwiftUI

struct YouTabView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    @State private var profile: Profile?
    @State private var workoutsLogged: Int = 0
    @State private var homeGymName: String?
    @State private var userSettings: UserSettings?
    @State private var showHomeGymSheet = false
    @State private var healthAuthStatus: HKAuthorizationStatus = .notDetermined
    @State private var errorText: String?
    @State private var showNotificationPrefs = false
    @State private var showAppearance = false
    @State private var showRestTimerSetting = false

    private var pushReceiver: PushReceiver { PushReceiver.shared }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        profileRow
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        statTileRow
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        GSSectionHeader("Settings")
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                            .padding(.bottom, 10)

                        settingsGroupBox
                            .padding(.horizontal, 16)

                        if let errorText {
                            Text(errorText)
                                .font(GSFont.body(13, relativeTo: .footnote))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        Spacer(minLength: 24)

                        signOutButton
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                    }
                    .frame(minHeight: proxy.size.height)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadData() }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task { await pushReceiver.refreshAuthorizationStatus() }
            }
            .sheet(isPresented: $showHomeGymSheet) {
                HomeGymSetupView(isOnboarding: false, onSaved: {
                    Task { await refreshHomeGymName() }
                })
            }
            .navigationDestination(isPresented: $showNotificationPrefs) {
                NotificationPreferencesView()
            }
            .navigationDestination(isPresented: $showAppearance) {
                AppearanceView(currentPaletteName: paletteDisplayName)
            }
            .navigationDestination(isPresented: $showRestTimerSetting) {
                RestTimerSettingView(currentSettings: effectiveUserSettings) { updated in
                    userSettings = updated
                }
            }
        }
    }

    // MARK: - Profile row
    //
    // Compact profile row per new-canvas-section.diff's "Settings Hub" frame:
    // 52pt avatar square, 17pt name, muted 12pt "@username", small INERT
    // "Edit" secondary button. Replaces the prior centered avatar card (60pt
    // avatar + "Member since ..." subtitle) — the diff specifies this exact
    // compact shape with no member-since text, so `memberSinceText` (the old
    // helper) was removed rather than left dead.

    @ViewBuilder
    private var profileRow: some View {
        let displayProfile = profile ?? appState.currentProfile
        HStack(spacing: 12) {
            Text(initials(for: displayProfile))
                .font(GSFont.heading(19, relativeTo: .title3))
                .foregroundColor(theme.bg)
                .frame(width: 52, height: 52)
                .background(theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: displayProfile))
                    .font(GSFont.heading(17, relativeTo: .headline))
                    .foregroundColor(theme.text)
                if let displayProfile {
                    Text("@\(displayProfile.username)")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundColor(theme.neutral700)
                }
            }

            Spacer()

            // INERT for now (recorded deviation — see task-2-report.md): Edit
            // Profile is a future screen. Present here for the hub's visual
            // completeness per the diff; tapping does nothing yet.
            Button {
                // no-op — Edit Profile screen not yet built.
            } label: {
                Text("Edit")
            }
            .buttonStyle(GSSecondaryButtonStyle(fontSize: 12, horizontalPadding: 12, verticalPadding: 6))
            .frame(minHeight: 44)
        }
    }

    private func initials(for profile: Profile?) -> String {
        guard let profile else { return "?" }
        let trimmedDisplayName = profile.displayName?.trimmingCharacters(in: .whitespaces)
        let source = (trimmedDisplayName?.isEmpty == false ? trimmedDisplayName : nil) ?? profile.username
        let words = source.split(separator: " ")
        if words.count >= 2 {
            return String(words.prefix(2).compactMap(\.first)).uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }

    /// Name text only — the "@username" subtitle is rendered as its own
    /// `Text` by `profileRow`, so (unlike the old avatar card's identically
    /// named helper) this no longer falls back to "@username" itself; it
    /// falls back to the bare username instead, to avoid showing the handle
    /// twice.
    private func displayName(for profile: Profile?) -> String {
        guard let profile else { return "" }
        if let name = profile.displayName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return profile.username
    }

    // MARK: - Stat Tiles
    //
    // Recorded deviation (per task brief): the diff's Settings Hub frame
    // omits these entirely, but they're recent parity work and
    // data-valuable — kept between the profile row and the Settings group,
    // flagged for designer review.

    private var statTileRow: some View {
        let displayProfile = profile ?? appState.currentProfile
        return HStack(spacing: 8) {
            GSStatTile(
                value: "\(StatMath.compactNumber(displayProfile?.lifetimeVolumeLifted ?? 0)) lbs",
                label: "Lifetime volume",
                valueFontSize: 18
            )
            GSStatTile(
                value: "\(workoutsLogged)",
                label: "Workouts logged",
                valueFontSize: 18
            )
        }
    }

    // MARK: - Settings group box
    //
    // 1px-bordered box (per the diff) with 4 rows — Appearance / Notifications
    // / Home Gym / Default rest timer — plus Apple Health Sync appended as a
    // 5th row.
    //
    // Recorded deviation: the diff's Settings Hub frame has no Apple Health
    // row at all, but it's the app's ONLY manual entry point to (re-)request
    // HealthKit authorization — `WorkoutSessionView.endSession()` only
    // re-prompts opportunistically during export, it never exposes a
    // settings toggle. Dropping this row would make that permission
    // undiscoverable with no other access point. Kept per the same
    // "recorded deviation, flag for designer" reasoning the brief already
    // applies to the stat tiles above. The old standalone "Theme" row is
    // fully superseded by "Appearance" (same info — current palette name —
    // now sourced from `user_settings` instead of a hardcoded "Midnight").

    @ViewBuilder
    private var settingsGroupBox: some View {
        VStack(spacing: 0) {
            GSSettingsRow(title: "Appearance", icon: "sun.max", value: paletteDisplayName) {
                showAppearance = true
            }
            GSSettingsRow(title: "Notifications", icon: "bell", value: notificationsStatusText) {
                showNotificationPrefs = true
            }
            GSSettingsRow(title: "Home Gym", icon: "mappin.and.ellipse", value: homeGymName ?? "Not set") {
                showHomeGymSheet = true
            }
            GSSettingsRow(
                title: "Default rest timer",
                icon: "timer",
                value: restTimerDisplayText
            ) {
                showRestTimerSetting = true
            }
            healthSyncRow
        }
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    private var paletteDisplayName: String {
        (userSettings?.palette ?? "midnight").capitalized
    }

    private var restTimerDisplayText: String {
        UserSettings.formatRestSeconds(userSettings?.defaultRestSeconds ?? 120)
    }

    /// Settings handed to `RestTimerSettingView` — falls back to
    /// `UserSettings.defaults` if `.task` hasn't resolved the real row yet.
    /// Safe even with a placeholder `userID`: `UserSettingsRepository.upsert`
    /// always re-derives the actual authenticated user id itself rather than
    /// trusting this struct's `userID` field.
    private var effectiveUserSettings: UserSettings {
        userSettings ?? UserSettings.defaults(userID: appState.currentProfile?.id ?? UUID())
    }

    private var notificationsStatusText: String {
        switch pushReceiver.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "On"
        case .denied, .notDetermined: return "Off"
        @unknown default: return "Off"
        }
    }

    /// Shows current authorization state as trailing text (not a chevron —
    /// this row isn't a navigation target). Tapping re-requests permission
    /// then refreshes the displayed state. Kept as a custom row (not
    /// `GSSettingsRow`) since it has no chevron and a different action
    /// shape; omits its own trailing divider since it's always the group
    /// box's last row (the box's own bottom border serves that edge).
    private var healthSyncRow: some View {
        Button {
            Task { await requestHealthPermission() }
        } label: {
            HStack {
                Text("Apple Health Sync")
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundColor(theme.text)
                Spacer()
                Text(healthAuthStatusText)
                    .font(GSFont.body(13, relativeTo: .caption))
                    .foregroundColor(theme.neutral700)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var healthAuthStatusText: String {
        switch healthAuthStatus {
        case .sharingAuthorized: return "Enabled"
        case .sharingDenied: return "Denied"
        case .notDetermined: return "Not Enabled"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Sign Out
    //
    // Canvas exception to the DS's flush-left button rule: centered label,
    // accent700 text, secondary (neutral300) border. Uses the promoted
    // GSSecondarySignOutButtonStyle (DesignSystem/GSComponents.swift).

    private var signOutButton: some View {
        Button {
            Task {
                do { try await auth.signOut() }
                catch { errorText = ErrorMapping.map(error).errorDescription }
            }
        } label: {
            Text("Sign Out")
        }
        .buttonStyle(GSSecondarySignOutButtonStyle())
    }

    // MARK: - Data loading

    @MainActor
    private func loadData() async {
        guard let userID = appState.currentProfile?.id else { return }

        async let profileFetch = ProfileRepository.refresh(userID: userID)
        async let historyFetch = SessionRepository.history(userID: userID, limit: 500)
        async let gymFetch = CheckInService.primaryGym()
        async let settingsFetch = UserSettingsRepository.get()

        if let fetched = try? await profileFetch {
            profile = fetched
            appState.currentProfile = fetched
        }
        if let history = try? await historyFetch {
            workoutsLogged = history.count
        }
        let gym = try? await gymFetch
        homeGymName = gym?.name
        userSettings = try? await settingsFetch

        healthAuthStatus = HealthKitBridge.store.authorizationStatus(for: .workoutType())
        await pushReceiver.refreshAuthorizationStatus()
    }

    private func requestHealthPermission() async {
        try? await HealthKitBridge.requestPermission()
        healthAuthStatus = HealthKitBridge.store.authorizationStatus(for: .workoutType())
    }

    /// Re-fetches the primary gym's name after the editor sheet saves, so
    /// the Home Gym settings row reflects the new value once the sheet
    /// dismisses (review note from Task 7: the row's name was only fetched
    /// once in `.task`).
    @MainActor
    private func refreshHomeGymName() async {
        let gym = try? await CheckInService.primaryGym()
        homeGymName = gym?.name
    }
}
