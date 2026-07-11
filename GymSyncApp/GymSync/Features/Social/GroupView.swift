import SwiftUI
import PhotosUI

struct GroupView: View {
    let group: GymGroup

    private enum SubTab: String, CaseIterable {
        case chat     = "Chat"
        case members  = "Members"
        case sessions = "Sessions"
    }

    @Environment(\.dismiss) private var dismiss
    @State private var subTab: SubTab = .chat
    @State private var members: [(member: GroupMember, profile: Profile)] = []
    @State private var addUsername = ""
    @State private var errorText: String?
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarURL: URL?

    // Sessions sub-tab
    @State private var upcomingSessions: [WorkoutSession] = []
    @State private var pastSessions: [WorkoutSession] = []

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $subTab) {
                ForEach(SubTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            switch subTab {
            case .chat:
                ChatView(group: group)
            case .members:
                membersList
            case .sessions:
                sessionsList
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            members = (try? await GroupRepository.members(groupID: group.id)) ?? []
            await loadGroupSessions()
        }
        .onChange(of: subTab) {
            if subTab == .sessions {
                Task { await loadGroupSessions() }
            }
        }
    }

    // MARK: - Members List

    private var membersList: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    if let url = avatarURL ?? group.avatarURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            InitialsAvatar(name: group.name)
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    } else {
                        InitialsAvatar(name: group.name)
                    }
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        Text("Change Group Photo")
                    }
                }
            }
            Section {
                HStack {
                    TextField("add by username", text: $addUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add") { Task { await addMember() } }
                        .disabled(addUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }
            Section("\(members.count) members") {
                ForEach(members, id: \.member.userID) { entry in
                    HStack {
                        Text(entry.profile.username)
                        Spacer()
                        if entry.member.role == .admin {
                            Text("admin")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button("Leave Group", role: .destructive) {
                    Task {
                        try? await GroupRepository.leave(groupID: group.id)
                        dismiss()
                    }
                }
            }
        }
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
    }

    // MARK: - Sessions List

    private static let upcomingStates: Set<String> = [
        "scheduled", "lobby_open", "editing", "voting", "locked", "in_progress"
    ]
    private static let pastStates: Set<String> = ["completed", "abandoned"]

    private var sessionsList: some View {
        List {
            if upcomingSessions.isEmpty && pastSessions.isEmpty {
                Section {
                    Text("No upcoming sessions — schedule one from Home.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } else {
                if !upcomingSessions.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcomingSessions) { session in
                            NavigationLink {
                                LobbyView(session: session)
                            } label: {
                                sessionRow(session)
                            }
                        }
                    }
                }
                if !pastSessions.isEmpty {
                    Section("Past") {
                        ForEach(pastSessions) { session in
                            sessionRow(session)
                        }
                    }
                }
            }
        }
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
                    .fontWeight(.semibold)
            }
            if let scheduledFor = session.scheduledFor {
                Text(scheduledFor, style: .date)
                    + Text(" at ") + Text(scheduledFor, style: .time)
            }
            Text(session.state.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
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
