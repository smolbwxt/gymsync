import Foundation
import Supabase

// MARK: - Trainer enrollment rails (20260816000001, design:
// docs/superpowers/specs/2026-08-16-trainer-enrollment-design.md)
//
// Entitlements are WRITTEN by the service role only (web portal /
// verify-entitlement fn); the client reads its own and redeems gym seat
// keys through the SECURITY DEFINER RPC. Capacity enforcement stays
// dormant until the trainer paywall flips.

/// A row of `trainer_entitlements` — why this user may carry clients
/// beyond the free taste.
struct TrainerEntitlement: Decodable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let source: String            // individual_sub | gym_seat
    let venueID: UUID?
    let clientCap: Int?
    let activeUntil: Date?
    let createdAt: Date
    let revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case source
        case venueID = "venue_id"
        case clientCap = "client_cap"
        case activeUntil = "active_until"
        case createdAt = "created_at"
        case revokedAt = "revoked_at"
    }

    var isActive: Bool {
        revokedAt == nil && (activeUntil.map { $0 > .now } ?? true)
    }
}

enum TrainerEntitlementRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// The signed-in user's entitlements (own rows by RLS).
    static func mine() async throws -> [TrainerEntitlement] {
        guard let userID = await SupabaseService.shared.currentUserID() else { return [] }
        do {
            let rows: [TrainerEntitlement] = try await client
                .from("trainer_entitlements")
                .select()
                .eq("user_id", value: userID)
                .order("created_at", ascending: false)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    private struct RedeemParams: Encodable {
        let code: String
        enum CodingKeys: String, CodingKey { case code = "p_code" }
    }

    /// Redeem a gym seat key — the RPC validates and mints the
    /// entitlement in one act; its P0001 messages are user-facing copy
    /// and surface verbatim.
    static func redeemGymKey(code: String) async throws {
        do {
            _ = try await client
                .rpc("redeem_gym_seat_key", params: RedeemParams(code: code))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
