import Foundation
import Supabase

@MainActor
final class ChatRealtimeService {
    private var channel: RealtimeChannelV2?
    private var streamTask: Task<Void, Never>?

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
                   onInsert: @escaping @MainActor (ChatMessage) -> Void) async {
        await unsubscribe()
        let channel = SupabaseService.shared.client
            .channel("chat:\(groupID.uuidString)")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_messages",
            filter: "group_id=eq.\(groupID.uuidString)"
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
    }

    func unsubscribe() async {
        streamTask?.cancel()
        streamTask = nil
        if let channel {
            await SupabaseService.shared.client.removeChannel(channel)
        }
        channel = nil
    }
}
