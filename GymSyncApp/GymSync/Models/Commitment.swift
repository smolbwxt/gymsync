import Foundation
import Supabase

// MARK: - SessionCommitment (20260811000001)
//
// A member's signal for an upcoming group session — 'in' or 'out'; the
// absence of a row means they haven't said. Ternary by design (owner
// decision 2026-08-11): an explicit OUT is social information ("can't make
// Friday" invites rescheduling) that a binary flag can't carry.
struct SessionCommitment: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case committed = "in"
        case out = "out"
    }

    let sessionID: UUID
    let userID: UUID
    let status: Status

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case userID = "user_id"
        case status
    }
}

enum CommitmentRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    static func commitments(sessionID: UUID) async throws -> [SessionCommitment] {
        do {
            let rows: [SessionCommitment] = try await client
                .from("session_commitments")
                .select("session_id, user_id, status")
                .eq("session_id", value: sessionID.uuidString)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Upsert my commitment for the session (PK is (session_id, user_id) —
    /// changing your answer overwrites the row).
    static func setMine(sessionID: UUID, status: SessionCommitment.Status) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        struct Upsert: Encodable {
            let session_id: String
            let user_id: String
            let status: String
            let updated_at: String
        }
        do {
            try await client
                .from("session_commitments")
                .upsert(Upsert(
                    session_id: sessionID.uuidString,
                    user_id: userID.uuidString,
                    status: status.rawValue,
                    updated_at: ISO8601DateFormatter().string(from: .now)
                ))
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Back to "hasn't said".
    static func clearMine(sessionID: UUID) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("session_commitments")
                .delete()
                .eq("session_id", value: sessionID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}

// MARK: - GroupCampaign (20260811000002)
//
// The crew room's campaign meter spine: a named multi-week push. WK n OF m
// derives from started_on + weeks; "active" = today inside that window.
// Trainer-lite campaign content layers on later.
struct GroupCampaign: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let groupID: UUID
    let name: String
    let weeks: Int
    let startedOn: Date
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case name
        case weeks
        case startedOn = "started_on"
        case createdBy = "created_by"
    }

    // `started_on` is a Postgres `date` — arrives as "yyyy-MM-dd", which the
    // client's timestamptz-tuned Date decoding doesn't cover. Parse it
    // explicitly (UTC midnight; week math only needs day precision).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        groupID = try c.decode(UUID.self, forKey: .groupID)
        name = try c.decode(String.self, forKey: .name)
        weeks = try c.decode(Int.self, forKey: .weeks)
        createdBy = try c.decode(UUID.self, forKey: .createdBy)
        let raw = try c.decode(String.self, forKey: .startedOn)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let parsed = formatter.date(from: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .startedOn, in: c,
                debugDescription: "unparseable date: \(raw)")
        }
        startedOn = parsed
    }

    /// 1-based week number, clamped into 1...weeks.
    var currentWeek: Int {
        let days = Calendar.current.dateComponents([.day], from: startedOn, to: .now).day ?? 0
        return min(max(days / 7 + 1, 1), weeks)
    }

    var isActive: Bool {
        guard let end = Calendar.current.date(byAdding: .day, value: weeks * 7, to: startedOn) else {
            return false
        }
        return Date.now < end
    }
}

enum CampaignRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// The group's most recent campaign whose window covers today, if any.
    static func active(groupID: UUID) async throws -> GroupCampaign? {
        do {
            let rows: [GroupCampaign] = try await client
                .from("group_campaigns")
                .select("id, group_id, name, weeks, started_on, created_by")
                .eq("group_id", value: groupID.uuidString)
                .order("started_on", ascending: false)
                .limit(3)
                .execute()
                .value
            return rows.first(where: \.isActive)
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func create(groupID: UUID, name: String, weeks: Int) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        struct Insert: Encodable {
            let group_id: String
            let name: String
            let weeks: Int
            let created_by: String
        }
        do {
            try await client
                .from("group_campaigns")
                .insert(Insert(
                    group_id: groupID.uuidString,
                    name: name.trimmingCharacters(in: .whitespaces),
                    weeks: min(max(weeks, 1), 52),
                    created_by: userID.uuidString
                ))
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
