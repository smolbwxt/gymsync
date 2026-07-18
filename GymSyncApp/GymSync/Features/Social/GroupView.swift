import SwiftUI
import PhotosUI

struct GroupView: View {
    let group: GymGroup

    // Group streak placement (Phase S Task 5 deferred this to Phase F):
    // `group_streaks` is live and readable (member-gated RLS,
    // 20260719000006_streaks.sql) — it now lives in the `.stats` sub-tab's
    // `GroupStatsView`, alongside the collective-metrics/leaderboard
    // aggregate this same task (Phase F Task 5) adds. See that file's
    // header comment for the full frame-check + design-idiom rationale.
    private enum SubTab: String, CaseIterable {
        case chat     = "Chat"
        case members  = "Members"
        case sessions = "Sessions"
        case stats    = "Stats"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState
    @State private var subTab: SubTab = .chat
    @State private var members: [(member: GroupMember, profile: Profile)] = []
    @State private var addUsername = ""
    @State private var errorText: String?
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarURL: URL?

    // Phase M Task 2 (moderation/compliance): Report/Block on Members rows.
    @State private var reportTarget: Profile?
    @State private var blockTarget: Profile?
    @State private var showBlockConfirm = false

    // Sessions sub-tab
    @State private var upcomingSessions: [WorkoutSession] = []
    @State private var pastSessions: [WorkoutSession] = []

    var body: some View {
        VStack(spacing: 0) {
            // Themed segmented control per canvas
            themedSegmentedControl

            GSDivider()

            switch subTab {
            case .chat:
                ChatView(group: group)
            case .members:
                membersList
            case .sessions:
                sessionsList
            case .stats:
                GroupStatsView(group: group)
            }
        }
        .background(theme.bg)
        // Pushed from SocialTabView. Its Chat sub-tab embeds ChatView's
        // bottom-pinned inputBar and its Members sub-tab has a bottom-pinned
        // "Leave Group" footer — applied here (the actual push destination)
        // so the dock stays hidden across all three sub-tabs, not just Chat.
        // See GSComponents.swift's GSHidesDock.
        .gsHidesDock()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    GSInitialsAvatar(name: group.name, avatarURL: group.avatarURL, size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group.name)
                            .font(GSFont.bold(15, relativeTo: .headline))
                            .foregroundStyle(theme.text)
                        Text("\(members.count) member\(members.count == 1 ? "" : "s")")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                }
            }
        }
        .task {
            members = (try? await GroupRepository.members(groupID: group.id)) ?? []
            await loadGroupSessions()
        }
        .onChange(of: subTab) {
            if subTab == .sessions {
                Task { await loadGroupSessions() }
            }
        }
        .sheet(item: $reportTarget) { profile in
            ReportSheet(reportedUserID: profile.id, contentType: .profile, contentID: profile.id)
        }
        // Literal text per brief: "Block @username? You won't see their
        // messages or requests." — same title/message split as FriendsView.
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
    }

    // MARK: - Themed Segmented Control

    private var themedSegmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(SubTab.allCases, id: \.self) { tab in
                Button {
                    subTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(GSFont.bold(11, relativeTo: .caption))
                        .foregroundStyle(subTab == tab ? theme.bg : theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(subTab == tab ? theme.accent : Color.clear)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.bg)
    }

    // MARK: - Members List

    private var membersList: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Avatar picker row — Phase F Task 6: GSInitialsAvatar now
                // renders the photo itself when avatarURL is non-nil (see
                // its doc comment); this used to hand-roll the same
                // AsyncImage block inline.
                HStack(spacing: 12) {
                    GSInitialsAvatar(name: group.name, avatarURL: avatarURL ?? group.avatarURL, size: 56)

                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        Text("Change Group Photo")
                            .font(GSFont.bodyMedium(14, relativeTo: .body))
                            .foregroundStyle(theme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                GSDivider()
                    .padding(.horizontal, 16)

                // Add member field
                VStack(alignment: .leading, spacing: 8) {
                    GSSectionHeader("Add member")
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    HStack(spacing: 8) {
                        HStack {
                            Text("@")
                                .font(GSFont.bodyMedium(14, relativeTo: .body))
                                .foregroundStyle(theme.neutral500)
                            TextField("username", text: $addUsername)
                                .font(GSFont.body(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .tint(theme.accent)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(theme.surface)
                        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))

                        Button("Add") { Task { await addMember() } }
                            .buttonStyle(GSPrimaryButtonStyle())
                            .frame(width: 64)
                            .disabled(addUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 16)

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }
                }

                GSDivider()
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                GSSectionHeader("\(members.count) members")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(members, id: \.member.userID) { entry in
                        memberRow(entry)

                        if entry.member.userID != members.last?.member.userID {
                            Rectangle()
                                .fill(theme.divider)
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }
                }

                Spacer(minLength: 16)
            }
        }
        .background(theme.bg)
        .onChange(of: avatarItem) {
            guard let item = avatarItem else { return }
            avatarItem = nil
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        errorText = "That image couldn't be loaded."
                        return
                    }
                    avatarURL = try await GroupRepository.setAvatar(
                        groupID: group.id, imageData: data)
                    errorText = nil
                } catch let error as GymSyncError {
                    errorText = error.errorDescription
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }

        // Sticky footer — bordered box, accent text, pinned below a divider
        GSDivider()
        Button("Leave Group", role: .destructive) {
            Task {
                try? await GroupRepository.leave(groupID: group.id)
                dismiss()
            }
        }
        .font(GSFont.bodyMedium(14, relativeTo: .body))
        .foregroundStyle(theme.accent)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.bg)
        }
    }

    // Phase M Task 2: member row + Report/Block long-press menu (mirrors
    // ChatView's reaction .contextMenu — this codebase's established
    // per-row menu idiom; GroupView's members list is a plain VStack, not a
    // List, so there's no swipeActions equivalent to reach for here). Omits
    // the menu entirely for the current user's own row (self-report/block
    // is meaningless) — an EMPTY `.contextMenu` is deliberately avoided
    // (ambiguous iOS behavior on long-press) by branching the whole
    // modifier chain instead of gating just its content.
    @ViewBuilder
    private func memberRow(_ entry: (member: GroupMember, profile: Profile)) -> some View {
        let row = HStack(spacing: 10) {
            GSInitialsAvatar(name: entry.profile.username,
                              avatarURL: entry.profile.avatarURL, size: 36)

            nameBlock(entry.profile)

            Spacer()

            if entry.member.role == .admin {
                GSTag(text: "Admin", style: .neutral)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())

        if entry.profile.id == appState.currentProfile?.id {
            row
        } else {
            row.contextMenu {
                Button {
                    reportTarget = entry.profile
                } label: {
                    Label("Report", systemImage: "flag")
                }
                Button(role: .destructive) {
                    blockTarget = entry.profile
                    showBlockConfirm = true
                } label: {
                    Label("Block", systemImage: "nosign")
                }
            }
        }
    }

    // Two-line "Display Name" / "@username" block — matches the proof's
    // name treatment (fallback: username-only, single line, when no
    // displayName is set).
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

    // MARK: - Sessions List

    private static let upcomingStates: Set<String> = [
        "scheduled", "lobby_open", "editing", "voting", "locked", "in_progress"
    ]
    private static let pastStates: Set<String> = ["completed", "abandoned"]

    private var sessionsList: some View {
        List {
            // Burpee Ledger entry point (Canvas Completion Task 3, proof p25) —
            // group-scoped crew debt aggregate, always available regardless of
            // whether this group currently has upcoming/past sessions.
            Section {
                NavigationLink {
                    BurpeeLedgerView(group: group)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.strengthtraining.functional")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(theme.accent)
                        Text("Burpee Ledger")
                            .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                            .foregroundStyle(theme.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.neutral500)
                    }
                    .frame(minHeight: 44)
                }
                .listRowBackground(theme.surface)
                .listRowSeparatorTint(theme.divider)
            }

            if upcomingSessions.isEmpty && pastSessions.isEmpty {
                Section {
                    Text("No upcoming sessions — schedule one from Home.")
                        .foregroundStyle(theme.neutral500)
                        .font(GSFont.body(14, relativeTo: .subheadline))
                        .listRowBackground(theme.bg)
                }
            } else {
                if !upcomingSessions.isEmpty {
                    Section {
                        ForEach(upcomingSessions) { session in
                            NavigationLink {
                                LobbyView(session: session)
                            } label: {
                                sessionRow(session)
                            }
                            .listRowBackground(theme.surface)
                            .listRowSeparatorTint(theme.divider)
                        }
                    } header: {
                        GSSectionHeader("Upcoming")
                    }
                }
                if !pastSessions.isEmpty {
                    Section {
                        ForEach(pastSessions) { session in
                            NavigationLink {
                                CompletedSessionView(session: session)
                            } label: {
                                sessionRow(session)
                            }
                            .listRowBackground(theme.surface)
                            .listRowSeparatorTint(theme.divider)
                        }
                    } header: {
                        GSSectionHeader("Past")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .refreshable { await loadGroupSessions() }
    }

    @ViewBuilder
    private func sessionRow(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if session.state == "completed" {
                    Text("\u{2705}")
                } else if session.state == "abandoned" {
                    Text("\u{1F32B}\u{FE0F}")
                }
                Text("Workout")
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                if session.seriesID != nil {
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundStyle(theme.neutral500)
                }
            }
            if let scheduledFor = session.scheduledFor {
                (Text(scheduledFor, style: .date)
                    + Text(" at ") + Text(scheduledFor, style: .time))
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
            }
            Text(session.state.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
        }
    }

    // MARK: - Actions

    private func addMember() async {
        do {
            try await GroupRepository.addMember(
                groupID: group.id,
                username: addUsername.trimmingCharacters(in: .whitespaces))
            addUsername = ""
            errorText = nil
            members = (try? await GroupRepository.members(groupID: group.id)) ?? []
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // Phase M Task 2: block a group member. No local `members` mutation —
    // blocking doesn't remove group membership (out of this task's scope,
    // matches Task 1's backend contract, which only enforces block at chat
    // SELECT + friend-request INSERT); the member row stays visible, only
    // their chat content becomes hidden (RLS on refetch/realtime, plus
    // ChatView's own client-side message filter for content already in
    // memory).
    private func block(_ profile: Profile?) async {
        guard let profile else { return }
        do {
            try await ModerationRepository.block(userID: profile.id)
            errorText = nil
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadGroupSessions() async {
        do {
            let all = try await SessionRepository.groupSessions(groupID: group.id)
            let upcoming = all
                .filter { GroupView.upcomingStates.contains($0.state) }
                .sorted { ($0.scheduledFor ?? .distantFuture) < ($1.scheduledFor ?? .distantFuture) }
            let past = all
                .filter { GroupView.pastStates.contains($0.state) }
                .sorted { ($0.scheduledFor ?? .distantPast) > ($1.scheduledFor ?? .distantPast) }
                .prefix(10)
            upcomingSessions = upcoming
            pastSessions = Array(past)
        } catch {
            // Best-effort; existing data preserved on error
        }
    }
}
