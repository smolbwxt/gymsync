import SwiftUI

struct SocialTabView: View {
    @State private var groups: [GymGroup] = []
    @State private var unread: Set<UUID> = []
    @State private var friendCount = 0
    @State private var pendingCount = 0
    @State private var showCreateGroup = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FriendsView()
                    } label: {
                        HStack {
                            Label("Friends", systemImage: "person.2.fill")
                            Spacer()
                            if pendingCount > 0 {
                                Text("\(pendingCount)")
                                    .font(.caption.bold())
                                    .padding(6)
                                    .background(.red, in: Circle())
                                    .foregroundStyle(.white)
                            }
                            Text("\(friendCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Groups") {
                    if groups.isEmpty {
                        Text("No groups yet. Create one to start chatting.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(groups) { group in
                        NavigationLink {
                            GroupView(group: group)
                        } label: {
                            HStack {
                                InitialsAvatar(name: group.name)
                                Text(group.name)
                                Spacer()
                                if unread.contains(group.id) {
                                    Circle().fill(.blue).frame(width: 10, height: 10)
                                }
                            }
                        }
                    }
                }

                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Social")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateGroup = true
                    } label: {
                        Label("New Group", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView { newGroup in
                    groups.insert(newGroup, at: 0)
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
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

struct InitialsAvatar: View {
    let name: String

    var body: some View {
        Text(initials)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Color.accentColor.gradient, in: Circle())
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}
