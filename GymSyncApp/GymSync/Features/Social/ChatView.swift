import SwiftUI
import PhotosUI

struct ChatView: View {
    let group: GymGroup

    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gsTheme) private var theme
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
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
                .background(theme.bg)
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                        Task { try? await ChatRepository.markRead(groupID: group.id,
                                                                  messageID: last.id) }
                    }
                }
            }

            if let errorText {
                Text(errorText)
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }

            // Typing indicator — 3 animated dots + name per canvas
            if !typingUsers.isEmpty {
                HStack(spacing: 7) {
                    TypingDotsView(theme: theme)
                    Text("\(typingUsers.sorted().joined(separator: ", ")) is typing…")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
                .padding(.bottom, 4)
            }

            // Input bar: bg fill, 2px top divider, icon button | surface field | accent send button
            inputBar
        }
        .background(theme.bg)
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

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Photo picker icon button — 38×38, bordered per canvas
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(theme.neutral700)
                    .frame(width: 38, height: 38)
                    .background(theme.bg)
                    .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
            }
            .disabled(isSendingImage)

            // Message field — surface bg, 1px divider border, 38px height
            TextField("Message", text: $draft, axis: .vertical)
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundStyle(theme.text)
                .tint(theme.accent)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(theme.surface)
                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))

            // Send button — accent primary, 38×38
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.bg)
                    .frame(width: 38, height: 38)
                    .background(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? theme.neutral400
                            : theme.accent
                    )
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 20)
        .background(theme.bg)
        .overlay(alignment: .top) {
            GSDivider()
        }
        .onChange(of: pickerItem) {
            guard let item = pickerItem else { return }
            pickerItem = nil
            Task { await sendImage(item) }
        }
    }

    // MARK: - Message Row

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        if message.isSystem {
            // System messages: centered, inline-block, 1px divider border per canvas
            systemMessageView(message)
        } else {
            let mine = message.authorID == appState.currentProfile?.id
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                // Sender kicker — only for incoming messages (flush-left architecture)
                if !mine, let author = message.authorID {
                    Text(usernames[author] ?? "…")
                        .font(GSFont.body(10, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                        .padding(.leading, 2)
                }
                messageContent(message, mine: mine)
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
                // Reaction pills
                if let messageReactions = reactions[message.id], !messageReactions.isEmpty {
                    let counts = Dictionary(grouping: messageReactions, by: \.emoji)
                        .mapValues(\.count)
                        .sorted { $0.key < $1.key }
                    HStack(spacing: 4) {
                        ForEach(counts, id: \.key) { emoji, count in
                            reactionPill(emoji: emoji, count: count)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
                }
            }
            // Flush-left for incoming; flush-right for outgoing
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        }
    }

    // MARK: - System Message

    @ViewBuilder
    private func systemMessageView(_ message: ChatMessage) -> some View {
        // PR auto-messages get accent100 bg + 3px left border accent per canvas
        if let body = message.body, body.contains("hit a PR") || body.contains("PR") {
            HStack(alignment: .top, spacing: 7) {
                Text("🔥")
                    .font(.system(size: 16))
                Text(body)
                    .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(theme.accent100)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 3)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 8)
        } else {
            // Standard system message: centered, inline border per canvas
            Text(message.body ?? "")
                .font(GSFont.bold(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .multilineTextAlignment(.center)
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Reaction Pill

    private func reactionPill(emoji: String, count: Int) -> some View {
        Text("\(emoji) \(count)")
            .font(GSFont.body(11, relativeTo: .caption))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(theme.divider, lineWidth: 1))
    }

    // MARK: - Message Content

    @ViewBuilder
    private func messageContent(_ message: ChatMessage, mine: Bool) -> some View {
        if message.deletedAt != nil {
            // Deleted: surface bg, italic
            Text("[deleted message]")
                .italic()
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundStyle(theme.neutral500)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(theme.surface)
        } else if message.kind == .image {
            // Image bubble: surface bg wrapper, 5px inner padding per canvas
            VStack(alignment: .leading, spacing: 0) {
                AsyncImage(url: imageURLs[message.id]) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(theme.neutral500)
                            .padding(10)
                    default:
                        ZStack {
                            theme.neutral300
                            ProgressView()
                                .tint(theme.neutral700)
                        }
                        .frame(width: 120, height: 120)
                    }
                }
                .frame(maxWidth: 240, maxHeight: 280)
            }
            .padding(5)
            .background(theme.surface)
        } else {
            // Text bubble per canvas:
            //   incoming → surface fill
            //   outgoing → accent fill + bg text
            Text(message.body ?? "")
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundStyle(mine ? theme.bg : theme.text)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(mine ? theme.accent : theme.surface)
                .frame(maxWidth: 260, alignment: mine ? .trailing : .leading)
        }
    }

    // MARK: - Data Operations (all preserved byte-identical to original)

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

// MARK: - TypingDotsView

/// Three pulsing neutral500 circles, matching canvas typing indicator treatment.
private struct TypingDotsView: View {
    let theme: GSTheme
    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            dot(delay: 0.0)
            dot(delay: 0.2)
            dot(delay: 0.4)
        }
        .frame(height: 10)
        .onAppear { phase = true }
    }

    private func dot(delay: Double) -> some View {
        Circle()
            .fill(theme.neutral500)
            .frame(width: 6, height: 6)
            .opacity(phase ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: phase
            )
    }
}
