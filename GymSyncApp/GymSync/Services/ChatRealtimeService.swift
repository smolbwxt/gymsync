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

    func subscribeTyping(groupID: UUID, selfUsername: String,
                         onChange: @escaping @MainActor (Set<String>) -> Void) async {
        let channel = SupabaseService.shared.client
            .channel("chat:\(groupID.uuidString):typing")
        let presence = channel.presenceChange()
        typingChannel = channel
        typingUsername = selfUsername
        await channel.subscribe()
        typingTask = Task {
            for await _ in presence {
                let states = await channel.presenceState()
                var names: Set<String> = []
                for entry in states {
                    for presenceItem in entry.presences {
                        if let name = presenceItem.state["username"]?.stringValue,
                           name != selfUsername {
                            names.insert(name)
                        }
                    }
                }
                onChange(names)
            }
        }
    }

    func setTyping(_ typing: Bool) async {
        guard let typingChannel, let typingUsername else { return }
        if typing && !isTracked {
            try? await typingChannel.track(["username": .string(typingUsername)])
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
