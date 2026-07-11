import Foundation
import Supabase

struct ChatMessage: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let groupID: UUID
    let sessionID: UUID?
    let authorID: UUID?      // nil = system message
    let kind: Kind
    let body: String?
    let replyToID: UUID?
    let createdAt: Date
    let editedAt: Date?
    let deletedAt: Date?

    enum Kind: String, Codable, Sendable {
        case text, image
        case systemPR = "system_pr"
        case systemSession = "system_session"
        case systemLate = "system_late"
        case systemLeaderboard = "system_leaderboard"
        case soundboardEcho = "soundboard_echo"
    }

    var isSystem: Bool { authorID == nil }

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case sessionID = "session_id"
        case authorID = "author_id"
        case kind, body
        case replyToID = "reply_to_id"
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case deletedAt = "deleted_at"
    }
}

struct ChatReaction: Codable, Sendable, Equatable {
    let messageID: UUID
    let userID: UUID
    let emoji: String

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case userID = "user_id"
        case emoji
    }
}

enum ChatRepository {
    static func messages(groupID: UUID, before: Date? = nil,
                         limit: Int = 50) async throws -> [ChatMessage] {
        do {
            var query = SupabaseService.shared.client
                .from("chat_messages")
                .select()
                .eq("group_id", value: groupID.uuidString)
            if let before {
                query = query.lt("created_at", value: before.ISO8601Format(.iso8601(timeZone: TimeZone(secondsFromGMT: 0)!, includingFractionalSeconds: true)))
            }
            let rows: [ChatMessage] = try await query
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func send(groupID: UUID, body: String) async throws -> ChatMessage {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let row: ChatMessage = try await SupabaseService.shared.client
                .from("chat_messages")
                .insert(["id": UUID().uuidString,
                         "group_id": groupID.uuidString,
                         "author_id": me.uuidString,
                         "kind": "text",
                         "body": body])
                .select()
                .single()
                .execute()
                .value
            return row
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func react(messageID: UUID, emoji: String) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("chat_message_reactions")
                .insert(["message_id": messageID.uuidString,
                         "user_id": me.uuidString,
                         "emoji": emoji])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func unreact(messageID: UUID, emoji: String) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("chat_message_reactions")
                .delete()
                .eq("message_id", value: messageID.uuidString)
                .eq("user_id", value: me.uuidString)
                .eq("emoji", value: emoji)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func reactions(messageIDs: [UUID]) async throws -> [ChatReaction] {
        guard !messageIDs.isEmpty else { return [] }
        do {
            let rows: [ChatReaction] = try await SupabaseService.shared.client
                .from("chat_message_reactions")
                .select()
                .in("message_id", values: messageIDs.map(\.uuidString))
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func markRead(groupID: UUID, messageID: UUID) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("chat_read_state")
                .upsert(["group_id": groupID.uuidString,
                         "user_id": me.uuidString,
                         "last_read_message_id": messageID.uuidString])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func hasUnread(groupID: UUID) async throws -> Bool {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let latest = try await messages(groupID: groupID, limit: 1)
            guard let latestID = latest.first?.id else { return false }

            struct ReadState: Codable {
                let lastReadMessageID: UUID?
                enum CodingKeys: String, CodingKey {
                    case lastReadMessageID = "last_read_message_id"
                }
            }
            let states: [ReadState] = try await SupabaseService.shared.client
                .from("chat_read_state")
                .select("last_read_message_id")
                .eq("group_id", value: groupID.uuidString)
                .eq("user_id", value: me.uuidString)
                .execute()
                .value
            return states.first?.lastReadMessageID != latestID
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
