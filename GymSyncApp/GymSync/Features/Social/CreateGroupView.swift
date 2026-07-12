import SwiftUI

struct CreateGroupView: View {
    let onCreated: (GymGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme
    @State private var name = ""
    @State private var friends: [Profile] = []
    @State private var selected: Set<UUID> = []
    @State private var isCreating = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Group name field
                    VStack(alignment: .leading, spacing: 8) {
                        GSSectionHeader("Group name")
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        HStack(spacing: 10) {
                            GSInitialsAvatar(
                                name: name.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? "New Group" : name,
                                size: 44
                            )

                            TextField("e.g. Push Crew", text: $name)
                                .font(GSFont.body(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
                                .tint(theme.accent)
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background(theme.surface)
                                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                        }
                        .padding(.horizontal, 16)
                    }

                    GSDivider()
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    // Add Friends section
                    HStack {
                        GSSectionHeader("Add friends")
                        Spacer()
                        if !selected.isEmpty {
                            Text("\(selected.count) selected · max 25")
                                .font(GSFont.body(11, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    if friends.isEmpty {
                        Text("No friends to add yet — you can add members later.")
                            .font(GSFont.body(14, relativeTo: .body))
                            .foregroundStyle(theme.neutral500)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(friends) { profile in
                                Button {
                                    if selected.contains(profile.id) {
                                        selected.remove(profile.id)
                                    } else {
                                        selected.insert(profile.id)
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        GSInitialsAvatar(name: profile.username, size: 36)

                                        nameBlock(profile)

                                        Spacer()

                                        selectionCheckbox(isSelected: selected.contains(profile.id))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        selected.contains(profile.id)
                                            ? theme.accent100
                                            : Color.clear
                                    )
                                    .overlay(
                                        selected.contains(profile.id)
                                            ? Rectangle().strokeBorder(theme.accent, lineWidth: 1)
                                            : nil
                                    )
                                }
                                .buttonStyle(.plain)

                                if profile.id != friends.last?.id {
                                    Rectangle()
                                        .fill(theme.divider)
                                        .frame(height: 1)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                    }

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    // Create button
                    Button {
                        Task { await create() }
                    } label: {
                        if selected.isEmpty {
                            Text("Create Group")
                        } else {
                            Text("Create Group · \(selected.count + 1) members")
                        }
                    }
                    .buttonStyle(GSPrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .background(theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("New Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .font(GSFont.bold(14, relativeTo: .body))
                        .foregroundStyle(
                            name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating
                                ? theme.neutral500 : theme.accent
                        )
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .task {
                friends = (try? await FriendRepository.friends()) ?? []
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

    // Filled checkbox-square with checkmark when selected, empty outline otherwise.
    private func selectionCheckbox(isSelected: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(isSelected ? theme.accent : Color.clear)
                .overlay(Rectangle().strokeBorder(isSelected ? theme.accent : theme.neutral400, lineWidth: 1))
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.bg)
            }
        }
        .frame(width: 20, height: 20)
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
