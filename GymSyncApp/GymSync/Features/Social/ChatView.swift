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

// MARK: - ChatReportTarget

/// `.sheet(item:)` payload for reporting a message (Phase M Task 2) — a
/// small dedicated `Identifiable` rather than reusing `ChatMessage` itself,
/// since `authorID` must be a plain non-optional `UUID` here (guaranteed by
/// the `!mine, let authorID = message.authorID` guard at the one call site
/// that constructs this) and a fallback like `message.authorID ?? UUID()`
/// would be a silent-misreport smell if that guard were ever bypassed.
private struct ChatReportTarget: Identifiable {
    let id: UUID          // message id
    let authorID: UUID
}

// MARK: - ChatView

struct ChatView: View {
    /// What this chat surface is scoped to — a group's persistent chat, or
    /// a single session's sub-thread (Task 3, Phase F). Parameterizing this
    /// existing view (rather than a scoped sibling view) was picked because
    /// every data/realtime/AppState call site below only ever read
    /// `group.id` before this change — never `.name` or any other
    /// `GymGroup` field — so the reuse is a pure scope substitution, not a
    /// UI fork; a sibling would have had to duplicate message-bubble/
    /// reaction/system-message rendering (~400 of this file's ~740 lines)
    /// just to reach the same visual result. See task-3-report.md.
    enum Scope {
        case group(UUID)
        case session(sessionID: UUID, groupID: UUID?)

        /// group_id used for the push-suppression flag (`AppState.
        /// activeChatGroupID`) — mirrors `push_chat_mention`'s trigger,
        /// which always keys its enqueued push off `NEW.group_id`
        /// regardless of whether the row is a sub-thread message
        /// (supabase/migrations/20260716000001_push_schema.sql:311-318).
        /// `nil` only for a solo session's sub-thread, where that trigger's
        /// `WHERE gm.group_id = NEW.group_id` never matches a NULL group_id
        /// anyway (20260719000010_session_chat_subthreads.sql,
        /// "Deliberately untouched") — there is no such push to suppress.
        var groupIDForPushSuppression: UUID? {
            switch self {
            case .group(let id): return id
            case .session(_, let groupID): return groupID
            }
        }

        /// Key into `AppState.chatDrafts` (Task 6 item 2 — tab-switch
        /// draft persistence). Session sub-threads use `sessionID`, not
        /// `groupID`, so a solo session's sub-thread (`groupID == nil`)
        /// still gets its own slot, and so two different sessions in the
        /// same group never collide.
        var draftKey: UUID {
            switch self {
            case .group(let id): return id
            case .session(let sessionID, _): return sessionID
            }
        }
    }

    let scope: Scope

    init(group: GymGroup) {
        self.scope = .group(group.id)
    }

    /// `groupID` MUST be the session's own `group_id` (nil for a solo/
    /// ad-hoc session) — the sub-thread INSERT RLS binds it via `IS NOT
    /// DISTINCT FROM` against `sessions.group_id`
    /// (20260719000011_chat_subthread_lock_hardening.sql #5). Callers
    /// (LobbyView, GroupSessionLiveView) pass `session.groupID` straight
    /// from the `WorkoutSession` already in scope — see those files' chat
    /// sheet definitions.
    init(sessionID: UUID, groupID: UUID?) {
        self.scope = .session(sessionID: sessionID, groupID: groupID)
    }

    #if DEBUG
    /// Debug-only: true only via the catalog fixture init at the bottom of
    /// this file — skips `load()`'s live network fetch + realtime subscribe
    /// entirely so `CatalogHostView`'s `session-chat` state renders
    /// deterministically from a seeded fixture instead of racing an
    /// unauthenticated (and certain-to-fail) live query. Always false on
    /// every other path; compiled out of release entirely. Checked inside
    /// `load()` itself, not just at its `.task` call site, because ChatView
    /// has a SECOND path into `load()` — `.onChange(of: scenePhase)` —
    /// that the HomeGymSetupView precedent for this seam didn't need to
    /// account for.
    var catalogSkipLoad = false
    #endif

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
    // Task 6 item 1 (reliability/debt roll-up, .superpowers/sdd/progress.md:33
    // "signed-URL cache never re-resolves after 3600s expiry"): a signed URL
    // is only valid for 3600s (StorageService.signedChatImageURL); once
    // `imageURLs[id]` is populated it's never touched again by
    // `resolveImageURLs()`'s `guard imageURLs[message.id] == nil` — so a
    // chat sitting open past an hour would show a permanently-failed image
    // for anything scrolled into view after expiry. `imageURLRetried` bounds
    // the fix to ONE re-fetch per message per view lifetime (a genuinely
    // deleted/missing object must not retry forever).
    @State private var imageURLRetried: Set<UUID> = []

    // Phase M Task 2 (moderation/compliance): Report/Block on message rows.
    @State private var reportTarget: ChatReportTarget?
    @State private var blockAuthorID: UUID?
    @State private var showBlockConfirm = false

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
                        // chat_read_state stays group-scoped only (out of
                        // scope for session sub-threads — see
                        // 20260719000010_session_chat_subthreads.sql #5's
                        // "Deliberately untouched" note).
                        if case .group(let groupID) = scope {
                            Task { try? await ChatRepository.markRead(groupID: groupID,
                                                                      messageID: last.id) }
                        }
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
        .onAppear {
            // Suppresses the push banner for this chat's group_id while it's
            // open live (AppDelegate.willPresent, AppState.activeChatGroupID)
            // — see Scope.groupIDForPushSuppression's doc comment for why a
            // session sub-thread uses the SAME flag, keyed off the session's
            // own group_id. Left unset for a solo session's sub-thread (nil)
            // — no group-keyed push exists there to suppress.
            if let groupID = scope.groupIDForPushSuppression {
                appState.activeChatGroupID = groupID
            }
            // Task 6 item 2: restore a half-typed draft this chat had when
            // the tab was last switched away from (MainTabView recreates
            // this whole view on tab switch — see AppState.chatDrafts' doc
            // comment for the adjudication). No-op (empty string) if none
            // was saved.
            if let saved = appState.chatDrafts[scope.draftKey] {
                draft = saved
            }
        }
        .onDisappear {
            // Only clear the suppression flag if it's still pointing at THIS
            // chat's group — see GroupSessionLiveView's identical guard on
            // activeSessionID for why an unconditional nil is unsafe.
            if let groupID = scope.groupIDForPushSuppression, appState.activeChatGroupID == groupID {
                appState.activeChatGroupID = nil
            }
            // Persist (or clear) the draft so a tab switch away and back
            // doesn't silently discard in-progress composition. Empty/
            // whitespace-only drafts are removed rather than stored as ""
            // — nothing to restore, and keeps the dictionary from growing
            // unbounded with every chat ever opened.
            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                appState.chatDrafts.removeValue(forKey: scope.draftKey)
            } else {
                appState.chatDrafts[scope.draftKey] = draft
            }
            Task { await realtime.unsubscribe() }
        }
        // ChatView's inputBar is bottom-pinned; when reached via GroupView's
        // push (SocialTabView → GroupView → Chat sub-tab) it would otherwise
        // sit under the custom dock. GroupView also carries this modifier
        // (it covers ChatView's every sub-tab sibling too), so this is
        // belt-and-suspenders — see GSComponents.swift's GSHidesDock.
        .gsHidesDock()
        .sheet(item: $reportTarget) { target in
            ReportSheet(
                reportedUserID: target.authorID,
                contentType: .chatMessage,
                contentID: target.id
            )
        }
        // Literal text per brief: "Block @username? You won't see their
        // messages or requests." — ChatView only has the author's id (not a
        // Profile), so the title stays generic here (matches
        // RoutineDetailChoice's identical "no username on hand" case below).
        .confirmationDialog(
            "Block this user?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task { await blockAuthor() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see their messages or requests.")
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if isRecording {
                // Recording row: elapsed timer + cancel, hides text field per canvas
                recordingIndicator
            } else {
                // Normal row: photo | text field | mic | send (group) —
                // text field | send only for a session sub-thread (kind=
                // 'text' only in v1, task-3-brief.md; no frame precedent for
                // this row's sub-thread treatment — system-designed, see
                // docs/design/accepted-deviations.json's "session-chat"
                // entry).
                HStack(spacing: 8) {
                    // Photo picker icon button — 38×38, bordered per canvas
                    if case .group = scope {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Image(systemName: "photo")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(theme.neutral700)
                                .frame(width: 38, height: 38)
                                .background(theme.bg)
                                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
                        }
                        .disabled(isSendingImage)
                    }

                    // Message field — surface bg, 1px divider border, 38px height
                    TextField("Message", text: $draft, axis: .vertical)
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.text)
                        .tint(theme.accent)
                        .lineLimit(1...4)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 38)
                        .background(theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))

                    if case .group = scope {
                        // Mic (empty draft) or Send (non-empty draft) — matches the proof's
                        // idle row, which never shows a separate mic icon alongside send.
                        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            micButton
                        } else {
                            sendButton
                        }
                    } else {
                        // Session sub-thread: no voice recorder to swap in for
                        // an empty draft, so the send button stays put and
                        // just disables instead.
                        sendButton
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
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

    // MARK: - Send Button
    //
    // Extracted from the group row's inline non-empty-draft branch (was a
    // literal Button here, identical modifiers) so the session sub-thread
    // row above can reuse the exact same rendering — no visual change for
    // the group codepath.

    private var sendButton: some View {
        Button {
            Task { await send() }
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.bg)
                .frame(width: 38, height: 38)
                .background(theme.accent)
                .clipShape(Circle())   // redesign: rounded accent surface
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mic Button (hold to record)

    /// True while a live PTT voice room is connected (any sub-state — muted
    /// or transmitting) OR still connecting. Gates the voice-MESSAGE mic
    /// below: `VoiceRecorder`'s `exitRecordMode()` unconditionally resets
    /// `AVAudioSession` to `.ambient` on every recording end path, which
    /// would silently kill the still-connected room's audio out from under
    /// it (AUDIO SACRED RULE — only `VoiceRoomService`/`AudioSessionManager`
    /// may own the session while a room is live; see Dossier §B.3.4).
    ///
    /// Phase O Task 5 (3e follow-up queue item 2, "chat mic gate during
    /// .connecting" — final review's M1): `.connecting` is included, not
    /// just `.connected`. `VoiceRoomService.join()` calls
    /// `audioSession.enterVoiceMode()` (switching the session to
    /// `.playAndRecord`/`.voiceChat`) BEFORE it ever reaches `.connected` —
    /// the ownership window this gate exists to protect starts at
    /// `.connecting`, not after. Without this, tapping the chat mic during
    /// the connect handshake races `VoiceRecorder.startRecording()`'s own
    /// session reconfiguration against `join()`'s, and releasing the chat
    /// mic mid-connect would reset the session out from under a room that's
    /// about to finish connecting.
    private var isVoiceRoomActive: Bool {
        switch VoiceRoomService.shared.state {
        case .connected, .connecting:
            return true
        case .idle, .unavailable, .micDenied:
            return false
        }
    }

    private var micButton: some View {
        Image(systemName: "mic")
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(theme.neutral700)
            .frame(width: 44, height: 44)
            .background(theme.bg)
            .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
            .opacity((isSendingVoice || isVoiceRoomActive) ? 0.4 : 1)
            // onLongPressGesture with pressing: true → start, false → stop
            .onLongPressGesture(minimumDuration: 0.15, pressing: { pressing in
                guard !isSendingVoice, !isVoiceRoomActive else { return }
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
            .disabled(isSendingVoice || isVoiceRoomActive)
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

            // Decorative waveform bars (no live audio metering — visual only)
            RecordingWaveformView(theme: theme)

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
                        // Phase M Task 2: Report/Block, incoming messages
                        // only (can't report/block yourself; system/
                        // soundboard-echo messages never reach this branch —
                        // see messageRow's isSystem/soundboardEcho guards).
                        if !mine, let authorID = message.authorID {
                            Divider()
                            Button {
                                reportTarget = ChatReportTarget(id: message.id, authorID: authorID)
                            } label: {
                                Label("Report Message", systemImage: "flag")
                            }
                            Button(role: .destructive) {
                                blockAuthorID = authorID
                                showBlockConfirm = true
                            } label: {
                                Label("Block User", systemImage: "nosign")
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
            // Celebration card: accent-fill/border, single inline sentence
            // (flame + bold body). SF flame per the emoji sweep (spec §7).
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.accent)
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
            .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.accent.opacity(0.35), lineWidth: 1))
            .padding(.horizontal, 8)
        } else {
            // Standard system message: centered, inline border per canvas
            Text(message.body ?? "")
                .font(GSFont.bold(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .multilineTextAlignment(.center)
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
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
            .background(Capsule().fill(theme.neutral300))
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
                    Text(message.body ?? "Sound")
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
                            // Most "failures" here are an expired signed URL
                            // (3600s TTL), not a genuinely missing object —
                            // re-resolve once so a long-dwell chat recovers
                            // without the user having to leave and re-enter.
                            .task { await retryImageURL(for: message) }
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
            // Onyx alignment (2026-07-31): bubbles are rounded — the
            // zero-radius rectangles were pre-redesign canvas literals.
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
                // Onyx alignment (2026-07-31) — see the voice bubble above.
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: 260, alignment: mine ? .trailing : .leading)
        }
    }

    // MARK: - Data Operations (group codepath preserved byte-identical to original)

    private func load() async {
        #if DEBUG
        if catalogSkipLoad { return }
        #endif
        do {
            let page: [ChatMessage]
            switch scope {
            case .group(let groupID):
                page = try await ChatRepository.messages(groupID: groupID)
            case .session(let sessionID, _):
                page = try await ChatRepository.sessionMessages(sessionID: sessionID)
            }
            messages = page.reversed()
            await refreshReactions()
            await resolveUsernames()
            await resolveImageURLs()

            let onInsert: @MainActor (ChatMessage) -> Void = { message in
                guard !messages.contains(where: { $0.id == message.id }) else { return }
                messages.append(message)
                Task { await resolveUsernames(); await resolveImageURLs() }
            }
            let onReaction: @MainActor () -> Void = {
                Task { await refreshReactions() }
            }

            switch scope {
            case .group(let groupID):
                await realtime.subscribe(groupID: groupID, onInsert: onInsert, onReaction: onReaction)
                if let username = appState.currentProfile?.username {
                    await realtime.subscribeTyping(groupID: groupID,
                                                   selfUsername: username) { names in
                        typingUsers = names
                    }
                }
            case .session(let sessionID, _):
                // No subscribeTyping call — sub-thread typing indicators are
                // out of v1 scope; `realtime.setTyping()` in `.onChange(of:
                // draft)` stays a safe no-op (see ChatRealtimeService.
                // subscribe(sessionID:...)'s doc comment).
                await realtime.subscribe(sessionID: sessionID, onInsert: onInsert, onReaction: onReaction)
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
            let sent: ChatMessage
            switch scope {
            case .group(let groupID):
                sent = try await ChatRepository.send(groupID: groupID, body: body)
            case .session(let sessionID, let groupID):
                sent = try await ChatRepository.sendSessionMessage(
                    sessionID: sessionID, groupID: groupID, body: body)
            }
            if !messages.contains(where: { $0.id == sent.id }) {
                messages.append(sent)
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // Phase M Task 2: block a message's author. Spec: "chat: filter local
    // messages" — the RLS-fixed-forward SELECT policy (Task 1) already hides
    // this author's rows on the next fetch/realtime event, but messages
    // already sitting in `messages` were fetched before the block existed,
    // so they need the same client-side removal here.
    private func blockAuthor() async {
        guard let authorID = blockAuthorID else { return }
        do {
            try await ModerationRepository.block(userID: authorID)
            messages.removeAll { $0.authorID == authorID }
            errorText = nil
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
        // Defense in depth: the photo picker button is already hidden for a
        // session sub-thread (kind='text' only in v1) — this guard is the
        // belt-and-suspenders backstop in case this function is ever reached
        // another way (e.g. `.onChange(of: pickerItem)` firing on stale
        // state), mirroring this file's other defensive guards.
        guard case .group(let groupID) = scope else { return }
        isSendingImage = true
        defer { isSendingImage = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorText = "That image couldn't be loaded."
                return
            }
            let sent = try await ChatRepository.sendImage(groupID: groupID, imageData: data)
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

    /// Re-fetches a fresh signed URL for one image bubble after
    /// `AsyncImage` reports `.failure` — bounded to a single attempt per
    /// message (`imageURLRetried`) so a truly-missing/orphaned object fails
    /// once and stays failed, rather than retry-looping. See
    /// `imageURLRetried`'s declaration for the expiry scenario this covers.
    ///
    /// Fix wave 1 (Task 6 review, MINOR 3): only overwrite `imageURLs[id]`
    /// on a SUCCESSFUL retry. The retry itself is a network call and can
    /// fail transiently — `try?` discarding that into `nil` used to replace
    /// the (merely expired, not missing) URL with `nil`, and
    /// `AsyncImage(url: nil)` sits in `.empty` forever (a permanent spinner,
    /// worse than the old "Image unavailable" state it was showing before
    /// the retry). Keeping the previous URL on failure means AsyncImage
    /// re-evaluates the same expired URL, gets `.failure` again, and the
    /// "Image unavailable" label renders as it did pre-retry.
    private func retryImageURL(for message: ChatMessage) async {
        guard !imageURLRetried.contains(message.id),
              let path = message.storagePath else { return }
        imageURLRetried.insert(message.id)
        if let refreshed = try? await StorageService.signedChatImageURL(path: path) {
            imageURLs[message.id] = refreshed
        }
    }

    private func sendVoice(url: URL, duration: TimeInterval) async {
        // Defense in depth — see sendImage's identical guard above; the mic
        // button is hidden for a session sub-thread, so this path is only
        // reachable in group scope.
        guard case .group(let groupID) = scope else { return }
        isSendingVoice = true
        defer { isSendingVoice = false }
        do {
            let sent = try await ChatRepository.sendVoice(
                groupID: groupID, fileURL: url, duration: duration)
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

// MARK: - RecordingWaveformView

/// Decorative animated bars shown in the voice-recording input row.
/// Purely visual — not driven by live audio metering.
private struct RecordingWaveformView: View {
    let theme: GSTheme
    @State private var animate = false

    private static let heights: [CGFloat] = [6, 12, 8, 16, 10, 14, 7]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(Self.heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(theme.accent)
                    .frame(width: 3, height: animate ? height : height * 0.4)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.08),
                        value: animate
                    )
            }
        }
        .frame(height: 16)
        .onAppear { animate = true }
    }
}

// MARK: - Catalog fixture seam (Task 3 — `session-chat` catalog case)

#if DEBUG
extension ChatView {
    /// Debug-only seam for the design-parity screen catalog: seeds
    /// `messages`/`usernames` directly and sets `catalogSkipLoad` so `load()`
    /// never fires its live fetch/subscribe. Added here (rather than a
    /// third public init) because `_messages`/`_usernames` are `private`
    /// `@State` — this initializer can only assign them because it lives in
    /// the SAME FILE as those declarations (same idiom as
    /// HomeGymSetupView.swift's `catalogSearchQuery` init).
    init(catalogFixtureMessages messages: [ChatMessage],
         catalogFixtureUsernames usernames: [UUID: String] = [:],
         scope: Scope) {
        self.scope = scope
        _messages = State(initialValue: messages)
        _usernames = State(initialValue: usernames)
        catalogSkipLoad = true
    }
}
#endif
