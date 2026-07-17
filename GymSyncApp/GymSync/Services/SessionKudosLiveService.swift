import Foundation
import Supabase

/// Live updates for the frame-8 recap's kudos leaderboard chips.
///
/// Single-stream INSERT subscription — mirrors `FriendRealtimeService`'s
/// shape (one channel, one `postgresChange` stream, one consuming task)
/// rather than `SessionLiveService`'s multi-stream `withTaskGroup`:
/// `session_kudos` has no UPDATE/DELETE to watch for (backend migration
/// 20260720000001_session_kudos.sql ships no UPDATE/DELETE policy — v1 is
/// append-only), so there is exactly one event kind to stream.
///
/// Reuses `SessionLiveService.postgresDecoder` (declared `nonisolated
/// static let`, not `private`) rather than duplicating the fractional/plain
/// ISO-8601 fallback decoder a third time in this module.
@MainActor
final class SessionKudosLiveService {
    private var channel: RealtimeChannelV2?
    private var streamTask: Task<Void, Never>?

    /// - Parameters:
    ///   - sessionID: Session whose kudos to watch.
    ///   - onKudos: Called with each decoded `SessionKudo` INSERT — the
    ///     caller increments its local per-recipient count.
    func subscribe(
        sessionID: UUID,
        onKudos: @escaping @MainActor (SessionKudo) -> Void
    ) async {
        await unsubscribe()

        let ch = SupabaseService.shared.client
            .channel("session:\(sessionID.uuidString):kudos")

        let inserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "session_kudos",
            filter: "session_id=eq.\(sessionID.uuidString)"
        )

        channel = ch
        await ch.subscribe()

        streamTask = Task { @MainActor in
            for await action in inserts {
                do {
                    let kudo = try action.decodeRecord(
                        decoder: SessionLiveService.postgresDecoder) as SessionKudo
                    onKudos(kudo)
                } catch {
                    AppLogger.sessions.error(
                        "kudos live decode failed: \(error, privacy: .public)")
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
