import HealthKit
import SwiftUI

struct YouTabView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var profile: Profile?
    @State private var workoutsLogged: Int = 0
    @State private var homeGymName: String?
    @State private var showHomeGymSheet = false
    @State private var healthAuthStatus: HKAuthorizationStatus = .notDetermined
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        avatarCardView
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        statTileRow
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        GSSectionHeader("Settings")
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                            .padding(.bottom, 10)

                        settingsRows

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
            .sheet(isPresented: $showHomeGymSheet) {
                HomeGymSetupView(isOnboarding: false, onSaved: {
                    Task { await refreshHomeGymName() }
                })
            }
        }
    }

    // MARK: - Avatar Card

    @ViewBuilder
    private var avatarCardView: some View {
        let displayProfile = profile ?? appState.currentProfile
        GSCard(bordered: false) {
            VStack(spacing: 8) {
                Text(initials(for: displayProfile))
                    .font(GSFont.heading(20, relativeTo: .title3))
                    .foregroundColor(theme.bg)
                    .frame(width: 60, height: 60)
                    .background(theme.accent)

                Text(displayName(for: displayProfile))
                    .font(GSFont.heading(18, relativeTo: .title3))
                    .foregroundColor(theme.text)

                if let displayProfile {
                    Text(memberSinceText(for: displayProfile))
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundColor(theme.neutral700)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
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

    private func displayName(for profile: Profile?) -> String {
        guard let profile else { return "" }
        if let name = profile.displayName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return "@\(profile.username)"
    }

    private func memberSinceText(for profile: Profile) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return "@\(profile.username) · Member since \(formatter.string(from: profile.createdAt))"
    }

    // MARK: - Stat Tiles

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

    // MARK: - Settings Rows

    @ViewBuilder
    private var settingsRows: some View {
        VStack(spacing: 0) {
            GSSettingsRow(title: "Home Gym") {
                showHomeGymSheet = true
            }
            healthSyncRow
            themeRow
        }
        .padding(.horizontal, 16)
    }

    /// Shows current authorization state as trailing text (not a chevron —
    /// this row isn't a navigation target). Tapping re-requests permission
    /// then refreshes the displayed state.
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

    /// Restyled as a GSSettingsRow-shaped static row (recorded deviation —
    /// canvas's You tab has no Theme row at all; this app only ships the
    /// Midnight theme today, so the row is informational, not tappable).
    private var themeRow: some View {
        HStack {
            Text("Theme")
                .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                .foregroundColor(theme.text)
            Spacer()
            Text("Midnight")
                .font(GSFont.body(13, relativeTo: .caption))
                .foregroundColor(theme.neutral700)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
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

        if let fetched = try? await profileFetch {
            profile = fetched
            appState.currentProfile = fetched
        }
        if let history = try? await historyFetch {
            workoutsLogged = history.count
        }
        let gym = try? await gymFetch
        homeGymName = gym?.name

        healthAuthStatus = HealthKitBridge.store.authorizationStatus(for: .workoutType())
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
