import SwiftUI

struct SocialTabView: View {
    @State private var groups: [GymGroup] = []
    @State private var unread: Set<UUID> = []
    @State private var friendCount = 0
    @State private var pendingCount = 0
    @State private var showCreateGroup = false
    @State private var errorText: String?
    @State private var friendRealtime = FriendRealtimeService()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gsTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                    Text("Groups")
                        .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                        .tracking(0.5)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    if groups.isEmpty {
                        Text("No groups yet. Create one to start chatting.")
                            .font(GSFont.body(14, relativeTo: .body))
                            .foregroundStyle(theme.neutral500)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
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

                    // New Group button
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

                    if let errorText {
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
            .onDisappear { Task { await friendRealtime.unsubscribe() } }
            .refreshable { await refresh() }
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
            var unreadIDs: Set<UUID> = []
            await withTaskGroup(of: (UUID, Bool).self) { taskGroup in
                for group in currentGroups {
                    taskGroup.addTask {
                        (group.id, (try? await ChatRepository.hasUnread(groupID: group.id)) == true)
                    }
                }
                for await (id, hasUnread) in taskGroup where hasUnread {
                    unreadIDs.insert(id)
                }
            }
            unread = unreadIDs
            errorText = nil
        } catch {
            errorText = (error as? GymSyncError)?.errorDescription
                ?? error.localizedDescription
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

