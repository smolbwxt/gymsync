import Foundation
import Supabase

// Named GymGroup because `Group` collides with SwiftUI.Group.
struct GymGroup: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let avatarURL: URL?
    let createdBy: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case avatarURL = "avatar_url"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct GroupMember: Codable, Sendable, Equatable {
    let groupID: UUID
    let userID: UUID
    let role: Role
    let joinedAt: Date

    enum Role: String, Codable, Sendable { case admin, member }

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case role
        case joinedAt = "joined_at"
    }
}

enum GroupRepository {
    static func create(name: String) async throws -> GymGroup {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        let groupID = UUID()
        do {
            let group: GymGroup = try await SupabaseService.shared.client
                .from("groups")
                .insert(["id": groupID.uuidString,
                         "name": name,
                         "created_by": me.uuidString])
                .select()
                .single()
                .execute()
                .value
            try await SupabaseService.shared.client
                .from("group_members")
                .insert(["group_id": groupID.uuidString,
                         "user_id": me.uuidString,
                         "role": "admin"])
                .execute()
            return group
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func myGroups() async throws -> [GymGroup] {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let memberships: [GroupMember] = try await SupabaseService.shared.client
                .from("group_members")
                .select()
                .eq("user_id", value: me.uuidString)
                .execute()
                .value
            guard !memberships.isEmpty else { return [] }
            let groups: [GymGroup] = try await SupabaseService.shared.client
                .from("groups")
                .select()
                .in("id", values: memberships.map(\.groupID.uuidString))
                .order("created_at", ascending: false)
                .execute()
                .value
            return groups
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Bulk group lookup by ID — backs Exercise History's "· {group name}"
    /// meta suffix for sets logged in a group session.
    static func fetchMany(ids: [UUID]) async throws -> [GymGroup] {
        guard !ids.isEmpty else { return [] }
        do {
            let rows: [GymGroup] = try await SupabaseService.shared.client
                .from("groups")
                .select()
                .in("id", values: ids.map(\.uuidString))
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func members(groupID: UUID) async throws -> [(member: GroupMember, profile: Profile)] {
        do {
            let rows: [GroupMember] = try await SupabaseService.shared.client
                .from("group_members")
                .select()
                .eq("group_id", value: groupID.uuidString)
                .execute()
                .value
            let profiles = try await ProfileRepository.fetchMany(ids: rows.map(\.userID))
            let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            return rows.compactMap { row in
                byID[row.userID].map { (member: row, profile: $0) }
            }
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func addMember(groupID: UUID, username: String) async throws {
        guard let target = try await ProfileRepository.fetchByUsername(username) else {
            throw GymSyncError.notFound
        }
        do {
            try await SupabaseService.shared.client
                .from("group_members")
                .insert(["group_id": groupID.uuidString,
                         "user_id": target.id.uuidString,
                         "role": "member"])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func leave(groupID: UUID) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("group_members")
                .delete()
                .eq("group_id", value: groupID.uuidString)
                .eq("user_id", value: me.uuidString)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func deleteGroup(groupID: UUID) async throws {
        do {
            try await SupabaseService.shared.client
                .from("groups")
                .delete()
                .eq("id", value: groupID.uuidString)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func setAvatar(groupID: UUID, imageData: Data) async throws -> URL {
        guard let jpeg = ImageProcessor.jpegForUpload(from: imageData, maxDimension: 512) else {
            throw GymSyncError.validation("That image couldn't be processed.")
        }
        let url = try await StorageService.uploadGroupAvatar(groupID: groupID, jpegData: jpeg)
        do {
            try await SupabaseService.shared.client
                .from("groups")
                .update(["avatar_url": url.absoluteString])
                .eq("id", value: groupID.uuidString)
                .execute()
            return url
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
