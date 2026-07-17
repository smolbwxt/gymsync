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

    // MARK: - Phase F Task 6: Edit Profile

    /// Full-row-authorized by "users can update their own profile"
    /// (`20260709000001_create_profiles.sql`: `USING/WITH CHECK (auth.uid()
    /// = id)`, no column restriction) — same owner-RLS shape `setAvatar`
    /// below relies on. Always sends the trimmed string, even if empty,
    /// rather than attempting to encode a column-clearing NULL through the
    /// `[String: String]` update dictionary: every existing display-name
    /// reader in this codebase (`YouTabView.displayName(for:)`,
    /// `GroupView`/`FriendsView`/`CreateGroupView`'s `nameBlock`) already
    /// treats an empty string exactly like `nil` (`!displayName.isEmpty`
    /// guards), so a blank field round-trips to the same "show username
    /// instead" behavior without needing an `Encodable` that can carry null.
    static func updateDisplayName(_ displayName: String) async throws -> Profile {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let updated: Profile = try await client
                .from("profiles")
                .update(["display_name": displayName.trimmingCharacters(in: .whitespaces)])
                .eq("id", value: userID.uuidString)
                .select()
                .single()
                .execute()
                .value
            return updated
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Mirrors `GroupRepository.setAvatar`'s upload idiom exactly (same
    /// downscale/compress via `ImageProcessor.jpegForUpload`, same
    /// upload-then-write-URL shape) — the group-avatar flow from Phase 2.5
    /// is the precedent this task's brief names explicitly.
    /// `StorageService.uploadUserAvatar` carries the per-entity path
    /// convention (`users/{uid}.jpg` vs groups' `groups/{group_id}.jpg`);
    /// RLS in 20260720000005_user_avatar_storage.sql.
    ///
    /// Return type deliberately DIVERGES from `GroupRepository.setAvatar`
    /// (`Profile`, not bare `URL`): `Profile` has no memberwise init (only
    /// the custom `init(from decoder:)` — see this file's decode-only
    /// `init`, same trap `CatalogHostView.swift`'s `catalogFixtureUsername`
    /// init documents), so a caller that needs to refresh a shared
    /// `AppState.currentProfile` after an avatar-only change cannot hand-
    /// build an updated `Profile` locally the way `CreateGroupView.create()`
    /// can for `GymGroup` (which DOES have a synthesized memberwise init).
    /// Returning the full re-selected row here sidesteps that trap entirely
    /// — no call site ever needs to construct a `Profile` by hand.
    static func setAvatar(imageData: Data) async throws -> Profile {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        guard let jpeg = ImageProcessor.jpegForUpload(from: imageData, maxDimension: 512) else {
            throw GymSyncError.validation("That image couldn't be processed.")
        }
        let url = try await StorageService.uploadUserAvatar(userID: userID, jpegData: jpeg)
        do {
            let updated: Profile = try await client
                .from("profiles")
                .update(["avatar_url": url.absoluteString])
                .eq("id", value: userID.uuidString)
                .select()
                .single()
                .execute()
                .value
            return updated
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
