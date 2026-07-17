import SwiftUI

/// You-tab destination: the current user's blocked-users list, with a
/// per-row Unblock action. Reached via a `GSSettingsRow` in `YouTabView`'s
/// settings group box — same `.navigationDestination(isPresented:)` idiom as
/// NotificationPreferencesView/AppearanceView/RestTimerSettingView.
///
/// No canvas frame exists for this screen (system-designed, App Store
/// compliance gate — see `docs/design/accepted-deviations.json`'s
/// "blocked-users" entry). Row shape mirrors `FriendsView`'s friends-list
/// rows (GSInitialsAvatar + two-line name block); empty/error states reuse
/// `GSEmptyState`/`GSErrorCard` per this codebase's list-screen idiom.
struct BlockedUsersView: View {
    @Environment(\.gsTheme) private var theme
    @State private var blocked: [Profile] = []
    @State private var loading = false
    @State private var errorText: String?

    #if DEBUG
    /// Catalog-only seam — same idiom as ChatView/HomeGymSetupView's
    /// `catalogSkipLoad`: skips the live `.task` fetch so the
    /// `blocked-users` catalog capture is hermetic (CatalogHostView bypasses
    /// auth entirely, so a live fetch would just fail).
    private var catalogSkipLoad = false
    #endif

    var body: some View {
        Group {
            if loading {
                HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                    .padding(.top, 40)
            } else if let errorText, blocked.isEmpty {
                GSErrorCard(
                    title: "Couldn't load blocked users",
                    message: errorText,
                    retry: { Task { await load() } }
                )
                .padding(16)
            } else if blocked.isEmpty {
                GSEmptyState(
                    icon: "person.crop.circle.badge.xmark",
                    title: "No blocked users",
                    message: "Users you block won't be able to message you or send friend requests."
                )
                .padding(.top, 60)
            } else {
                List {
                    ForEach(blocked) { profile in
                        HStack(spacing: 10) {
                            GSInitialsAvatar(name: profile.username, avatarURL: profile.avatarURL, size: 36)
                            nameBlock(profile)
                            Spacer()
                            Button("Unblock") {
                                Task { await unblock(profile) }
                            }
                            .buttonStyle(GSSecondaryButtonStyle(fontSize: 12, horizontalPadding: 12, verticalPadding: 6))
                        }
                        .listRowBackground(theme.surface)
                        .listRowSeparatorTint(theme.divider)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(theme.bg)
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // Two-line "Display Name" / "@username" block — same idiom as
    // FriendsView/GroupView/CreateGroupView's identically-named helper.
    @ViewBuilder
    private func nameBlock(_ profile: Profile) -> some View {
        if let displayName = profile.displayName, !displayName.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(GSFont.bodyMedium(14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Text("@\(profile.username)")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
        } else {
            Text(profile.username)
                .font(GSFont.bodyMedium(14, relativeTo: .body))
                .foregroundStyle(theme.text)
        }
    }

    private func load() async {
        #if DEBUG
        if catalogSkipLoad { return }
        #endif
        loading = true
        defer { loading = false }
        do {
            blocked = try await ModerationRepository.blockedUsers()
            errorText = nil
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
        }
    }

    private func unblock(_ profile: Profile) async {
        do {
            try await ModerationRepository.unblock(userID: profile.id)
            blocked.removeAll { $0.id == profile.id }
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
        }
    }
}

// MARK: - Catalog fixture seam (`blocked-users` catalog case)

#if DEBUG
extension BlockedUsersView {
    /// Debug-only seam for the design-parity screen catalog — same
    /// same-file-for-`private`-@State-access pattern as ChatView's
    /// `catalogFixtureMessages` init at the bottom of that file: seeds
    /// `blocked` directly and sets `catalogSkipLoad` so `load()` never fires
    /// its live fetch.
    init(catalogFixtureBlocked blocked: [Profile]) {
        _blocked = State(initialValue: blocked)
        catalogSkipLoad = true
    }
}
#endif
