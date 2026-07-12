import AVFoundation
import SwiftUI
import PhotosUI

// MARK: - VoiceBubblePlayer

/// Manages playback of voice-message bubbles.
/// One active player at a time — starting a new bubble stops the previous.
/// NEVER touches AVAudioSession category (ambient config stays in force — AUDIO SACRED RULE).
@MainActor
final class VoiceBubblePlayer: ObservableObject {

    static let shared = VoiceBubblePlayer()
    private init() {}

    /// message.id of the currently playing bubble; nil when idle.
    @Published private(set) var playingID: UUID?

    private var player: AVAudioPlayer?
    private var playerTask: Task<Void, Never>?

    /// Local tmp-cache: message id → downloaded audio file URL.
    private var cache: [UUID: URL] = [:]

    /// Toggle play/pause for a given message.  If another bubble is playing,
    /// it is stopped first.  Downloads the signed URL on first play (cached by message id).
    func toggle(messageID: UUID, storagePath: String) async {
        if playingID == messageID {
            stop()
            return
        }
        stop()

        do {
            let fileURL = try await resolve(messageID: messageID, storagePath: storagePath)
            let p = try AVAudioPlayer(contentsOf: fileURL)
            // AUDIO SACRED RULE: do NOT set audio session category here.
            player = p
            playingID = messageID
            p.play()

            // Reset when playback finishes
            let dur = p.duration
            playerTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((dur + 0.2) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if self?.playingID == messageID {
                    self?.playingID = nil
                    self?.player = nil
                }
            }
        } catch {
            AppLogger.audio.error("VoiceBubblePlayer: \(error, privacy: .public)")
            playingID = nil
        }
    }

    func stop() {
        playerTask?.cancel()
        playerTask = nil
        player?.stop()
        player = nil
        playingID = nil
    }

    // MARK: - Private

    private func resolve(messageID: UUID, storagePath: String) async throws -> URL {
        if let cached = cache[messageID] { return cached }
        let signedURL = try await StorageService.signedChatAudioURL(path: storagePath)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_\(messageID.uuidString).m4a")
        if !FileManager.default.fileExists(atPath: dest.path) {
            let (tmp, _) = try await URLSession.shared.download(from: signedURL)
            try FileManager.default.moveItem(at: tmp, to: dest)
        }
        cache[messageID] = dest
        return dest
    }
}

// MARK: - ChatView

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

    // Voice recording state
    @ObservedObject private var voicePlayer = VoiceBubblePlayer.shared
    @State private var voiceRecorder = VoiceRecorder()
    @State private var isRecording = false
    @State private var recordStart: Date?
    @State private var isSendingVoice = false

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
        VStack(spacing: 0) {
            if isRecording {
                // Recording row: elapsed timer + cancel, hides text field per canvas
                recordingIndicator
            } else {
                // Normal row: photo | text field | mic | send
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

                    // Mic button — hold to record per canvas; 38×38, bordered
                    micButton

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
            }
        }
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

    // MARK: - Mic Button (hold to record)

    private var micButton: some View {
        Image(systemName: "mic")
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(theme.neutral700)
            .frame(width: 44, height: 44)
            .background(theme.bg)
            .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
            .opacity(isSendingVoice ? 0.4 : 1)
            // onLongPressGesture with pressing: true → start, false → stop
            .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
                guard !isSendingVoice else { return }
                if pressing {
                    guard !isRecording else { return }
                    isRecording = true
                    recordStart = Date()
                    Task {
                        do {
                            try await voiceRecorder.startRecording()
                        } catch {
                            isRecording = false
                            recordStart = nil
                            errorText = (error as? GymSyncError)?.errorDescription
                                ?? error.localizedDescription
                        }
                    }
                } else {
                    // Finger lifted — stop and send if long enough
                    guard isRecording else { return }
                    isRecording = false
                    let start = recordStart
                    recordStart = nil
                    guard let result = voiceRecorder.stopRecording() else { return }
                    let elapsed = start.map { Date().timeIntervalSince($0) } ?? result.duration
                    guard elapsed >= 1.0 else {
                        // Too short — discard
                        try? FileManager.default.removeItem(at: result.url)
                        return
                    }
                    Task { await sendVoice(url: result.url, duration: result.duration) }
                }
            }, perform: {
                // Long press recognized (≥0.15s) — no additional action needed;
                // the pressing: callback already manages state transitions.
            })
            .disabled(isSendingVoice)
    }

    // MARK: - Recording Indicator

    private var recordingIndicator: some View {
        HStack(spacing: 12) {
            // Cancel button
            Button {
                isRecording = false
                recordStart = nil
                voiceRecorder.cancelRecording()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.neutral500)
            }
            .buttonStyle(.plain)

            // Red mic dot
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Text("Recording…")
                .font(GSFont.body(13, relativeTo: .callout))
                .foregroundStyle(theme.neutral700)

            Spacer()

            // Live elapsed timer — zero Timers: Text with .timer style
            if let start = recordStart {
                Text(start, style: .timer)
                    .font(GSFont.bold(13, relativeTo: .callout))
                    .foregroundStyle(theme.accent)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 20)
    }

    // MARK: - Message Row

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        if message.isSystem {
            // System messages: centered, inline-block, 1px divider border per canvas
            systemMessageView(message)
        } else if message.kind == .soundboardEcho {
            // Soundboard echo: centered inline (canvas treatment), no sender kicker
            messageContent(message, mine: false)
                .padding(.vertical, 2)
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
        if message.kind == .systemPR {
            // Canvas celebration card: accent-fill/border, 🔥 uppercase kicker "NEW PR",
            // Archivo bold body — replaces the previous body-text-sniffing treatment.
            VStack(alignment: .leading, spacing: 5) {
                // Kicker row: fire emoji + "NEW PR" uppercase in tight tracking
                HStack(spacing: 5) {
                    Text("🔥")
                        .font(.system(size: 14))
                    Text("NEW PR")
                        .font(.custom("Archivo-Bold", size: 11))
                        .tracking(1.6)
                        .foregroundStyle(theme.accent700)
                }
                // Message body in Archivo bold
                Text(message.body ?? "")
                    .font(.custom("Archivo-Bold", size: 13))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accent100)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: 3)
            }
            .overlay(Rectangle().strokeBorder(theme.accent.opacity(0.35), lineWidth: 1))
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
        } else if message.kind == .soundboardEcho {
            // Canvas soundboard echo: centered inline block with dashed divider border.
            // 🔊 icon + body text; tapping replays the sound from the payload slug.
            let slug = message.payload?["sound_slug"]?.stringValue
            Button {
                guard let s = slug else { return }
                Task { await SoundboardPlayer.shared.play(slug: s) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 11, weight: .semibold))
                    Text(message.body ?? "🔊")
                        .font(GSFont.bold(11, relativeTo: .caption2))
                        .lineLimit(2)
                }
                .foregroundStyle(theme.neutral700.opacity(0.85))
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .overlay(
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(theme.divider)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
            .disabled(slug == nil)
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
        } else if message.kind == .audio {
            // Voice bubble per canvas: play/pause button + duration label in a GS bubble.
            // Colour treatment mirrors text: outgoing = accent fill; incoming = surface fill.
            let isPlaying = voicePlayer.playingID == message.id
            let duration = message.body ?? "0:00"
            let storagePath = message.storagePath ?? ""

            HStack(spacing: 8) {
                Button {
                    Task {
                        await voicePlayer.toggle(
                            messageID: message.id,
                            storagePath: storagePath)
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(mine ? theme.bg : theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(storagePath.isEmpty)

                Text(duration)
                    .font(GSFont.bold(13, relativeTo: .callout))
                    .foregroundStyle(mine ? theme.bg : theme.text)
                    .monospacedDigit()
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(mine ? theme.accent : theme.surface)
            .frame(maxWidth: 180, alignment: mine ? .trailing : .leading)
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

    private func sendVoice(url: URL, duration: TimeInterval) async {
        isSendingVoice = true
        defer { isSendingVoice = false }
        do {
            let sent = try await ChatRepository.sendVoice(
                groupID: group.id, fileURL: url, duration: duration)
            // Dedup-guard: realtime subscription may deliver it first
            if !messages.contains(where: { $0.id == sent.id }) {
                messages.append(sent)
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
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
