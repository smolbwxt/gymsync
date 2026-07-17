import SwiftUI

struct FriendsView: View {
    /// When true, focuses the "Add a friend" username field as soon as this
    /// view appears. Wired from `SocialTabView`'s full-tab "No crew yet" CTA
    /// (Canvas Completion Task 4 fix round 1) so tapping "Add your first
    /// friend" there lands with the keyboard already up, not just a bare
    /// navigation. Defaults to false for every other entry point (the
    /// Social tab's "Friends" row, the push-route deep link), which are
    /// unchanged.
    var focusAddFieldOnAppear = false

    @State private var friends: [Profile] = []
    @State private var incoming: [Profile] = []
    @State private var outgoing: [Profile] = []
    @State private var addUsername = ""
    @State private var errorText: String?
    // Canvas Completion Task 4: `refresh()`'s existing `try?`-and-swallow
    // pattern never tracked failure at all, so — unlike SocialTabView's
    // reused `errorText` — this is a genuinely new flag. Only set from the
    // `friends` fetch specifically (the one GSEmptyState/GSErrorCard below
    // cares about); `incoming`/`outgoing` failures stay silent as before.
    @State private var friendsLoadFailed = false
    @FocusState private var isUsernameFieldFocused: Bool

    @Environment(\.gsTheme) private var theme

    var body: some View {
        // Keep List so swipeActions (Remove) on friends rows continues to work (contract).
        List {
            // Add Friend section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("@")
                                .font(GSFont.bodyMedium(14, relativeTo: .body))
                                .foregroundStyle(theme.neutral500)
                            TextField("username", text: $addUsername)
                                .font(GSFont.body(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .tint(theme.accent)
                                .focused($isUsernameFieldFocused)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(theme.surface)
                        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))

                        Button("Send") {
                            Task { await sendRequest() }
                        }
                        .buttonStyle(GSPrimaryButtonStyle())
                        .frame(width: 72)
                        .disabled(addUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                    }
                }
                .listRowBackground(theme.bg)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                GSSectionHeader("Add a friend")
            }

            // Incoming requests
            if !incoming.isEmpty {
                Section {
                    ForEach(incoming) { profile in
                        HStack(spacing: 10) {
                            GSInitialsAvatar(name: profile.username, avatarURL: profile.avatarURL, size: 36)
                            nameBlock(profile)
                            Spacer()
                            Button("Accept") {
                                Task {
                                    try? await FriendRepository.accept(requesterID: profile.id)
                                    await refresh()
                                }
                            }
                            .buttonStyle(GSPrimaryButtonStyle())
                            .frame(width: 72)

                            Button {
                                Task {
                                    try? await FriendRepository.removeFriendship(with: profile.id)
                                    await refresh()
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(theme.neutral500)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(theme.surface)
                        .listRowSeparatorTint(theme.divider)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                } header: {
                    GSSectionHeader("Requests · \(incoming.count)")
                }
            }

            // Outgoing pending requests
            if !outgoing.isEmpty {
                Section {
                    ForEach(outgoing) { profile in
                        HStack(spacing: 10) {
                            GSInitialsAvatar(name: profile.username, avatarURL: profile.avatarURL, size: 36)
                            nameBlock(profile)
                            Spacer()
                            Button("Cancel") {
                                Task {
                                    try? await FriendRepository.removeFriendship(with: profile.id)
                                    await refresh()
                                }
                            }
                            .buttonStyle(GSSecondaryButtonStyle())
                            .frame(width: 80)
                        }
                        .listRowBackground(theme.surface)
                        .listRowSeparatorTint(theme.divider)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                } header: {
                    GSSectionHeader("Sent")
                }
            }

            // Friends list — swipeActions to Remove preserved
            Section {
                // Canvas Completion Task 4 (proof p30-empty-offline, "No crew
                // yet"): the error card only shows when the list is blank
                // BECAUSE the load failed — a refresh failure that leaves
                // existing friends on screen stays silent, same as before.
                if friends.isEmpty {
                    if friendsLoadFailed {
                        GSErrorCard(
                            title: "Couldn't load your friends",
                            message: "Check your connection and try again.",
                            retry: { Task { await refresh() } }
                        )
                        .listRowBackground(theme.bg)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    } else {
                        GSEmptyState(
                            icon: "person.2",
                            title: "No crew yet",
                            message: "Add a friend by username — then take turns on the bar together.",
                            ctaTitle: "Add your first friend",
                            action: { isUsernameFieldFocused = true }
                        )
                        .listRowBackground(theme.bg)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }
                } else {
                    ForEach(friends) { profile in
                        HStack(spacing: 10) {
                            GSInitialsAvatar(name: profile.username, avatarURL: profile.avatarURL, size: 36)
                            nameBlock(profile)
                        }
                        .listRowBackground(theme.surface)
                        .listRowSeparatorTint(theme.divider)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                Task {
                                    try? await FriendRepository.removeFriendship(with: profile.id)
                                    await refresh()
                                }
                            }
                        }
                    }
                }
            } header: {
                GSSectionHeader("Friends · \(friends.count)")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle("Friends")
        .task { await refresh() }
        .refreshable { await refresh() }
        .onAppear {
            if focusAddFieldOnAppear {
                isUsernameFieldFocused = true
            }
        }
    }

    // Two-line "Display Name" / "@username" block, matching the proof's
    // name treatment across requests/sent/friends rows. Falls back to
    // username-only (single line) when displayName is nil — never renders
    // an empty first line.
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

    private func sendRequest() async {
        let username = addUsername.trimmingCharacters(in: .whitespaces)
        do {
            try await FriendRepository.sendRequest(toUsername: username)
            addUsername = ""
            errorText = nil
            await refresh()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func refresh() async {
        // Best-effort per Canvas Completion Task 4's contract: a failure here
        // leaves the previous `friends` value in place (does NOT reset to
        // `[]`) so a transient blip never wipes a populated list — only a
        // failure while `friends` is ALREADY empty produces the
        // blank-list-plus-error condition GSErrorCard is for.
        do {
            friends = try await FriendRepository.friends()
            friendsLoadFailed = false
        } catch {
            friendsLoadFailed = true
        }
        incoming = (try? await FriendRepository.incomingRequests()) ?? []
        outgoing = (try? await FriendRepository.outgoingRequests()) ?? []
    }
}
