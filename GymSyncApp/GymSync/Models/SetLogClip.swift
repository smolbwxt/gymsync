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
    /// Storage v1.5 flat windows: 90 days PRO, 30 days coach-linked -
    /// stamped at insert; the hourly sweeper enforces it. Paid
    /// extensions later just move this date.
    let retainUntil: Date?
    let byteSize: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case setLogID = "set_log_id"
        case userID = "user_id"
        case storagePath = "storage_path"
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
        case retainUntil = "retain_until"
        case byteSize = "byte_size"
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
        let retainUntil: Date
        let byteSize: Int
        enum CodingKeys: String, CodingKey {
            case id
            case setLogID = "set_log_id"
            case userID = "user_id"
            case storagePath = "storage_path"
            case durationSeconds = "duration_seconds"
            case retainUntil = "retain_until"
            case byteSize = "byte_size"
        }
    }

    /// Uploads the clip data and records the row - one call so a failed
    /// upload never leaves a dangling row (row insert happens second).
    static func attach(clipID: UUID, setLogID: UUID, userID: UUID,
                       data: Data, durationSeconds: Double?) async throws -> SetLogClip {
        let path = try await StorageService.uploadFormClip(
            userID: userID, clipID: clipID, data: data)
        // Flat retention windows (storage v1.5): PRO keeps 90 days,
        // coach-linked 30. The caller already passed the retention gate
        // (PRO or coached) before any upload happened.
        let retainDays = Entitlements.hasPro ? 90 : 30
        let retainUntil = Date().addingTimeInterval(TimeInterval(retainDays) * 86_400)
        do {
            return try await client
                .from("set_log_clips")
                .insert(InsertRow(id: clipID.uuidString,
                                  setLogID: setLogID.uuidString,
                                  userID: userID.uuidString,
                                  storagePath: path,
                                  durationSeconds: durationSeconds,
                                  retainUntil: retainUntil,
                                  byteSize: data.count))
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

    /// The athlete's own clip footprint - the Settings usage meter's
    /// one fetch.
    static func usage() async -> (count: Int, bytes: Int64) {
        struct Row: Decodable {
            let byteSize: Int64?
            enum CodingKeys: String, CodingKey { case byteSize = "byte_size" }
        }
        guard let me = await SupabaseService.shared.currentUserID() else { return (0, 0) }
        let rows: [Row]? = try? await client
            .from("set_log_clips")
            .select("byte_size")
            .eq("user_id", value: me.uuidString)
            .execute()
            .value
        let all = rows ?? []
        return (all.count, all.reduce(0) { $0 + ($1.byteSize ?? 0) })
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
