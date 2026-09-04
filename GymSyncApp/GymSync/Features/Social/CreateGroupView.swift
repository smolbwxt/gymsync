import SwiftUI
import PhotosUI
import UIKit

struct CreateGroupView: View {
    let onCreated: (GymGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme
    @State private var name = ""
    @State private var friends: [Profile] = []
    @State private var selected: Set<UUID> = []
    @State private var isCreating = false
    @State private var errorText: String?
    // Phase F Task 6 (2.5 deferral): avatar picker, same components as the
    // GROUP avatar flow (GroupView.membersList) — PhotosPicker +
    // ImageProcessor + StorageService.uploadGroupAvatar via
    // GroupRepository.setAvatar. Deferred upload: unlike GroupView (editing
    // an EXISTING group, so `groupID` is already known and `onChange`
    // uploads immediately), this screen creates the group only on submit —
    // there is no groupID to upload against until `create()` has already
    // called `GroupRepository.create`. So the picked image is held as raw
    // `Data` and uploaded right after that call succeeds, before
    // `onCreated(group)` fires (see `create()`).
    @State private var avatarItem: PhotosPickerItem?
    @State private var pendingAvatarData: Data?

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
                            PhotosPicker(selection: $avatarItem, matching: .images) {
                                avatarPreview
                            }

                            TextField("e.g. Push Crew", text: $name)
                                .font(GSFont.body(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
                                .tint(theme.accent)
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background(theme.surface)
                                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
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
                        // gs3D pass (2026-09-03): the friend multi-select
                        // rows join the extruded language. The hairline that
                        // separated FLAT rows retires — a lip cannot read
                        // against an abutting neighbor, so 8pt of air does
                        // the separating now.
                        VStack(spacing: 8) {
                            ForEach(friends) { profile in
                                Button {
                                    if selected.contains(profile.id) {
                                        selected.remove(profile.id)
                                    } else {
                                        selected.insert(profile.id)
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        GSInitialsAvatar(name: profile.username,
                                                          avatarURL: profile.avatarURL, size: 36)

                                        nameBlock(profile)

                                        Spacer()

                                        selectionCheckbox(isSelected: selected.contains(profile.id))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .overlay(
                                        selected.contains(profile.id)
                                            ? RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                                                .strokeBorder(theme.accent, lineWidth: 2)
                                            : nil
                                    )
                                    .contentShape(Rectangle())
                                }
                                // gs3D pass (2026-09-03): sinking extruded row;
                                // the label sheds its fills (accent100 retired)
                                // and selection reads as the 2pt accent ring —
                                // the ScheduleSessionView precedent (77a6c28).
                                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                            }
                        }
                        // The rows carry the card inset now (the label used to
                        // own the 16pt itself); 10pt inside the face matches
                        // the precedent's row metrics.
                        .padding(.horizontal, 16)
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
            .onChange(of: avatarItem) {
                guard let item = avatarItem else { return }
                avatarItem = nil
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        errorText = "That image couldn't be loaded."
                        return
                    }
                    pendingAvatarData = data
                    errorText = nil
                }
            }
        }
    }

    // 44×44 preview for the avatar-picker row above: the picked photo
    // (decoded locally — no groupID exists yet to upload against, see
    // `pendingAvatarData`'s doc comment) once one has been chosen, else the
    // same live initials-of-typed-name preview this row always showed.
    @ViewBuilder
    private var avatarPreview: some View {
        if let pendingAvatarData, let uiImage = UIImage(data: pendingAvatarData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipped()
        } else {
            GSInitialsAvatar(
                name: name.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "New Group" : name,
                size: 44
            )
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
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(isSelected ? theme.accent : theme.neutral400, lineWidth: 1))
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
        var group: GymGroup
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

        // Deferred avatar upload (see `pendingAvatarData`'s doc comment) —
        // best-effort: a failed upload here does not block group creation,
        // same "non-blocking secondary step" philosophy as the member-add
        // loop below. `group` is reassigned with the fresh `avatarURL` so
        // `onCreated(group)` — and whatever screen it pushes next — sees
        // the photo immediately rather than only after a manual refresh.
        // GymGroup has no custom initializer (unlike Profile/ChatMessage),
        // so the synthesized memberwise init is available here.
        var uploadFailures: [String] = []
        if let pendingAvatarData {
            do {
                let url = try await GroupRepository.setAvatar(groupID: group.id, imageData: pendingAvatarData)
                group = GymGroup(id: group.id, name: group.name, avatarURL: url,
                                  createdBy: group.createdBy, createdAt: group.createdAt)
            } catch {
                uploadFailures.append("photo")
            }
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
        if uploadFailures.isEmpty && failedUsernames.isEmpty {
            dismiss()
        } else {
            var errorMessages: [String] = []
            if !uploadFailures.isEmpty {
                errorMessages.append("the photo upload failed — you can add it from the group screen")
            }
            if !failedUsernames.isEmpty {
                errorMessages.append("couldn't add: " + failedUsernames.joined(separator: ", ") + ". You can add them from the group's Members tab.")
            }
            errorText = "Group created, but " + errorMessages.joined(separator: " and ")
        }
    }
}
