import Foundation
import Supabase

/// Catalog row from `soundboard_sounds` (fetched for UI lists — playback
/// caching stays in SoundboardPlayer, which keeps its own minimal decode).
struct SoundboardSound: Codable, Identifiable, Sendable, Equatable {
    let slug: String
    let displayName: String?
    let storagePath: String
    let durationMs: Int?
    let isCurated: Bool
    let icon: String?      // emoji, per designer frames
    let category: String?  // hype | funny | fx

    var id: String { slug }
    var label: String { displayName ?? slug }

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case storagePath = "storage_path"
        case durationMs = "duration_ms"
        case isCurated = "is_curated"
        case icon
        case category
    }
}

enum SoundboardRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    static func fetchCatalog() async throws -> [SoundboardSound] {
        do {
            let rows: [SoundboardSound] = try await client
                .from("soundboard_sounds")
                .select()
                .order("slug")
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }
}

/// One row per user; absent row = no favorites chosen yet (callers fall back
/// to the first four curated catalog sounds). Deliberately NOT part of
/// user_settings — see migration 20260717000003 header.
enum SoundboardFavoritesRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    private struct Row: Codable {
        let userID: UUID
        let slugs: [String]
        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case slugs
        }
    }

    static func get() async throws -> [String] {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [Row] = try await client
                .from("soundboard_favorites")
                .select()
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value
            return rows.first?.slugs ?? []
        } catch { throw ErrorMapping.map(error) }
    }

    static func set(_ slugs: [String]) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("soundboard_favorites")
                .upsert(Row(userID: userID, slugs: slugs))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
