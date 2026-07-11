import Foundation
import Supabase

struct Friendship: Codable, Sendable, Equatable {
    let userID: UUID      // requester
    let friendID: UUID    // recipient
    let status: Status
    let createdAt: Date

    enum Status: String, Codable, Sendable {
        case pending, accepted, blocked
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case friendID = "friend_id"
        case status
        case createdAt = "created_at"
    }
}

enum FriendRepository {
    static func sendRequest(toUsername username: String) async throws {
        guard let target = try await ProfileRepository.fetchByUsername(username) else {
            throw GymSyncError.notFound
        }
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("friendships")
                .insert(["user_id": me.uuidString,
                         "friend_id": target.id.uuidString,
                         "status": "pending"])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func incomingRequests() async throws -> [Profile] {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [Friendship] = try await SupabaseService.shared.client
                .from("friendships")
                .select()
                .eq("friend_id", value: me.uuidString)
                .eq("status", value: "pending")
                .execute()
                .value
            return try await ProfileRepository.fetchMany(ids: rows.map(\.userID))
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func outgoingRequests() async throws -> [Profile] {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [Friendship] = try await SupabaseService.shared.client
                .from("friendships")
                .select()
                .eq("user_id", value: me.uuidString)
                .eq("status", value: "pending")
                .execute()
                .value
            return try await ProfileRepository.fetchMany(ids: rows.map(\.friendID))
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func accept(requesterID: UUID) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("friendships")
                .update(["status": "accepted"])
                .eq("user_id", value: requesterID.uuidString)
                .eq("friend_id", value: me.uuidString)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func removeFriendship(with otherID: UUID) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("friendships")
                .delete()
                .or("and(user_id.eq.\(me.uuidString),friend_id.eq.\(otherID.uuidString)),and(user_id.eq.\(otherID.uuidString),friend_id.eq.\(me.uuidString))")
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func friends() async throws -> [Profile] {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [Friendship] = try await SupabaseService.shared.client
                .from("friendships")
                .select()
                .eq("status", value: "accepted")
                .or("user_id.eq.\(me.uuidString),friend_id.eq.\(me.uuidString)")
                .execute()
                .value
            let ids = rows.map { $0.userID == me ? $0.friendID : $0.userID }
            return try await ProfileRepository.fetchMany(ids: ids)
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
