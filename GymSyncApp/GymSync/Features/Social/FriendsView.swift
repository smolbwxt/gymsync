import SwiftUI

struct FriendsView: View {
    @State private var friends: [Profile] = []
    @State private var incoming: [Profile] = []
    @State private var outgoing: [Profile] = []
    @State private var addUsername = ""
    @State private var errorText: String?

    var body: some View {
        List {
            Section("Add Friend") {
                HStack {
                    TextField("username", text: $addUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Send") {
                        Task { await sendRequest() }
                    }
                    .disabled(addUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }

            if !incoming.isEmpty {
                Section("Requests") {
                    ForEach(incoming) { profile in
                        HStack {
                            Text(profile.username)
                            Spacer()
                            Button("Accept") {
                                Task {
                                    try? await FriendRepository.accept(requesterID: profile.id)
                                    await refresh()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Decline") {
                                Task {
                                    try? await FriendRepository.removeFriendship(with: profile.id)
                                    await refresh()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if !outgoing.isEmpty {
                Section("Sent") {
                    ForEach(outgoing) { profile in
                        HStack {
                            Text(profile.username)
                            Spacer()
                            Button("Cancel") {
                                Task {
                                    try? await FriendRepository.removeFriendship(with: profile.id)
                                    await refresh()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section("Friends") {
                if friends.isEmpty {
                    Text("No friends yet. Send a request by username.")
                        .foregroundStyle(.secondary)
                }
                ForEach(friends) { profile in
                    Text(profile.username)
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
        }
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
