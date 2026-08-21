import Foundation
import Supabase

// MARK: - SetLogClip
//
// Form video v1 (owner rulings 2026-08-21): one row per clip attached to
// a logged set. RETENTION IS GATED client-side before any upload happens
// (PRO or coach-linked; see WorkoutSessionView.canRetainClips) and
// server-side by the form-clips bucket RLS; the active trainer reads
// through the same trainer_clients relationship that gates every other
// client surface.

struct SetLogClip: Codable, Identifiable, Sendable {
    let id: UUID
    let setLogID: UUID
    let userID: UUID
    let storagePath: String
    let durationSeconds: Double?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case setLogID = "set_log_id"
        case userID = "user_id"
        case storagePath = "storage_path"
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
    }
}

enum SetLogClipRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    private struct InsertRow: Encodable {
        let id: String
        let setLogID: String
        let userID: String
        let storagePath: String
        let durationSeconds: Double?
        enum CodingKeys: String, CodingKey {
            case id
            case setLogID = "set_log_id"
            case userID = "user_id"
            case storagePath = "storage_path"
            case durationSeconds = "duration_seconds"
        }
    }

    /// Uploads the clip data and records the row - one call so a failed
    /// upload never leaves a dangling row (row insert happens second).
    static func attach(clipID: UUID, setLogID: UUID, userID: UUID,
                       data: Data, durationSeconds: Double?) async throws -> SetLogClip {
        let path = try await StorageService.uploadFormClip(
            userID: userID, clipID: clipID, data: data)
        do {
            return try await client
                .from("set_log_clips")
                .insert(InsertRow(id: clipID.uuidString,
                                  setLogID: setLogID.uuidString,
                                  userID: userID.uuidString,
                                  storagePath: path,
                                  durationSeconds: durationSeconds))
                .select()
                .single()
                .execute()
                .value
        } catch { throw ErrorMapping.map(error) }
    }

    /// Clips for a batch of set IDs - the completed-session surface's one
    /// fetch (athlete reads their own; the active trainer reads through
    /// the RLS relationship, no separate code path).
    static func forSets(_ setLogIDs: [UUID]) async throws -> [SetLogClip] {
        guard !setLogIDs.isEmpty else { return [] }
        do {
            return try await client
                .from("set_log_clips")
                .select()
                .in("set_log_id", values: setLogIDs.map(\.uuidString))
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch { throw ErrorMapping.map(error) }
    }

    /// Whether the signed-in athlete has an ACTIVE coach - one half of
    /// the retention gate (the other is Entitlements.hasPro).
    static func hasActiveCoach() async -> Bool {
        guard let me = await SupabaseService.shared.currentUserID() else { return false }
        struct Row: Decodable { let id: UUID }
        let rows: [Row]? = try? await client
            .from("trainer_clients")
            .select("id")
            .eq("client_id", value: me.uuidString)
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value
        return !(rows ?? []).isEmpty
    }
}
