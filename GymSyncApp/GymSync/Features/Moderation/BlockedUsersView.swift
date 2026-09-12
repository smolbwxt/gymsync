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
                    title: "Nobody blocked",
                    message: "Block someone and they land here — they won't be able to message you or send friend requests."
                )
                // Same 16pt inset the error card above carries, so the two
                // states sit on one gutter instead of the empty one going
                // full-bleed.
                .padding(.horizontal, 16)
                .padding(.top, 60)
            } else {
                List {
                    ForEach(blocked) { profile in
                        HStack(spacing: 10) {
                            GSInitialsAvatar(name: profile.username, avatarURL: profile.avatarURL, size: 36)
                            nameBlock(profile)
                            Spacer(minLength: 8)
                            // Fixed width so every row's pill is the same
                            // size with the same left edge, right-aligned to
                            // the 16pt trailing inset below. The frame goes
                            // on the BUTTON, not its label: this style wraps
                            // `configuration.label` in
                            // `HStack { label; Spacer(minLength: 0) }`, so a
                            // frame inside the label leaves the pill itself
                            // still stretchy — and it would measure 92 + 24pt
                            // of horizontal padding rather than 92. The
                            // label then takes `maxWidth: .infinity` to
                            // starve that internal Spacer, so "Unblock"
                            // centres in the pill instead of hugging its
                            // left edge.
                            Button {
                                Task { await unblock(profile) }
                            } label: {
                                Text("Unblock").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(GSSecondaryButtonStyle(fontSize: 12, horizontalPadding: 12, verticalPadding: 6))
                            .frame(width: 92)
                        }
                        // Clear, not `theme.surface`: the surface painted only
                        // behind rows, so it stopped mid-page against
                        // `theme.bg` and read as a hard seam. With clear rows
                        // the page is one ground and the separator tint below
                        // carries the structure.
                        .listRowBackground(Color.clear)
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
