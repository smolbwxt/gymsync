import Foundation
import Supabase

// MARK: - Trainer arm T1 (hubs/trainer design doc)
//
// The relationship + consent foundation. Scopes are CLIENT-granted at
// redemption and client-adjustable after; body weight is its own toggle
// on purpose (sensitive). T2 wires these scopes into scope-gated read
// policies — nothing in T1 exposes any training data yet.

struct TrainerClient: Codable, Identifiable, Sendable {
    let id: UUID
    let trainerID: UUID
    let clientID: UUID?
    var status: String            // invited | active | ended
    var scopes: TrainerScopes
    var inviteCode: String?
    let createdAt: Date
    var respondedAt: Date?
    /// The hidden coaching-chat backing group (20260821000007), set on
    /// first message from either side.
    var chatGroupID: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case trainerID = "trainer_id"
        case clientID = "client_id"
        case status, scopes
        case inviteCode = "invite_code"
        case createdAt = "created_at"
        case respondedAt = "responded_at"
        case chatGroupID = "chat_group_id"
    }
}

/// The consent surface, one Bool per shared thing. Encoded as the row's
/// jsonb — absent key = not granted, so a scope added later defaults to
/// OFF for every existing relationship (consent never expands silently).
struct TrainerScopes: Codable, Sendable, Equatable {
    var history: Bool = false
    var stats: Bool = false
    var bodyWeight: Bool = false
    var calendar: Bool = false

    enum CodingKeys: String, CodingKey {
        case history, stats, calendar
        case bodyWeight = "body_weight"
    }

    init(history: Bool = false, stats: Bool = false,
         bodyWeight: Bool = false, calendar: Bool = false) {
        self.history = history
        self.stats = stats
        self.bodyWeight = bodyWeight
        self.calendar = calendar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        history = try container.decodeIfPresent(Bool.self, forKey: .history) ?? false
        stats = try container.decodeIfPresent(Bool.self, forKey: .stats) ?? false
        bodyWeight = try container.decodeIfPresent(Bool.self, forKey: .bodyWeight) ?? false
        calendar = try container.decodeIfPresent(Bool.self, forKey: .calendar) ?? false
    }
}

enum TrainerClientRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Mint an invite code (the join-code idiom). 6 chars, unambiguous
    /// alphabet; uniqueness is the DB constraint's job — collide (rare)
    /// and the insert fails, caller retries.
    static func createInvite() async throws -> TrainerClient {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        let code = String((0..<6).map { _ in alphabet.randomElement()! })
        do {
            let row: TrainerClient = try await client
                .from("trainer_clients")
                .insert(["trainer_id": me.uuidString, "invite_code": code])
                .select()
                .single()
                .execute()
                .value
            return row
        } catch { throw ErrorMapping.map(error) }
    }

    /// Redeem a code with the CLIENT's scope choices — acceptance and
    /// consent are the same act.
    static func redeem(code: String, scopes: TrainerScopes) async throws {
        struct Params: Encodable {
            let p_code: String
            let p_scopes: TrainerScopes
        }
        do {
            try await client
                .rpc("redeem_trainer_invite", params: Params(p_code: code, p_scopes: scopes))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Every relationship visible to me — both sides; callers split by
    /// comparing trainerID/clientID against their own id.
    static func mine() async throws -> [TrainerClient] {
        do {
            let rows: [TrainerClient] = try await client
                .from("trainer_clients")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// Client adjusts scopes on an active relationship.
    static func updateScopes(id: UUID, scopes: TrainerScopes) async throws {
        do {
            try await client
                .from("trainer_clients")
                .update(["scopes": scopes])
                .eq("id", value: id)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Either side ends it — the row stays (an ended relationship never
    /// silently vanishes from the other side's history).
    static func end(id: UUID) async throws {
        do {
            try await client
                .from("trainer_clients")
                .update(["status": "ended"])
                .eq("id", value: id)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Trainer revokes an unredeemed invite.
    static func revokeInvite(id: UUID) async throws {
        do {
            try await client
                .from("trainer_clients")
                .delete()
                .eq("id", value: id)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
