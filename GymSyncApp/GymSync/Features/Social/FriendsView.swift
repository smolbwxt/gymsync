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

    // Phase M Task 2 (moderation/compliance): Report/Block on friends rows.
    // Whole-branch review Finding 2: also wired onto incoming and outgoing
    // request rows below — same two @State vars serve all three sections,
    // since a report/block always targets the Profile behind the row, not
    // the request/friendship relationship itself.
    @State private var reportTarget: Profile?
    @State private var blockTarget: Profile?
    @State private var showBlockConfirm = false
    // Minor fix round: block() previously reused `errorText` — the field
    // meant for the "Add a friend" username submission at the top of the
    // list — so a failed block silently rendered its error next to an
    // unrelated input instead of near the row the user acted on. Own state
    // + `.alert` (below) keeps a block failure visibly tied to the block
    // action itself.
    @State private var moderationError: String?

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
                        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))

                        Button("Send") {
                            Task { await sendRequest() }
                        }
                        // verticalPadding 8 (3D pass 2026-08): the style's
                        // 37pt face floor + 7pt lip = exactly the field's
                        // 44pt beside it — default padding would push the
                        // extruded button ~6pt taller than the field.
                        .buttonStyle(GSPrimaryButtonStyle(verticalPadding: 8))
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
                            // fixedSize, not a fixed width (user screenshot
                            // 2026-07-31: "Accept" wrapped to "Acce/pt" in
                            // the old 72pt box).
                            .fixedSize()

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
                        // Whole-branch review Finding 2: incoming (and
                        // outgoing, below) request rows lacked Report/Block
                        // entirely — same .contextMenu idiom as the
                        // Friends-section rows below, reusing the same
                        // reportTarget/blockTarget/showBlockConfirm state
                        // (a request row and a friend row report/block the
                        // same way: the profile behind the row, not the
                        // request itself).
                        .contextMenu {
                            Button {
                                reportTarget = profile
                            } label: {
                                Label("Report", systemImage: "flag")
                            }
                            Button(role: .destructive) {
                                blockTarget = profile
                                showBlockConfirm = true
                            } label: {
                                Label("Block", systemImage: "nosign")
                            }
                        }
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
                            // Redesign fix (2026-07-23 screenshot: "Canc/el"
                            // wrap): natural width at a compact scale instead
                            // of squeezing the 16pt default into 80pt.
                            .buttonStyle(GSSecondaryButtonStyle(fontSize: 13, horizontalPadding: 14, verticalPadding: 9))
                            .fixedSize()
                        }
                        .listRowBackground(theme.surface)
                        .listRowSeparatorTint(theme.divider)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        // Finding 2 (same as the incoming section above):
                        // same trivial contextMenu pattern applies here too
                        // — a user may want to report/block someone even
                        // after sending them a request but before it's
                        // answered.
                        .contextMenu {
                            Button {
                                reportTarget = profile
                            } label: {
                                Label("Report", systemImage: "flag")
                            }
                            Button(role: .destructive) {
                                blockTarget = profile
                                showBlockConfirm = true
                            } label: {
                                Label("Block", systemImage: "nosign")
                            }
                        }
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
                        // Phase M Task 2: long-press menu — mirrors ChatView's
                        // reaction .contextMenu, this codebase's established
                        // per-row menu idiom (no swipeActions equivalent for a
                        // non-destructive "Report" action).
                        .contextMenu {
                            Button {
                                reportTarget = profile
                            } label: {
                                Label("Report", systemImage: "flag")
                            }
                            Button(role: .destructive) {
                                blockTarget = profile
                                showBlockConfirm = true
                            } label: {
                                Label("Block", systemImage: "nosign")
                            }
                        }
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
        // insetGrouped, not plain (Onyx alignment 2026-07-31): plain
        // rendered every section as a full-bleed zero-radius band —
        // insetGrouped gives the rounded floating-card read while keeping
        // the List (and its swipeActions contract) intact.
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        // Dock clearance (UI audit 2026-07-29): pushed inside a tab with
        // neither .gsHidesDock() nor a bottom inset, so the 86pt dock drew
        // over the last friend row — which also carries a swipe action.
        .contentMargins(.bottom, 88, for: .scrollContent)
        .navigationTitle("Friends")
        .task { await refresh() }
        .refreshable { await refresh() }
        .onAppear {
            if focusAddFieldOnAppear {
                isUsernameFieldFocused = true
            }
        }
        .sheet(item: $reportTarget) { profile in
            ReportSheet(reportedUserID: profile.id, contentType: .profile, contentID: profile.id)
        }
        // Literal text per brief: "Block @username? You won't see their
        // messages or requests." — split title/message per this codebase's
        // confirmationDialog idiom (LobbyView's dialogs: short question
        // title, explanatory message).
        .confirmationDialog(
            "Block @\(blockTarget?.username ?? "")?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task { await block(blockTarget) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see their messages or requests.")
        }
        // Minor fix round: block failures get their own alert instead of
        // reusing the add-friend `errorText` near the top input — same
        // title/message shape as the confirmationDialog above, adapted to
        // `.alert`'s `presenting:` form since `moderationError` carries the
        // message itself (no separate stored title).
        .alert(
            "Couldn't complete that action",
            isPresented: Binding<Bool>(
                get: { moderationError != nil },
                set: { if !$0 { moderationError = nil } }
            ),
            presenting: moderationError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
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

    // Phase M Task 2: block a user — inserts `blocked_users`, then drops the
    // row client-side (spec: "friends: drop the row" — the row is already
    // fetched, so future RLS-driven refetches alone wouldn't hide it until
    // the next `refresh()`).
    //
    // Whole-branch review Finding 2 extension: `blockTarget` can now come
    // from ANY of the three sections (friends, incoming, outgoing —
    // contextMenu is wired on all three above), so this removes the
    // profile from all three local arrays rather than just `friends`. A
    // given profile only ever actually appears in one of them at a time,
    // so the other two `removeAll` calls are no-ops for that profile — this
    // is simpler and safer than threading "which section did this menu
    // open from" through `blockTarget` just to call one specific array's
    // removeAll. Server-side, the new blocked_users_sever_friendship
    // trigger (20260722000003_block_severs_friendship.sql) already deletes
    // the underlying friendships row (pending or accepted) the instant the
    // block INSERT lands — this local removal just keeps the visible list
    // in sync immediately, same rationale as the pre-existing `friends`
    // case, without waiting for a `refresh()`.
    private func block(_ profile: Profile?) async {
        guard let profile else { return }
        do {
            try await ModerationRepository.block(userID: profile.id)
            friends.removeAll { $0.id == profile.id }
            incoming.removeAll { $0.id == profile.id }
            outgoing.removeAll { $0.id == profile.id }
            moderationError = nil
        } catch let error as GymSyncError {
            moderationError = error.errorDescription
        } catch {
            moderationError = error.localizedDescription
        }
    }
}
