import SwiftUI

struct ChatView: View {
    let group: GymGroup

    @Environment(AppState.self) private var appState
    @State private var messages: [ChatMessage] = []   // oldest-first for rendering
    @State private var reactions: [UUID: [ChatReaction]] = [:]
    @State private var usernames: [UUID: String] = [:]
    @State private var draft = ""
    @State private var realtime = ChatRealtimeService()
    @State private var errorText: String?

    private static let reactionChoices = ["👍", "🔥", "💪", "😂"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                        Task { try? await ChatRepository.markRead(groupID: group.id,
                                                                  messageID: last.id) }
                    }
                }
            }

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.footnote)
            }

            HStack {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .task { await load() }
        .onDisappear { Task { await realtime.unsubscribe() } }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        if message.isSystem {
            Text(message.body ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            let mine = message.authorID == appState.currentProfile?.id
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if !mine, let author = message.authorID {
                    Text(usernames[author] ?? "…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(message.deletedAt != nil ? "[deleted message]" : (message.body ?? ""))
                    .italic(message.deletedAt != nil)
                    .padding(10)
                    .background(mine ? Color.accentColor.opacity(0.25)
                                     : Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 14))
                    .contextMenu {
                        ForEach(Self.reactionChoices, id: \.self) { emoji in
                            Button(emoji) {
                                Task {
                                    try? await ChatRepository.react(
                                        messageID: message.id, emoji: emoji)
                                    await refreshReactions()
                                }
                            }
                        }
                    }
                if let messageReactions = reactions[message.id], !messageReactions.isEmpty {
                    let counts = Dictionary(grouping: messageReactions, by: \.emoji)
                        .mapValues(\.count)
                        .sorted { $0.key < $1.key }
                    HStack(spacing: 4) {
                        ForEach(counts, id: \.key) { emoji, count in
                            Text("\(emoji) \(count)")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemBackground),
                                            in: Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        }
    }

    private func load() async {
        do {
            let page = try await ChatRepository.messages(groupID: group.id)
            messages = page.reversed()
            await refreshReactions()
            await resolveUsernames()
            await realtime.subscribe(groupID: group.id) { message in
                guard !messages.contains(where: { $0.id == message.id }) else { return }
                messages.append(message)
                Task { await resolveUsernames() }
            }
            errorText = nil
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        do {
            let sent = try await ChatRepository.send(groupID: group.id, body: body)
            if !messages.contains(where: { $0.id == sent.id }) {
                messages.append(sent)
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func refreshReactions() async {
        let all = (try? await ChatRepository.reactions(
            messageIDs: messages.map(\.id))) ?? []
        reactions = Dictionary(grouping: all, by: \.messageID)
    }

    private func resolveUsernames() async {
        let unknown = Set(messages.compactMap(\.authorID)).subtracting(usernames.keys)
        guard !unknown.isEmpty else { return }
        let profiles = (try? await ProfileRepository.fetchMany(ids: Array(unknown))) ?? []
        for profile in profiles {
            usernames[profile.id] = profile.username
        }
    }
}
