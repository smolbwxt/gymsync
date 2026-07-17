import Foundation
import Supabase

// MARK: - SessionKudo
//
// One `session_kudos` row (Phase F Task 4 — backend:
// 20260720000001_session_kudos.sql; frame 8 recap). Emoji set is
// server-enforced there via CHECK (💪 🔥 👏 🏆 ⚡) — `GroupRecapView.
// kudosEmoji` is the single client-side source for which 5 icons the send
// row offers; nothing here re-validates the set.
//
// Plain field declarations only (no custom `init(from decoder:)`), so the
// compiler synthesizes the normal memberwise init — unlike `Profile`/
// `ChatMessage` (whose custom decoders suppress it, per CatalogHostView.
// swift's documented "memberwise-init trap"), a `SessionKudo` fixture value
// can be constructed directly wherever one is needed.
struct SessionKudo: Codable, Identifiable, Sendable {
    let id: UUID
    let sessionID: UUID
    let senderID: UUID
    let recipientID: UUID
    let emoji: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case emoji
        case createdAt = "created_at"
    }
}

enum SessionKudosRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// All kudos rows for a session, aggregated to a received-count per
    /// recipient — backs the recap leaderboard's chip. RLS (session
    /// participants only) already scopes what comes back.
    static func counts(sessionID: UUID) async throws -> [UUID: Int] {
        do {
            let rows: [SessionKudo] = try await client
                .from("session_kudos")
                .select()
                .eq("session_id", value: sessionID)
                .execute()
                .value
            return rows.reduce(into: [UUID: Int]()) { acc, row in
                acc[row.recipientID, default: 0] += 1
            }
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Crew-wide send (see GroupRecapView's kudos-send-model decision): one
    /// row per recipient for a single emoji tap. Sequential inserts, not a
    /// bulk array insert — no precedent for a multi-row `.insert()` call
    /// exists anywhere in this codebase (every repository inserts one
    /// dictionary/Encodable row at a time: `RoutineProposal.vote`,
    /// `GroupRepository.create`, `PersonalRecordRepository.record`, …), so
    /// this mirrors that rather than risking an unverified SDK code path.
    ///
    /// Best-effort per recipient (fire-and-forget, matches `tapReaction`/
    /// `tapSound`'s discipline in GroupSessionLiveView): one rejected row
    /// (e.g. a participant who somehow no longer satisfies the RLS
    /// recipient check) must not block the rest of the crew from getting
    /// theirs, and a failure here must never surface an error to the user
    /// tapping an emoji.
    ///
    /// Defensively drops `senderID` from `recipients` even though callers
    /// are expected to pass "every OTHER participant" already — the
    /// crew-wide model is "kudos to your crew", never a self-kudos row, and
    /// there's no server-side CHECK for that (documented in the migration).
    static func send(sessionID: UUID, recipients: [UUID], emoji: String) async {
        guard let senderID = await SupabaseService.shared.currentUserID() else { return }
        for recipientID in recipients where recipientID != senderID {
            do {
                try await client
                    .from("session_kudos")
                    .insert([
                        "session_id": sessionID.uuidString,
                        "sender_id": senderID.uuidString,
                        "recipient_id": recipientID.uuidString,
                        "emoji": emoji
                    ])
                    .execute()
            } catch {
                AppLogger.sessions.error(
                    "kudos send to \(recipientID.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
