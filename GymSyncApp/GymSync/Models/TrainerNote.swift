import Foundation
import Supabase

/// Trainer arm T5: the trainer's private notebook per client — RLS makes
/// it trainer-only (the client NEVER sees these), and notes survive an
/// ended relationship (your notebook doesn't vanish when a client leaves).
struct TrainerNote: Codable, Identifiable, Sendable {
    let id: UUID
    let trainerID: UUID
    let clientID: UUID
    var body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case trainerID = "trainer_id"
        case clientID = "client_id"
        case body
        case createdAt = "created_at"
    }
}

enum TrainerNoteRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    static func notes(clientID: UUID) async throws -> [TrainerNote] {
        do {
            let rows: [TrainerNote] = try await client
                .from("trainer_notes")
                .select()
                .eq("client_id", value: clientID)
                .order("created_at", ascending: false)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    static func add(clientID: UUID, body: String) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("trainer_notes")
                .insert(["trainer_id": me.uuidString,
                         "client_id": clientID.uuidString,
                         "body": body])
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    static func delete(id: UUID) async throws {
        do {
            try await client
                .from("trainer_notes")
                .delete()
                .eq("id", value: id)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
