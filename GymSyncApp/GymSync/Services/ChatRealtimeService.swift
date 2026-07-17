import Foundation
import Supabase

@MainActor
final class ChatRealtimeService {
    private var channel: RealtimeChannelV2?
    private var streamTask: Task<Void, Never>?
    private var reactionTask: Task<Void, Never>?

    private var typingChannel: RealtimeChannelV2?
    private var typingTask: Task<Void, Never>?
    private var typingUsername: String?
    private var isTracked = false

    // Postgrest timestamps: "2026-07-10T19:00:00.123456+00:00" (fractional) or without.
    nonisolated static let postgresDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { dec in
            let value = try dec.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: value) ?? plain.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: dec.codingPath,
                debugDescription: "unparseable timestamp: \(value)"))
        }
        return decoder
    }()

    func subscribe(groupID: UUID,
                   onInsert: @escaping @MainActor (ChatMessage) -> Void,
                   onReaction: (@MainActor () -> Void)? = nil) async {
        await unsubscribe()
        let channel = SupabaseService.shared.client
            .channel("chat:\(groupID.uuidString)")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_messages",
            filter: "group_id=eq.\(groupID.uuidString)"
        )
        // Reactions have no group_id column; RLS (WALRUS) already limits INSERT
        // events to messages the subscriber can read, and the callback only
        // refreshes the currently open chat.
        let reactionInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_message_reactions"
        )
        self.channel = channel
        await channel.subscribe()
        streamTask = Task {
            for await action in inserts {
                do {
                    let message = try action.decodeRecord(
                        decoder: Self.postgresDecoder) as ChatMessage
                    onInsert(message)
                } catch {
                    AppLogger.chat.error("realtime decode failed: \(error, privacy: .public)")
                }
            }
        }
        if let onReaction {
            reactionTask = Task {
                for await _ in reactionInserts {
                    onReaction()
                }
            }
        }
    }

    /// Session sub-thread variant of `subscribe(groupID:onInsert:onReaction:)`
    /// above — same body, filtered on `session_id` instead of `group_id`
    /// (kept as a separate method rather than an optional param so the
    /// group-level codepath is untouched; see task-3-report.md). Channel
    /// name is prefixed `chat:session:` (distinct from the group channel's
    /// `chat:<uuid>`/`chat:<uuid>:typing` namespace) purely for log/debug
    /// clarity — group and session ids are different UUID spaces so there's
    /// no actual collision risk either way.
    ///
    /// Reaction inserts are subscribed unchanged (same `onReaction` signal,
    /// no filter): `chat_message_reactions` has no session_id/group_id
    /// column of its own, and RLS (WALRUS) already scopes delivered events
    /// to rows the subscriber can access via `can_access_message()`
    /// (20260719000011_chat_subthread_lock_hardening.sql #1) — this already
    /// covers the sub-thread case.
    ///
    /// No typing/presence subscription here — sub-thread typing indicators
    /// are out of v1 scope (task-3-brief.md only asks for sends/reads/
    /// realtime message delivery). `ChatView.send()`'s `realtime.setTyping()`
    /// calls remain safe no-ops when this method is used instead of
    /// `subscribeTyping` — `setTyping` already guards on `typingChannel`
    /// being non-nil.
    func subscribe(sessionID: UUID,
                   onInsert: @escaping @MainActor (ChatMessage) -> Void,
                   onReaction: (@MainActor () -> Void)? = nil) async {
        await unsubscribe()
        let channel = SupabaseService.shared.client
            .channel("chat:session:\(sessionID.uuidString)")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_messages",
            filter: "session_id=eq.\(sessionID.uuidString)"
        )
        let reactionInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_message_reactions"
        )
        self.channel = channel
        await channel.subscribe()
        streamTask = Task {
            for await action in inserts {
                do {
                    let message = try action.decodeRecord(
                        decoder: Self.postgresDecoder) as ChatMessage
                    onInsert(message)
                } catch {
                    AppLogger.chat.error("realtime decode failed: \(error, privacy: .public)")
                }
            }
        }
        if let onReaction {
            reactionTask = Task {
                for await _ in reactionInserts {
                    onReaction()
                }
            }
        }
    }

    // SDK drift note: supabase-swift 2.51 has no presenceState() method.
    // presenceChange() yields PresenceAction with .joins/.leaves diffs keyed by presence key.
    // We maintain a local [key: username] map and recompute the set on every diff.
    // track(state:) takes a labeled `state:` parameter of type JSONObject ([String: AnyJSON]).
    func subscribeTyping(groupID: UUID, selfUsername: String,
                         onChange: @escaping @MainActor (Set<String>) -> Void) async {
        let channel = SupabaseService.shared.client
            .channel("chat:\(groupID.uuidString):typing")
        let presence = channel.presenceChange()
        typingChannel = channel
        typingUsername = selfUsername
        await channel.subscribe()
        typingTask = Task {
            // Local map from presence key → username; mutated on each diff.
            var tracked: [String: String] = [:]
            for await action in presence {
                for (key, pv) in action.joins {
                    if let name = pv.state["username"]?.stringValue {
                        tracked[key] = name
                    }
                }
                for key in action.leaves.keys {
                    tracked.removeValue(forKey: key)
                }
                let names = Set(tracked.values).subtracting([selfUsername])
                onChange(names)
            }
        }
    }

    func setTyping(_ typing: Bool) async {
        guard let typingChannel, let typingUsername else { return }
        if typing && !isTracked {
            await typingChannel.track(state: ["username": .string(typingUsername)])
            isTracked = true
        } else if !typing && isTracked {
            await typingChannel.untrack()
            isTracked = false
        }
    }

    func unsubscribe() async {
        streamTask?.cancel()
        streamTask = nil
        reactionTask?.cancel()
        reactionTask = nil
        typingTask?.cancel()
        typingTask = nil
        if let typingChannel {
            await SupabaseService.shared.client.removeChannel(typingChannel)
        }
        typingChannel = nil
        isTracked = false
        if let channel {
            await SupabaseService.shared.client.removeChannel(channel)
        }
        channel = nil
    }
}
