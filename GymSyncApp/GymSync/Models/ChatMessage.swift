import Foundation
import Supabase

struct ChatMessage: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let groupID: UUID
    let sessionID: UUID?
    let authorID: UUID?      // nil = system message
    let kind: Kind
    let body: String?
    let storagePath: String?
    let replyToID: UUID?
    let createdAt: Date
    let editedAt: Date?
    let deletedAt: Date?
    /// Optional jsonb payload — decoded additively so older rows that lack the column
    /// decode as nil without error.  soundboard_echo rows carry `{"sound_slug": "…"}`.
    let payload: [String: PayloadValue]?

    enum Kind: String, Codable, Sendable {
        case text, image, audio
        case systemPR = "system_pr"
        case systemSession = "system_session"
        case systemLate = "system_late"
        case systemLeaderboard = "system_leaderboard"
        case soundboardEcho = "soundboard_echo"
    }

    /// Flexible JSON value type for the payload column (jsonb).
    /// Only string and number variants are needed today.
    enum PayloadValue: Codable, Sendable, Equatable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
        case unknown

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self)  { self = .string(s); return }
            if let d = try? c.decode(Double.self)  { self = .number(d); return }
            if let b = try? c.decode(Bool.self)    { self = .bool(b);   return }
            if c.decodeNil() { self = .null; return }
            // Unknown type (objects, arrays, etc.) — tolerate without throwing
            self = .unknown
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let s): try c.encode(s)
            case .number(let d): try c.encode(d)
            case .bool(let b):   try c.encode(b)
            case .null:          try c.encodeNil()
            case .unknown:       try c.encodeNil()
            }
        }

        var stringValue: String? {
            if case .string(let s) = self { return s }
            return nil
        }
    }

    var isSystem: Bool { authorID == nil }

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case sessionID = "session_id"
        case authorID = "author_id"
        case kind, body, payload
        case storagePath = "storage_path"
        case replyToID = "reply_to_id"
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case deletedAt = "deleted_at"
    }

    // Custom decode: payload is optional/nullable in the schema — tolerate missing column.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try  c.decode(UUID.self,   forKey: .id)
        groupID      = try  c.decode(UUID.self,   forKey: .groupID)
        sessionID    = try? c.decodeIfPresent(UUID.self,   forKey: .sessionID)
        authorID     = try? c.decodeIfPresent(UUID.self,   forKey: .authorID)
        kind         = try  c.decode(Kind.self,   forKey: .kind)
        body         = try? c.decodeIfPresent(String.self, forKey: .body)
        storagePath  = try? c.decodeIfPresent(String.self, forKey: .storagePath)
        replyToID    = try? c.decodeIfPresent(UUID.self,   forKey: .replyToID)
        createdAt    = try  c.decode(Date.self,   forKey: .createdAt)
        editedAt     = try? c.decodeIfPresent(Date.self,   forKey: .editedAt)
        deletedAt    = try? c.decodeIfPresent(Date.self,   forKey: .deletedAt)
        payload      = try? c.decodeIfPresent([String: PayloadValue].self, forKey: .payload)
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

    static func sendImage(groupID: UUID, imageData: Data) async throws -> ChatMessage {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        guard let jpeg = ImageProcessor.jpegForUpload(from: imageData) else {
            throw GymSyncError.validation("That image couldn't be processed.")
        }
        let messageID = UUID()
        let path = try await StorageService.uploadChatImage(
            groupID: groupID, messageID: messageID, jpegData: jpeg)
        do {
            let row: ChatMessage = try await SupabaseService.shared.client
                .from("chat_messages")
                .insert(["id": messageID.uuidString,
                         "group_id": groupID.uuidString,
                         "author_id": me.uuidString,
                         "kind": "image",
                         "storage_path": path])
                .select()
                .single()
                .execute()
                .value
            return row
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func sendVoice(groupID: UUID,
                          fileURL: URL,
                          duration: TimeInterval) async throws -> ChatMessage {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        let messageID = UUID()
        let data = try Data(contentsOf: fileURL)
        let path = try await StorageService.uploadChatAudio(
            groupID: groupID, messageID: messageID, data: data)

        // Pre-render duration as "m:ss" string — e.g. "0:42", "1:03"
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds  = totalSeconds % 60
        let bodyText  = "\(minutes):\(String(format: "%02d", seconds))"

        // Use a Codable struct so the payload jsonb column encodes correctly
        // (same pattern as insertSoundboardEcho in SessionBroadcastService).
        struct AudioInsert: Encodable {
            let id: UUID
            let groupID: UUID
            let authorID: UUID
            let kind: String
            let body: String
            let storagePath: String
            let payload: [String: AnyJSON]

            enum CodingKeys: String, CodingKey {
                case id
                case groupID     = "group_id"
                case authorID    = "author_id"
                case kind, body, payload
                case storagePath = "storage_path"
            }
        }

        let insert = AudioInsert(
            id: messageID,
            groupID: groupID,
            authorID: me,
            kind: "audio",
            body: bodyText,
            storagePath: path,
            payload: ["duration_seconds": .double(duration)]
        )

        do {
            let row: ChatMessage = try await SupabaseService.shared.client
                .from("chat_messages")
                .insert(insert)
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
        let latest = try await messages(groupID: groupID, limit: 1)
        return try await hasUnread(latest: latest.first, groupID: groupID)
    }

    /// Same unread determination as `hasUnread(groupID:)`, but takes an already-fetched
    /// latest message so callers that also need the message body (e.g. for a preview line)
    /// don't have to issue a second `messages(groupID:limit:1)` query.
    static func hasUnread(latest: ChatMessage?, groupID: UUID) async throws -> Bool {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            guard let latestID = latest?.id else { return false }

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
