import Foundation
import Supabase

// ── SessionBroadcastService ───────────────────────────────────────────────────
//
// Manages ephemeral broadcast messaging on the `session:{id}` realtime channel.
//
// Wire shapes (spec §5):
//   soundboard event: { "user_id": uuid-string, "sound_slug": slug, "ts": ms }
//   reaction  event:  { "user_id": uuid-string, "emoji": string,    "ts": ms }
//
// Broadcast is a DIFFERENT primitive from postgres_changes:
//   • Receive: channel.broadcastStream(event:) -> AsyncStream<JSONObject>
//     (supabase-swift 2.51 API — JSONObject = [String: AnyJSON])
//   • Send:    channel.broadcast(event:message:) async throws
//
// SDK drift note (mirrors the presence adaptation in LobbyRealtimeService):
//   - broadcastStream(event:) is the async-stream API introduced in supabase-swift 2.x.
//     It replaces the older callback-based onBroadcast(event:callback:).
//   - Broadcast channels do NOT require a postgres publication or table filter;
//     they need no postgresChange() registration — pure pub/sub via the realtime server.
//   - Same register-before-subscribe ordering rule as postgres_changes applies:
//     call broadcastStream(event:) before await channel.subscribe().
//   - channel.broadcast(event:message:) is async throws in 2.51; send errors are
//     swallowed (ephemeral semantics — missed events lost by design).
//
// Rate limit: 1 send per second shared across all sends from this instance.
// Drops silently (spec: "drop, don't queue").
//
// Sound echo: sendSound also inserts a chat_messages row (kind='soundboard_echo')
// when groupID is non-nil, so the event is durable in chat history.

@MainActor
final class SessionBroadcastService {

    // MARK: - Channel

    private var channel: RealtimeChannelV2?
    private var broadcastTask: Task<Void, Never>?

    // MARK: - Rate limit (1/s, shared across sounds + reactions)

    private var lastSentAt: Date = .distantPast

    // MARK: - Subscribe

    /// Subscribe to soundboard + reaction broadcast events for a session.
    ///
    /// - Parameters:
    ///   - sessionID:     The session to subscribe to (channel: `session:{id}`).
    ///   - onSoundboard:  Called on MainActor with (userID, soundSlug) when a soundboard broadcast arrives.
    ///   - onReaction:    Called on MainActor with (userID, emoji) when a reaction broadcast arrives.
    func subscribe(
        sessionID: UUID,
        onSoundboard: @escaping @MainActor (UUID, String) -> Void,
        onReaction:   @escaping @MainActor (UUID, String) -> Void
    ) async {
        await unsubscribe()

        let ch = SupabaseService.shared.client
            .channel("session:\(sessionID.uuidString)")

        // Register broadcast stream iterators BEFORE subscribing.
        // (Same ordering rule as postgres_changes — SDK wires filters during subscribe.)
        let soundboardStream = ch.broadcastStream(event: "soundboard")
        let reactionStream   = ch.broadcastStream(event: "reaction")

        self.channel = ch
        await ch.subscribe()

        broadcastTask = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in

                // ── soundboard ────────────────────────────────────────────
                group.addTask { @MainActor in
                    for await payload in soundboardStream {
                        guard
                            let rawUID = payload["user_id"]?.stringValue,
                            let uid    = UUID(uuidString: rawUID),
                            let slug   = payload["sound_slug"]?.stringValue
                        else {
                            AppLogger.soundboard.error(
                                "broadcast: malformed soundboard payload")
                            continue
                        }
                        onSoundboard(uid, slug)
                    }
                }

                // ── reaction ──────────────────────────────────────────────
                group.addTask { @MainActor in
                    for await payload in reactionStream {
                        guard
                            let rawUID = payload["user_id"]?.stringValue,
                            let uid    = UUID(uuidString: rawUID),
                            let emoji  = payload["emoji"]?.stringValue
                        else {
                            AppLogger.soundboard.error(
                                "broadcast: malformed reaction payload")
                            continue
                        }
                        onReaction(uid, emoji)
                    }
                }
            }
        }
    }

    // MARK: - Unsubscribe

    func unsubscribe() async {
        broadcastTask?.cancel()
        broadcastTask = nil
        if let ch = channel {
            await SupabaseService.shared.client.removeChannel(ch)
        }
        channel = nil
    }

    // MARK: - Send (with shared rate limit)

    /// Broadcast a soundboard event and (if groupID provided) insert a chat echo.
    ///
    /// - Parameters:
    ///   - sessionID:   The active session.
    ///   - groupID:     The session's group chat; echo inserted only when non-nil.
    ///   - slug:        Sound slug (e.g. "airhorn").
    func sendSound(sessionID: UUID, groupID: UUID?, slug: String) async {
        guard rateAllowed() else { return }
        guard let me = await SupabaseService.shared.currentUserID() else { return }

        await broadcastRaw(
            sessionID: sessionID,
            event: "soundboard",
            message: [
                "user_id":    .string(me.uuidString),
                "sound_slug": .string(slug),
                "ts":         .double(Date().timeIntervalSince1970 * 1000)
            ]
        )

        if let groupID {
            await insertSoundboardEcho(groupID: groupID, authorID: me, slug: slug)
        }
    }

    /// Broadcast a reaction event (no chat echo per spec).
    ///
    /// - Parameters:
    ///   - sessionID: The active session.
    ///   - emoji:     The reaction emoji (e.g. "🔥").
    func sendReaction(sessionID: UUID, emoji: String) async {
        guard rateAllowed() else { return }
        guard let me = await SupabaseService.shared.currentUserID() else { return }

        await broadcastRaw(
            sessionID: sessionID,
            event: "reaction",
            message: [
                "user_id": .string(me.uuidString),
                "emoji":   .string(emoji),
                "ts":      .double(Date().timeIntervalSince1970 * 1000)
            ]
        )
    }

    // MARK: - Private helpers

    /// Returns true and records the timestamp when ≥1s has elapsed since last send.
    private func rateAllowed() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastSentAt) >= 1.0 else { return false }
        lastSentAt = now
        return true
    }

    /// Send a broadcast message.  Uses the subscribed channel when available;
    /// falls back to a disposable channel for send-without-subscribe callers.
    private func broadcastRaw(
        sessionID: UUID,
        event: String,
        message: JSONObject
    ) async {
        let ch: RealtimeChannelV2
        if let active = channel {
            ch = active
        } else {
            let tmp = SupabaseService.shared.client
                .channel("session:\(sessionID.uuidString)")
            await tmp.subscribe()
            ch = tmp
        }
        do {
            try await ch.broadcast(event: event, message: message)
        } catch {
            AppLogger.soundboard.error(
                "broadcast send failed (\(event, privacy: .public)): \(error, privacy: .public)")
        }
    }

    // MARK: - Soundboard echo insert

    /// Insert a soundboard_echo message into the group chat.
    ///
    /// Uses a Codable struct so the payload jsonb column encodes correctly
    /// (matching the ProposalRepository insert pattern).
    private func insertSoundboardEcho(
        groupID: UUID,
        authorID: UUID,
        slug: String
    ) async {
        let displayName = await resolveDisplayName(userID: authorID)

        struct EchoInsert: Encodable {
            let id: UUID
            let groupID: UUID
            let authorID: UUID
            let kind: String
            let body: String
            let payload: [String: AnyJSON]

            enum CodingKeys: String, CodingKey {
                case id
                case groupID   = "group_id"
                case authorID  = "author_id"
                case kind, body, payload
            }
        }

        let insert = EchoInsert(
            id: UUID(),
            groupID: groupID,
            authorID: authorID,
            kind: "soundboard_echo",
            body: "🔊 \(displayName)",
            payload: ["sound_slug": .string(slug)]
        )

        do {
            try await SupabaseService.shared.client
                .from("chat_messages")
                .insert(insert)
                .execute()
        } catch {
            AppLogger.soundboard.error(
                "soundboard_echo insert failed: \(error, privacy: .public)")
        }
    }

    /// Fetch display_name from profiles.  Returns "Someone" on any error.
    private func resolveDisplayName(userID: UUID) async -> String {
        struct ProfileRow: Decodable {
            let displayName: String?
            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }
        do {
            let rows: [ProfileRow] = try await SupabaseService.shared.client
                .from("profiles")
                .select("display_name")
                .eq("id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first?.displayName ?? "Someone"
        } catch {
            return "Someone"
        }
    }
}
