import SwiftUI

struct FriendsView: View {
    @State private var friends: [Profile] = []
    @State private var incoming: [Profile] = []
    @State private var outgoing: [Profile] = []
    @State private var addUsername = ""
    @State private var errorText: String?

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
                            GSInitialsAvatar(name: profile.username, size: 36)
                            Text(profile.username)
                                .font(GSFont.bodyMedium(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
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
                            GSInitialsAvatar(name: profile.username, size: 36)
                            Text(profile.username)
                                .font(GSFont.bodyMedium(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
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
                if friends.isEmpty {
                    Text("No friends yet. Send a request by username.")
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.neutral500)
                        .listRowBackground(theme.bg)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(friends) { profile in
                        HStack(spacing: 10) {
                            GSInitialsAvatar(name: profile.username, size: 36)
                            Text(profile.username)
                                .font(GSFont.bodyMedium(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
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
        friends = (try? await FriendRepository.friends()) ?? []
        incoming = (try? await FriendRepository.incomingRequests()) ?? []
        outgoing = (try? await FriendRepository.outgoingRequests()) ?? []
    }
}
