import Foundation
import Supabase

// MARK: - SessionCoachThread
//
// Plan task S6, spec §3.6, owner decision 19. One value, one repository call,
// one gate.

/// This session's Coach thread — one room for the whole crew (spec §3.6,
/// owner decision 19).
struct SessionCoachThread: Equatable, Sendable {
    let threadID: UUID
    /// Server-evaluated: at least one participant of this session is Pro
    /// (private.session_has_pro, 20260912000102). Never computed on the
    /// client — profiles.pro_until is not readable across users, so a
    /// client-side answer would be "no" for everybody but me.
    let unlocked: Bool
}

enum SessionCoachThreadRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// The RPC's wire shape. `coach_chat_threads.session_id` is the key the
    /// unique index is on (20260912000102); the row comes back with the
    /// thread's id and the server's verdict on Pro.
    private struct Row: Decodable {
        let threadID: UUID
        let unlocked: Bool

        enum CodingKeys: String, CodingKey {
            case threadID = "thread_id"
            case unlocked
        }
    }

    /// Find-or-create, through `public.session_coach_thread(uuid)`. Two
    /// lifters tapping at once land in ONE room; the unique index resolves
    /// the race server-side.
    ///
    /// A SECURITY DEFINER RPC rather than a client insert, for the reason the
    /// value's `unlocked` records: the Pro verdict needs to read every
    /// participant's `profiles.pro_until`, and RLS does not let one member
    /// read another's.
    static func open(sessionID: UUID) async throws -> SessionCoachThread {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            let row: Row = try await client
                .rpc("session_coach_thread",
                     params: ["p_session_id": sessionID.uuidString])
                .single()
                .execute().value
            return SessionCoachThread(threadID: row.threadID, unlocked: row.unlocked)
        } catch { throw ErrorMapping.map(error) }
    }

    /// `guard Monetization.paywallEnabled else { return true }` first — the
    /// house convention (CrewCoachEngine.swift:22-25). The server's answer is
    /// authoritative only once the paywall is on.
    ///
    /// While the paywall is dormant — which it is today
    /// (`Monetization.swift:25`) — the room is open to everyone regardless of
    /// what the server said, because every other gate in the app behaves that
    /// way and a Coach door that became the app's only live paywall would be a
    /// product change this plan is not entitled to make.
    static func isReachable(_ thread: SessionCoachThread) -> Bool {
        guard Monetization.paywallEnabled else { return true }
        return thread.unlocked
    }

    /// The line under Coach's door when the crew cannot reach the room.
    /// Nil when they can, so `CoachDoorRow` renders no note — an explanation
    /// of a restriction that is not in force is furniture.
    static func lockedNote(_ thread: SessionCoachThread) -> String? {
        isReachable(thread) ? nil : "Nobody in the crew has Pro yet — see plans"
    }
}
