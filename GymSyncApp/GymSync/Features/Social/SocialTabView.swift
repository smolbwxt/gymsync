import SwiftUI

struct SocialTabView: View {
    @State private var groups: [GymGroup] = []
    @State private var unread: Set<UUID> = []
    @State private var previews: [UUID: String] = [:]
    @State private var friendCount = 0
    @State private var pendingCount = 0
    @State private var showCreateGroup = false
    // Also doubles as the "did the last groups load fail" flag (Canvas
    // Completion Task 4) — it's already a String? set from `refresh()`'s
    // catch block, so a second dedicated Bool would just duplicate it.
    @State private var errorText: String?
    @State private var friendRealtime = FriendRealtimeService()
    // Canvas Completion Task 4 — drives the "Reconnecting…" pill below.
    @State private var connectivity = ConnectivityMonitor.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    // Push deep-link routing (Phase 3d Task 5) — programmatic navigation
    // targets consumed from `appState.pendingRoute`.
    @State private var pendingChatGroup: GymGroup?
    @State private var navigateToFriends = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Offline pill (Canvas Completion Task 4 — proof
                    // p30-empty-offline). Anchored at the top of this
                    // screen's content, matching the canvas frame — see
                    // ConnectivityMonitor.swift's doc comment for why this
                    // isn't a RootView-wide overlay.
                    if !connectivity.isOnline {
                        GSOfflineBanner()
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }

                    // Friends row
                    NavigationLink {
                        FriendsView()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(theme.text)
                            Text("Friends")
                                .font(GSFont.bold(14, relativeTo: .headline))
                                .foregroundStyle(theme.text)
                            Spacer()
                            if pendingCount > 0 {
                                GSTag(text: "\(pendingCount) new", style: .accent)
                            }
                            Text("\(friendCount)")
                                .font(GSFont.body(13, relativeTo: .subheadline))
                                .foregroundStyle(theme.neutral500)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.neutral500)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(theme.surface)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    GSDivider()
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    // Groups header
                    GSSectionHeader("Groups")
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    // Canvas Completion Task 4 (proof p30/p31): the blank-list
                    // error card only replaces the plain empty state when the
                    // list is ACTUALLY blank because the load failed — a
                    // refresh failure with existing groups on screen leaves
                    // them in place (best-effort, unchanged) and only surfaces
                    // the small red caption below.
                    if groups.isEmpty {
                        if errorText != nil {
                            GSErrorCard(
                                title: "Couldn't load your groups",
                                message: errorText ?? "Check your connection and try again.",
                                retry: { Task { await refresh() } }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        } else {
                            GSEmptyState(
                                icon: "person.3",
                                title: "No groups yet",
                                message: "Start a group with your crew — then take turns on the bar together.",
                                ctaTitle: "+ New Group",
                                action: { showCreateGroup = true }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }
                    }

                    VStack(spacing: 8) {
                        ForEach(groups) { group in
                            NavigationLink {
                                GroupView(group: group)
                            } label: {
                                groupRow(group)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        }
                    }

                    // New Group button — hidden in the true empty case since
                    // GSEmptyState above already surfaces an equivalent "+ New
                    // Group" CTA (avoids showing the same action twice). Still
                    // shown during the blank-list-plus-error case (GSErrorCard
                    // has no group-creation CTA of its own) and whenever the
                    // list has content.
                    if !groups.isEmpty || errorText != nil {
                        Button {
                            showCreateGroup = true
                        } label: {
                            Text("+ New Group")
                        }
                        .buttonStyle(GSSecondaryButtonStyle())
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }

                    // Non-blank-list case only — the blank-list case already
                    // surfaced this same message via GSErrorCard above, so
                    // showing it again here would be redundant.
                    if let errorText, !groups.isEmpty {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("Social")
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView { newGroup in
                    groups.insert(newGroup, at: 0)
                }
            }
            .task {
                await refresh()
                if let me = await SupabaseService.shared.currentUserID() {
                    await friendRealtime.subscribe(userID: me) {
                        Task { await refresh() }
                    }
                }
                await consumePendingRouteIfNeeded()
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task {
                    await refresh()
                    if let me = await SupabaseService.shared.currentUserID() {
                        await friendRealtime.subscribe(userID: me) {
                            Task { await refresh() }
                        }
                    }
                }
            }
            .onChange(of: appState.pendingRoute) {
                Task { await consumePendingRouteIfNeeded() }
            }
            .onDisappear { Task { await friendRealtime.unsubscribe() } }
            .refreshable { await refresh() }
            .navigationDestination(item: $pendingChatGroup) { group in
                GroupView(group: group)
            }
            .navigationDestination(isPresented: $navigateToFriends) {
                FriendsView()
            }
        }
    }

    // MARK: - Push deep-link routing (Phase 3d Task 5)

    /// Consumes `.chat`/`.friends`. Clears `pendingRoute` immediately so a
    /// later `.onChange` firing (or this `.task` re-running) doesn't
    /// re-navigate. `.chat`'s group fetch can legitimately come back empty
    /// (e.g. the user left the group between the push firing and the tap) —
    /// silently no-ops rather than surfacing an error for that edge case.
    private func consumePendingRouteIfNeeded() async {
        switch appState.pendingRoute {
        case .friends:
            appState.pendingRoute = nil
            navigateToFriends = true
        case .chat(let groupID):
            appState.pendingRoute = nil
            let groups = (try? await GroupRepository.fetchMany(ids: [groupID])) ?? []
            pendingChatGroup = groups.first
        default:
            break
        }
    }

    @ViewBuilder
    private func groupRow(_ group: GymGroup) -> some View {
        HStack(spacing: 10) {
            // 36×36 square avatar
            if let url = group.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    GSInitialsAvatar(name: group.name, size: 36)
                }
                .frame(width: 36, height: 36)
                .clipped()
            } else {
                GSInitialsAvatar(name: group.name, size: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                // Canvas: last-message preview line (Dossier §B — audit §2.6)
                if let preview = previews[group.id] {
                    Text(preview)
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral700)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)

            // Unread dot — square, 9×9, accent fill per canvas
            if unread.contains(group.id) {
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 9, height: 9)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.surface)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refresh() async {
        do {
            groups = try await GroupRepository.myGroups()
            friendCount = try await FriendRepository.friends().count
            pendingCount = try await FriendRepository.incomingRequests().count
            let currentGroups = groups

            // Single latest-message fetch per group feeds both the unread badge
            // and the preview line (was 2 fetches/group across two task groups).
            var unreadIDs: Set<UUID> = []
            var previewsByGroup: [UUID: String] = [:]
            await withTaskGroup(of: (UUID, Bool, String?).self) { taskGroup in
                for group in currentGroups {
                    taskGroup.addTask {
                        let latest = try? await ChatRepository.messages(groupID: group.id, limit: 1)
                        let message = latest?.first
                        let isUnread = (try? await ChatRepository.hasUnread(latest: message, groupID: group.id)) == true
                        let preview = message.flatMap(Self.previewText(for:))
                        return (group.id, isUnread, preview)
                    }
                }
                for await (id, isUnread, text) in taskGroup {
                    if isUnread {
                        unreadIDs.insert(id)
                    }
                    if let text {
                        previewsByGroup[id] = text
                    }
                }
            }
            unread = unreadIDs
            previews = previewsByGroup

            errorText = nil
        } catch {
            errorText = (error as? GymSyncError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Maps a chat message to its group-row preview line.
    /// text/soundboard_echo/system kinds show the body as-is; image and audio
    /// kinds show a fixed placeholder (no body to display).
    private static func previewText(for message: ChatMessage) -> String? {
        switch message.kind {
        case .image: return "📷 Photo"
        case .audio: return "🎤 Voice message"
        case .text, .soundboardEcho, .systemPR, .systemSession, .systemLate, .systemLeaderboard:
            return message.body
        }
    }
}

// MARK: - GSInitialsAvatar

/// Square, zero-radius initials avatar replacing the circle variant.
/// Used in group rows (36 px) and group header (30 px inside GroupView).
struct GSInitialsAvatar: View {
    let name: String
    var size: CGFloat = 34

    @Environment(\.gsTheme) private var theme

    var body: some View {
        Text(initials)
            .font(GSFont.bold(size * 0.31, relativeTo: .caption))
            .foregroundStyle(theme.bg)
            .frame(width: size, height: size)
            .background(theme.accent)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}

// Keep the old InitialsAvatar for any remaining callers in other files
struct InitialsAvatar: View {
    let name: String

    @Environment(\.gsTheme) private var theme

    var body: some View {
        Text(initials)
            .font(.caption.bold())
            .foregroundStyle(theme.bg)
            .frame(width: 34, height: 34)
            .background(theme.accent)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}

