import Foundation
import Supabase

struct Profile: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let username: String
    let displayName: String?
    let avatarURL: URL?
    let createdAt: Date
    let lifetimeVolumeLifted: Decimal
    let isCurator: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case lifetimeVolumeLifted = "lifetime_volume_lifted"
        case isCurator = "is_curator"
    }

    // Custom decode so any pre-migration cached JSON (no is_curator key yet)
    // still decodes safely, defaulting to false. No callers construct
    // `Profile(...)` directly (verified via grep before this change), so the
    // synthesized memberwise init is not needed elsewhere.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatarURL = try c.decodeIfPresent(URL.self, forKey: .avatarURL)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lifetimeVolumeLifted = try c.decode(Decimal.self, forKey: .lifetimeVolumeLifted)
        isCurator = try c.decodeIfPresent(Bool.self, forKey: .isCurator) ?? false
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

    static func fetchByUsername(_ username: String) async throws -> Profile? {
        do {
            let row: Profile = try await SupabaseService.shared.client
                .from("profiles")
                .select()
                .ilike("username", pattern: username
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_"))
                .single()
                .execute()
                .value
            return row
        } catch let error as PostgrestError where error.code == "PGRST116" {
            return nil
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func fetchMany(ids: [UUID]) async throws -> [Profile] {
        guard !ids.isEmpty else { return [] }
        do {
            let rows: [Profile] = try await SupabaseService.shared.client
                .from("profiles")
                .select()
                .in("id", values: ids.map(\.uuidString))
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
