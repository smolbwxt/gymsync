import Foundation
import Supabase

struct Profile: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let username: String
    let displayName: String?
    let avatarURL: URL?
    let createdAt: Date
    let lifetimeVolumeLifted: Decimal

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case lifetimeVolumeLifted = "lifetime_volume_lifted"
    }
}

enum ProfileRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    static func fetch(userID: UUID) async throws -> Profile? {
        do {
            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            return profile
        } catch let error as PostgrestError where error.code == "PGRST116" {
            return nil  // not found
        } catch {
            AppLogger.db.error("fetch profile failed: \(error.localizedDescription, privacy: .public)")
            throw ErrorMapping.map(error)
        }
    }

    static func create(username: String) async throws -> Profile {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= AppConfig.usernameMinLength,
              trimmed.count <= AppConfig.usernameMaxLength else {
            throw GymSyncError.validation(
                "Username must be \(AppConfig.usernameMinLength)–\(AppConfig.usernameMaxLength) characters."
            )
        }
        let inserted: Profile = try await client
            .from("profiles")
            .insert(["id": userID.uuidString, "username": trimmed])
            .select()
            .single()
            .execute()
            .value
        return inserted
    }

    static func refresh(userID: UUID) async throws -> Profile? {
        try await fetch(userID: userID)
    }

    static func usernameAvailable(_ username: String) async throws -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
        let existing: [Profile] = try await client
            .from("profiles")
            .select()
            .ilike("username", pattern: trimmed)
            .limit(1)
            .execute()
            .value
        return existing.isEmpty
    }
}
