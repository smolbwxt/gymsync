import EventKit
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
    // Phase H Task 2: "Add my sessions to Calendar" toggle state.
    @State private var calendarSyncEnabled = false
    @State private var calendarAuthStatus: EKAuthorizationStatus = .notDetermined
    @State private var errorText: String?
    @State private var showNotificationPrefs = false
    @State private var showAppearance = false
    /// QA tools (curator-gated): how many one-shot flags are currently set,
    /// and a transient tick on the reset button.
    @State private var qaSeenCount = 0
    @State private var qaResetConfirmed = false
    @AppStorage(GuidanceTip.tipsEnabledKey) private var tipsEnabled = true
    @State private var showRestTimerSetting = false
    @State private var showGymEquipment = false
    @State private var showHeartRateMonitor = false
    @State private var showEditProfile = false
    // Phase M Task 2 (moderation/compliance): You-tab Blocked Users list.
    @State private var showBlockedUsers = false
    // Phase M Task 4 (moderation/compliance): solo-workout privacy toggle +
    // Delete Account flow.
    @State private var showSoloWorkouts = false
    // Phase W Task 4 (watch-hr design §4): "Share heart rate in live
    // sessions" opt-in — `user_settings.share_heart_rate`. Populated from
    // `userSettings?.shareHeartRate` in `loadData()`, same "dedicated local
    // @State bool for an inline toggle" shape as `showSoloWorkouts` above.
    @State private var shareHeartRate = false
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
                        // Redesign v2: in-content title replaces the nav-bar title.
                        Text("You")
                            .font(GSFont.heading(24, relativeTo: .title))
                            .foregroundStyle(theme.text)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)

                        profileRow
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        statTileRow
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        GSSectionHeader("Settings")
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                            .padding(.bottom, 10)

                        settingsGroupBox
                            .padding(.horizontal, 16)

                        // QA tools — curator accounts only. NOT `#if DEBUG`:
                        // QA happens on TestFlight, which ships RELEASE
                        // builds, so a compile-time gate would make this
                        // invisible exactly where it's needed. `is_curator`
                        // is already RLS-protected against self-promotion
                        // (20260717000003) and revocable server-side without
                        // shipping a build.
                        if appState.currentProfile?.isCurator == true {
                            GSSectionHeader("QA tools")
                                .padding(.horizontal, 16)
                                .padding(.top, 24)
                                .padding(.bottom, 10)
                            qaToolsGroupBox
                                .padding(.horizontal, 16)
                        }

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
                    // Top-pinned: a bare .frame(minHeight:) centers short
                    // content vertically (the Social center-snap bug class).
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                // Dock clearance (user bug report).
                .contentMargins(.bottom, 88, for: .scrollContent)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .toolbar(.hidden, for: .navigationBar)   // redesign v2: in-content title above
            .task { await loadData() }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task { await pushReceiver.refreshAuthorizationStatus() }
                // Phase H Task 2: catch a Calendar permission change made in
                // Settings while this screen was backgrounded — same
                // re-check-on-foreground idiom as the push status refresh
                // above and NotificationPreferencesView's own
                // scenePhase-driven refresh.
                calendarAuthStatus = EventKitBridge.authorizationStatus()
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
            .navigationDestination(isPresented: $showGymEquipment) {
                GymEquipmentView(currentSettings: effectiveUserSettings) { updated in
                    userSettings = updated
                }
            }
            .navigationDestination(isPresented: $showHeartRateMonitor) {
                HeartRateMonitorView()
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
    /// Units (kg/lbs). STORED WEIGHTS STAY POUNDS — this changes display
    /// and entry only (Models/Units.swift), which is why flipping it is
    /// instant and safe: no data is rewritten. Persists through the full
    /// UserSettings upsert; ThemeStore.noteExternalSettingsWrite keeps the
    /// theme cache's copy consistent (its merge adopts unitSystem).
    private var unitsRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Units")
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundColor(theme.text)
                Text("Weights show in \(effectiveUserSettings.weightUnit == .kg ? "kilograms" : "pounds") everywhere")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundColor(theme.neutral700)
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                ForEach(WeightUnit.allCases, id: \.self) { candidate in
                    Button {
                        setUnitSystem(candidate)
                    } label: {
                        Text(candidate.label)
                            .font(GSFont.bold(12, relativeTo: .caption))
                            .foregroundStyle(effectiveUserSettings.weightUnit == candidate ? theme.bg : theme.neutral700)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(effectiveUserSettings.weightUnit == candidate ? theme.accent : Color.clear)
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(theme.bg)
            .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.divider).frame(height: 1) }
    }

    /// "45 lbs bar · standard plates" / "20 kg bar · 5 plates" — the
    /// Settings row's value preview.
    private var gymEquipmentPreview: String {
        let settings = effectiveUserSettings
        let unit = settings.weightUnit
        var barInUnit = Units.fromPounds(settings.barWeightLbs, to: unit)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &barInUnit, 2, .plain)
        let bar = "\(GSBarLoader.plateLabel(rounded)) \(unit.label) bar"
        if let custom = settings.plateInventory {
            return "\(bar) · \(custom.count) plates"
        }
        return "\(bar) · standard plates"
    }

    private func setUnitSystem(_ unit: WeightUnit) {
        var updated = effectiveUserSettings
        guard updated.unitSystem != unit.rawValue else { return }
        updated.unitSystem = unit.rawValue
        userSettings = updated   // optimistic — display flips immediately
        Task {
            do {
                try await UserSettingsRepository.upsert(updated)
                ThemeStore.shared.noteExternalSettingsWrite(updated)
            } catch {
                errorText = ErrorMapping.map(error).errorDescription
            }
        }
    }

    /// Global off switch for the first-visit spotlights. Device-local
    /// (`@AppStorage`) for the same reason their seen-flags are — this is
    /// per-device UI state, not account data.
    private var showTipsRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show tips")
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundColor(theme.text)
                Text("Brief pointers the first time you open a screen")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundColor(theme.neutral700)
            }
            Spacer(minLength: 8)
            GSToggle(isOn: $tipsEnabled, label: "Show tips")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.divider).frame(height: 1) }
    }

    // MARK: - QA tools (curator-gated)

    /// Replays the first-run experience on this device: clears every
    /// registered one-shot flag (`OneShotFlags`) so the walkthrough, coach
    /// marks, advisories — and, once they ship, the guidance spotlights —
    /// all show again. Local-only: nothing about the account changes, so
    /// this is safe to press repeatedly and affects no other device.
    private var qaToolsGroupBox: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replay first-run tips")
                        .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                        .foregroundColor(theme.text)
                    Text(qaFlagsSubtitle)
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundColor(theme.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    OneShotFlags.resetAll()
                    // Recompute the subtitle and confirm — without this the
                    // row would look identical after a successful reset,
                    // which reads as "the button did nothing".
                    qaSeenCount = OneShotFlags.seenCount
                    qaResetConfirmed = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        qaResetConfirmed = false
                    }
                } label: {
                    Text(qaResetConfirmed ? "Reset ✓" : "Reset")
                        .font(GSFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(theme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: GSMetrics.radiusMd)
                .strokeBorder(theme.divider, lineWidth: 1)
        )
        .onAppear { qaSeenCount = OneShotFlags.seenCount }
    }

    private var qaFlagsSubtitle: String {
        let total = OneShotFlags.all.count
        if qaSeenCount == 0 { return "All \(total) tips are already unseen — restart the app to replay." }
        return "\(qaSeenCount) of \(total) already seen. Resetting replays them (walkthrough shows on next launch)."
    }

    private var settingsGroupBox: some View {
        VStack(spacing: 0) {
            GSSettingsRow(title: "Appearance", icon: "sun.max", value: paletteDisplayName) {
                showAppearance = true
            }
            // Accent/palette customization is genuinely buried — a settings
            // row inside a group box. cornerRadius 0: this row sits mid-stack
            // in a clipped container, so a rounded outline would float.
            .gsDiscovery(.youAppearance, cornerRadius: 0)
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
            unitsRow
            GSSettingsRow(title: "Gym equipment", icon: "scalemass",
                          value: gymEquipmentPreview) {
                showGymEquipment = true
            }
            GSSettingsRow(title: "Heart rate monitor", icon: "heart",
                          value: BLEHeartRateService.shared.hasRememberedDevice ? "Paired" : "Not set") {
                showHeartRateMonitor = true
            }
            showTipsRow
            soloPrivacyRow
            heartRateShareRow
            healthSyncRow
            calendarSyncRow
        }
        // Redesign: rounded settings group — the container clips the rows'
        // square surface fills, so the group reads as one rounded widget.
        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusMd).strokeBorder(theme.divider, lineWidth: 1))
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

    // MARK: - Heart rate broadcast opt-in (Phase W Task 4, watch-hr design §4)
    //
    // "Share heart rate in live sessions" — same bordered toggle-row-with-
    // inline-caption shape as `soloPrivacyRow` above (this codebase's
    // established idiom for a single boolean preference with an explanatory
    // footer line, `soloPrivacyRow`'s own doc comment). The footer copy
    // states the privacy contract plainly, per the design doc's EPHEMERAL
    // LAW (§4/§6.5): broadcast only while in a live session, visible to
    // session participants, never stored.
    //
    // Persists to `user_settings.share_heart_rate`
    // (`supabase/migrations/20260727000001_user_settings_share_heart_rate.sql`)
    // — NOT `profiles`, where the master spec's Data Model section literally
    // lists this column (`docs/superpowers/specs/2026-06-28-gymsync-design.md:185`).
    // See that migration's own header comment and task-4-report.md for the
    // recorded placement deviation: `user_settings` is this codebase's
    // ACTUAL "single settings row per user" home for opt-in toggles today.
    //
    // Enabling this toggle does NOT prompt for any permission on the phone —
    // HealthKit heart-rate read authorization is requested WATCH-side, only
    // when the Watch actually starts sampling for a live session (T5 scope,
    // design §6.5 "Watch side": "the watchOS app runs an HKAnchoredObjectQuery
    // ... for the duration of the session"). This row is a pure preference
    // write — no permission code in this task, matching `WatchHRSamplePayload`'s
    // own "T5 concern" framing (`GymSyncShared/WatchEnvelope.swift`).
    private var heartRateShareRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Share heart rate in live sessions")
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundColor(theme.text)
                Text("Broadcast only while you're in a live session, visible to session participants, never stored")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundColor(theme.neutral700)
            }
            Spacer(minLength: 8)
            GSToggle(
                isOn: Binding(
                    get: { shareHeartRate },
                    set: { setShareHeartRate($0) }
                ),
                label: "Share heart rate in live sessions"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    /// Optimistic flip (matches `setShowSoloWorkouts`'s shape), but persists
    /// through `user_settings`'s established full-row-upsert discipline
    /// rather than a `profiles`-style targeted column update — this column
    /// lives on a different table, which has no genuine targeted-column
    /// UPDATE helper the way `ProfileRepository.updateShowSoloWorkouts`
    /// does (`Models/Profile.swift:204-221`); the brief's own instruction is
    /// "targeted-column pattern if one exists, or the established safe
    /// idiom" — none exists for `user_settings`, so this follows the
    /// established SAFE idiom instead, exactly mirroring
    /// `RestTimerSettingView.select(_:)` (`Features/You/RestTimerSettingView.swift:171-191`):
    /// build `updated` from `effectiveUserSettings` (the SAME live-palette-
    /// carrying base that view uses — see that computed property's own doc
    /// comment) with only `.shareHeartRate` mutated, full-row `upsert`, then
    /// — on success — call `ThemeStore.shared.noteExternalSettingsWrite(updated)`
    /// so `ThemeStore`'s cached row doesn't go stale and clobber this
    /// toggle's value back on the next palette `select(_:)` upsert (see
    /// `ThemeStore.mergeExternalSettingsWrite`'s Task-4 extension,
    /// `DesignSystem/ThemeStore.swift`, for the corresponding merge-rule
    /// change that makes this safe).
    private func setShareHeartRate(_ enabled: Bool) {
        let previous = shareHeartRate
        shareHeartRate = enabled
        Task {
            do {
                var updated = effectiveUserSettings
                updated.shareHeartRate = enabled
                try await UserSettingsRepository.upsert(updated)
                await MainActor.run {
                    ThemeStore.shared.noteExternalSettingsWrite(updated)
                    userSettings = updated
                }
            } catch {
                await MainActor.run {
                    shareHeartRate = previous
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
            .cornerRadius(GSMetrics.radiusSm)
            .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
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

    /// Settings handed to `RestTimerSettingView` (and, as of Phase W Task 4,
    /// the base row `setShareHeartRate` upserts from too) — falls back to
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
    /// mirror-image fix in the other direction (rest-then-palette) — every
    /// NEW full-row-upsert call site built on this property (Task 4's
    /// `setShareHeartRate` included) must call `noteExternalSettingsWrite`
    /// on success for the identical reason `RestTimerSettingView` does.
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
    /// shape. Phase H Task 2: this is no longer the group box's last row
    /// (`calendarSyncRow` was appended below it), so it now draws its own
    /// trailing divider instead of relying on the box's bottom border.
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
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.divider).frame(height: 1)
            }
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

    // MARK: - Calendar sync toggle (Phase H Task 2)
    //
    // "Add my sessions to Calendar" — gates every `EventKitBridge` write
    // (`CalendarSyncPrefsStore.isEnabled()`, checked at the schedule/
    // reschedule/cancel call sites in `ScheduleSessionView`/`LobbyView`).
    // Default OFF (`CalendarSyncPrefsStore.isEnabled()` returns false until
    // this row is ever turned on) — no permission prompt fires anywhere in
    // the app except this row's own enable action, matching the same
    // discipline `healthSyncRow` above and every push-priming surface
    // already follow.
    //
    // Two render states:
    //  - Normal (not yet denied by iOS): the same bordered
    //    toggle-row-with-inline-caption shape as `soloPrivacyRow` above.
    //  - System-denied: the ENTIRE row becomes one "open Settings" tap
    //    target, borrowing `PTTDockRow.deniedRow`'s shape exactly
    //    (`DesignSystem/GSComponents.swift:1407-1433` — icon + title +
    //    trailing arrow.up.right, whole row tappable). That idiom (rather
    //    than `NotificationPreferencesView.deniedBanner`'s separate
    //    banner-above-the-group shape) fits here because this toggle is a
    //    single settings-group row, not a whole screen — collapsing the
    //    denied state INTO the row matches its scale.
    @ViewBuilder
    private var calendarSyncRow: some View {
        if calendarAuthStatus == .denied || calendarAuthStatus == .restricted {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add my sessions to Calendar")
                            .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                            .foregroundColor(theme.text)
                        Text("Calendar access off — turn on in Settings")
                            .font(GSFont.body(11, relativeTo: .caption2))
                            .foregroundColor(theme.neutral700)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent700)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(theme.surface)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add my sessions to Calendar")
                        .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                        .foregroundColor(theme.text)
                    Text("Sync sessions you organize to your iOS Calendar")
                        .font(GSFont.body(11, relativeTo: .caption2))
                        .foregroundColor(theme.neutral700)
                }
                Spacer(minLength: 8)
                GSToggle(
                    isOn: Binding(
                        get: { calendarSyncEnabled },
                        set: { setCalendarSyncEnabled($0) }
                    ),
                    label: "Add my sessions to Calendar"
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.surface)
        }
    }

    /// Optimistic-flip shape matches `setShowSoloWorkouts` above, but the
    /// actual work (permission request, backfill, or teardown) is genuinely
    /// async and best-effort rather than a single repository call — see
    /// `enableCalendarSync()`/`disableCalendarSync()` below.
    private func setCalendarSyncEnabled(_ enabled: Bool) {
        calendarSyncEnabled = enabled
        Task {
            if enabled {
                await enableCalendarSync()
            } else {
                await disableCalendarSync()
            }
        }
    }

    /// Requests full Calendar access; if granted, persists the toggle ON and
    /// backfills every upcoming session the current user organizes (spec:
    /// "on enable: request permission + backfill upcoming organized
    /// sessions"). If denied, reverts the toggle and lets `calendarAuthStatus`
    /// drive the denied-row state on the next render.
    @MainActor
    private func enableCalendarSync() async {
        do {
            let granted = try await EventKitBridge.requestAccess()
            calendarAuthStatus = EventKitBridge.authorizationStatus()
            guard granted else {
                calendarSyncEnabled = false
                return
            }
            CalendarSyncPrefsStore.setEnabled(true)
            calendarSyncEnabled = true
            await backfillCalendarSync()
        } catch {
            AppLogger.calendar.error("enableCalendarSync: requestAccess failed: \(error.localizedDescription, privacy: .public)")
            calendarSyncEnabled = false
        }
    }

    /// Syncs every upcoming session the current user ORGANIZES (v1's
    /// organizer-only scope — see `EventKitBridge`'s doc comment) to the
    /// calendar. `SessionRepository.upcoming()` returns sessions the user
    /// PARTICIPATES in across several pre-workout states, so this filters to
    /// organizer-only + has a `scheduledFor`. Routine names/exercise counts
    /// come from a single bulk `RoutineRepository.fetchAll(ownerID:)` +
    /// `exercisesForRoutines(ids:)` pair — the same two-call shape
    /// `ScheduleSessionView.loadData()` already uses — rather than an N+1
    /// per-session `RoutineRepository.fetch(id:)` fan-out. A session whose
    /// routine isn't in the organizer's OWN routines (e.g. a cloned/Discover
    /// routine edge case) just falls back to `EventKitBridge`'s routine-less
    /// title — best-effort, not a hard failure.
    @MainActor
    private func backfillCalendarSync() async {
        guard let selfID = appState.currentProfile?.id else { return }
        let upcoming = (try? await SessionRepository.upcoming()) ?? []
        let organized = upcoming.filter { $0.organizerID == selfID && $0.scheduledFor != nil }
        guard !organized.isEmpty else { return }

        let routines = (try? await RoutineRepository.fetchAll(ownerID: selfID)) ?? []
        let routinesByID = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0) })
        let exercises = (try? await RoutineRepository.exercisesForRoutines(ids: routines.map(\.id))) ?? []
        let countsByRoutine = Dictionary(grouping: exercises, by: \.routineID).mapValues(\.count)

        for session in organized {
            let routineName = session.routineID.flatMap { routinesByID[$0]?.name }
            let exerciseCount = session.routineID.flatMap { countsByRoutine[$0] }
            await EventKitBridge.syncEvent(session: session, routineName: routineName, exerciseCount: exerciseCount)
        }
    }

    /// Persists the toggle OFF, then best-effort removes every mapped event
    /// this device has ever synced (spec: "on disable: best-effort remove
    /// mapped events"). `SessionCalendarSyncStore.allSessionIDs()` is the
    /// only record of what was ever synced — there's no server-side list to
    /// cross-check against for v1's local-only mapping.
    private func disableCalendarSync() async {
        CalendarSyncPrefsStore.setEnabled(false)
        for sessionID in SessionCalendarSyncStore.allSessionIDs() {
            await EventKitBridge.removeEvent(sessionID: sessionID)
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
        shareHeartRate = userSettings?.shareHeartRate ?? false

        healthAuthStatus = HealthKitBridge.store.authorizationStatus(for: .workoutType())
        await pushReceiver.refreshAuthorizationStatus()

        // Phase H Task 2: local-only, no network round-trip — see
        // `CalendarSyncPrefsStore`'s doc comment for why this reads
        // UserDefaults directly rather than a repository fetch.
        calendarSyncEnabled = CalendarSyncPrefsStore.isEnabled()
        calendarAuthStatus = EventKitBridge.authorizationStatus()
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
