import Foundation
import Supabase

@MainActor
final class FriendRealtimeService {
    private var channel: RealtimeChannelV2?
    private var streamTask: Task<Void, Never>?

    func subscribe(userID: UUID,
                   onFriendshipEvent: @escaping @MainActor () -> Void) async {
        await unsubscribe()
        let channel = SupabaseService.shared.client
            .channel("user:\(userID.uuidString)")
        // Incoming requests target me as friend_id; acceptances of MY outgoing
        // requests arrive as UPDATEs where I'm user_id. RLS already scopes both.
        let incoming = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "friendships",
            filter: "friend_id=eq.\(userID.uuidString)"
        )
        let accepted = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "friendships",
            filter: "user_id=eq.\(userID.uuidString)"
        )
        self.channel = channel
        await channel.subscribe()
        streamTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    for await _ in incoming { onFriendshipEvent() }
                }
                group.addTask { @MainActor in
                    for await _ in accepted { onFriendshipEvent() }
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
