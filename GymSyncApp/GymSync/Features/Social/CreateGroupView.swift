import SwiftUI

struct CreateGroupView: View {
    let onCreated: (GymGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var friends: [Profile] = []
    @State private var selected: Set<UUID> = []
    @State private var isCreating = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Name") {
                    TextField("e.g. Push Crew", text: $name)
                }
                Section("Add Friends") {
                    if friends.isEmpty {
                        Text("No friends to add yet — you can add members later.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(friends) { profile in
                        Button {
                            if selected.contains(profile.id) {
                                selected.remove(profile.id)
                            } else {
                                selected.insert(profile.id)
                            }
                        } label: {
                            HStack {
                                Text(profile.username).foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(profile.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("New Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .task {
                friends = (try? await FriendRepository.friends()) ?? []
            }
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        let group: GymGroup
        do {
            group = try await GroupRepository.create(
                name: name.trimmingCharacters(in: .whitespaces))
        } catch let error as GymSyncError {
            errorText = error.errorDescription
            return
        } catch {
            errorText = error.localizedDescription
            return
        }

        var failedUsernames: [String] = []
        for profile in friends.filter({ selected.contains($0.id) }) {
            do {
                try await GroupRepository.addMember(groupID: group.id,
                                                    username: profile.username)
            } catch {
                failedUsernames.append(profile.username)
            }
        }

        onCreated(group)
        if failedUsernames.isEmpty {
            dismiss()
        } else {
            errorText = "Group created, but couldn't add: "
                + failedUsernames.joined(separator: ", ")
                + ". You can add them from the group's Members tab."
        }
    }
}
