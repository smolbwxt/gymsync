import SwiftUI
import PhotosUI

struct ChatView: View {
    let group: GymGroup

    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var messages: [ChatMessage] = []   // oldest-first for rendering
    @State private var reactions: [UUID: [ChatReaction]] = [:]
    @State private var usernames: [UUID: String] = [:]
    @State private var draft = ""
    @State private var realtime = ChatRealtimeService()
    @State private var errorText: String?
    @State private var typingUsers: Set<String> = []
    @State private var typingDebounce: Task<Void, Never>?
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageURLs: [UUID: URL] = [:]
    @State private var isSendingImage = false

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

            if !typingUsers.isEmpty {
                Text("\(typingUsers.sorted().joined(separator: ", ")) typing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo").font(.title3)
                }
                .disabled(isSendingImage)
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
            .onChange(of: pickerItem) {
                guard let item = pickerItem else { return }
                pickerItem = nil
                Task { await sendImage(item) }
            }
        }
        .task { await load() }
        .onChange(of: draft) {
            typingDebounce?.cancel()
            let isEmpty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Task { await realtime.setTyping(!isEmpty) }
            guard !isEmpty else { return }
            typingDebounce = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await realtime.setTyping(false)
            }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await load() }
        }
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
                messageContent(message)
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
            await resolveImageURLs()
            await realtime.subscribe(groupID: group.id, onInsert: { message in
                guard !messages.contains(where: { $0.id == message.id }) else { return }
                messages.append(message)
                Task { await resolveUsernames(); await resolveImageURLs() }
            }, onReaction: {
                Task { await refreshReactions() }
            })
            if let username = appState.currentProfile?.username {
                await realtime.subscribeTyping(groupID: group.id,
                                               selfUsername: username) { names in
                    typingUsers = names
                }
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
        typingDebounce?.cancel()
        Task { await realtime.setTyping(false) }
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

    @ViewBuilder
    private func messageContent(_ message: ChatMessage) -> some View {
        if message.deletedAt != nil {
            Text("[deleted message]").italic()
                .padding(10)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 14))
        } else if message.kind == .image {
            AsyncImage(url: imageURLs[message.id]) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary).padding(10)
                default:
                    ProgressView().frame(width: 120, height: 120)
                }
            }
            .frame(maxWidth: 240, maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            Text(message.body ?? "")
                .padding(10)
                .background(message.authorID == appState.currentProfile?.id
                                ? Color.accentColor.opacity(0.25)
                                : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func sendImage(_ item: PhotosPickerItem) async {
        isSendingImage = true
        defer { isSendingImage = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorText = "That image couldn't be loaded."
                return
            }
            let sent = try await ChatRepository.sendImage(groupID: group.id, imageData: data)
            if !messages.contains(where: { $0.id == sent.id }) {
                messages.append(sent)
            }
            await resolveImageURLs()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func resolveImageURLs() async {
        for message in messages where message.kind == .image {
            guard imageURLs[message.id] == nil,
                  let path = message.storagePath else { continue }
            imageURLs[message.id] = try? await StorageService.signedChatImageURL(path: path)
        }
    }
}
