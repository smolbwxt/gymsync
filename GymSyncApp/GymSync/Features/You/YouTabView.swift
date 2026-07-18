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
    @State private var showEditProfile = false
    // Phase M Task 2 (moderation/compliance): You-tab Blocked Users list.
    @State private var showBlockedUsers = false
    // Phase M Task 4 (moderation/compliance): solo-workout privacy toggle +
    // Delete Account flow.
    @State private var showSoloWorkouts = false
    @State private var showDeleteAccount = false
    // Canvas Completion Task 5: singleton (matches `AppState.shared`'s
    // convention) so the Settings Hub's "Appearance" value preview reflects
    // the LIVE palette name (updates the instant `AppearanceView` calls
    // `ThemeStore.select(_:)`), independent of this view's own separately-
    // fetched `userSettings` (which only refreshes on `.task`/sheet-save).
    @State private var themeStore = ThemeStore.shared

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

                        deleteAccountRow
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

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
                AppearanceView()
            }
            .navigationDestination(isPresented: $showRestTimerSetting) {
                RestTimerSettingView(currentSettings: effectiveUserSettings) { updated in
                    userSettings = updated
                }
            }
            .navigationDestination(isPresented: $showEditProfile) {
                EditProfileView(profile: profile ?? appState.currentProfile) { updated in
                    profile = updated
                    appState.currentProfile = updated
                }
            }
            .navigationDestination(isPresented: $showBlockedUsers) {
                BlockedUsersView()
            }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountSheet()
            }
        }
    }

    // MARK: - Profile row
    //
    // Compact profile row per new-canvas-section.diff's "Settings Hub" frame:
    // 52pt avatar square, 17pt name, muted 12pt "@username", small "Edit"
    // secondary button. Replaces the prior centered avatar card (60pt
    // avatar + "Member since ..." subtitle) — the diff specifies this exact
    // compact shape with no member-since text, so `memberSinceText` (the old
    // helper) was removed rather than left dead.
    //
    // Phase F Task 6: "Edit Profile is a future screen" (task-2-report.md's
    // recorded deviation) is now fulfilled — the button pushes the real
    // `EditProfileView`, and the 52pt avatar square renders the real photo
    // via AsyncImage when one is set, initials otherwise.

    @ViewBuilder
    private var profileRow: some View {
        let displayProfile = profile ?? appState.currentProfile
        HStack(spacing: 12) {
            // Deliberately NOT routed through GSInitialsAvatar: this row's
            // initials use a displayName-priority, 2-char-single-word
            // algorithm (`initials(for:)` below) that diverges from
            // GSInitialsAvatar's plain name-split (which would collapse a
            // single-word username like "alex_j" to 1 char, "A", instead of
            // this row's existing "AL") — and its own 19pt `.heading` font
            // differs from GSInitialsAvatar's fixed `size * 0.31 .bold`
            // formula. Reusing the shared component here would have quietly
            // changed both the initials and the typography. Same
            // AsyncImage-with-initials-placeholder idiom as GSInitialsAvatar
            // (and the group-avatar flow it was upgraded from), just kept
            // local so this row's own algorithm/font stay intact.
            Group {
                if let url = displayProfile?.avatarURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        avatarInitials(displayProfile)
                    }
                    .frame(width: 52, height: 52)
                    .clipped()
                } else {
                    avatarInitials(displayProfile)
                }
            }

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

            Button {
                showEditProfile = true
            } label: {
                Text("Edit")
            }
            .buttonStyle(GSSecondaryButtonStyle(fontSize: 12, horizontalPadding: 12, verticalPadding: 6))
            .frame(minHeight: 44)
        }
    }

    private func avatarInitials(_ profile: Profile?) -> some View {
        Text(initials(for: profile))
            .font(GSFont.heading(19, relativeTo: .title3))
            .foregroundColor(theme.bg)
            .frame(width: 52, height: 52)
            .background(theme.accent)
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
            GSSettingsRow(title: "Blocked Users", icon: "person.crop.circle.badge.xmark") {
                showBlockedUsers = true
            }
            soloPrivacyRow
            healthSyncRow
        }
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    // MARK: - Solo-workout privacy toggle (Phase M Task 4)
    //
    // Same bordered-row-with-caption shape as RoutineBuilderView's
    // publishToggleRow (Library/RoutineBuilderView.swift:165-183) — label +
    // explanatory footer line to the left, GSToggle to the right — the
    // established "toggle row with an inline caption" idiom in this
    // codebase, rather than NotificationPreferencesView's single-line
    // toggleRow (that screen's captions are a single shared line below the
    // whole group, not per-row). Reads/writes `profiles.show_solo_workouts`
    // directly (owner-RLS, ProfileRepository.updateShowSoloWorkouts) — the
    // flag the new set_logs SELECT policy
    // (20260722000002_solo_workout_privacy.sql) checks before letting an
    // accepted friend see this user's SOLO (single-participant) session
    // set_logs; group-session set_logs are unaffected by this toggle either
    // way.
    private var soloPrivacyRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Share Solo Workouts")
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundColor(theme.text)
                Text("Let friends see your solo workouts")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundColor(theme.neutral700)
            }
            Spacer(minLength: 8)
            GSToggle(
                isOn: Binding(
                    get: { showSoloWorkouts },
                    set: { setShowSoloWorkouts($0) }
                ),
                label: "Share Solo Workouts"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    /// Optimistic update (matches NotificationPreferencesView.setEnabled's
    /// shape) — flips the local toggle immediately, reverts + surfaces
    /// `errorText` if the write fails.
    private func setShowSoloWorkouts(_ enabled: Bool) {
        let previous = showSoloWorkouts
        showSoloWorkouts = enabled
        Task {
            do {
                let updated = try await ProfileRepository.updateShowSoloWorkouts(enabled)
                await MainActor.run {
                    profile = updated
                    appState.currentProfile = updated
                }
            } catch {
                await MainActor.run {
                    showSoloWorkouts = previous
                    errorText = ErrorMapping.map(error).errorDescription
                }
            }
        }
    }

    // MARK: - Delete Account (Phase M Task 4 — App Store 5.1.1)
    //
    // Destructive row, deliberately kept OUTSIDE settingsGroupBox above —
    // every row in that box is a safe, reversible preference; this one is
    // not. Red icon + text signal irreversibility (no themed "danger" color
    // token exists in GSTheme — this codebase's established precedent for
    // destructive/error state is plain `.red`, e.g. ReportSheet's and this
    // screen's own `errorText` styling). A single tap only opens
    // `DeleteAccountSheet`'s typed-confirmation flow — it never deletes
    // anything itself.
    private var deleteAccountRow: some View {
        Button {
            showDeleteAccount = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.red)
                Text("Delete Account")
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundColor(.red)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.surface)
            .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Reads the live `ThemeStore` (not `userSettings.palette`) so this row
    /// updates the instant a selection is made in `AppearanceView`, without
    /// waiting for `YouTabView`'s own `.task` to re-fetch `user_settings`.
    private var paletteDisplayName: String {
        GSPalettes.name(for: themeStore.paletteID)
    }

    private var restTimerDisplayText: String {
        UserSettings.formatRestSeconds(userSettings?.defaultRestSeconds ?? 120)
    }

    /// Settings handed to `RestTimerSettingView` — falls back to
    /// `UserSettings.defaults` if `.task` hasn't resolved the real row yet.
    /// Safe even with a placeholder `userID`: `UserSettingsRepository.upsert`
    /// always re-derives the actual authenticated user id itself rather than
    /// trusting this struct's `userID` field.
    ///
    /// Fix round B1 (final review blocker): always overwrites `.palette`
    /// with the LIVE `themeStore.paletteID` rather than trusting
    /// `userSettings.palette` — this view's own cache, which only refreshes
    /// on `.task`/sheet-save and can lag a palette change made in
    /// `AppearanceView` during the same Settings visit. Without this,
    /// pushing `RestTimerSettingView` right after changing the palette would
    /// hand it a stale palette value; its own full-row upsert on save would
    /// then write that stale value back to `user_settings`, silently
    /// reverting the just-made palette change in the DB (invisible until
    /// relaunch). See `ThemeStore.noteExternalSettingsWrite` for the
    /// mirror-image fix in the other direction (rest-then-palette).
    private var effectiveUserSettings: UserSettings {
        var settings = userSettings ?? UserSettings.defaults(userID: appState.currentProfile?.id ?? UUID())
        settings.palette = themeStore.paletteID
        return settings
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
            showSoloWorkouts = fetched.showSoloWorkouts
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
