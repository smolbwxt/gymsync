import Foundation
import Supabase

// MARK: - Pump Check posts (spec 2026-07-27, P1 backend 20260731000001)
//
// A post is an IMMUTABLE SNAPSHOT of a finished workout: the summary jsonb
// is frozen at post time (later set edits never rewrite it) and weights are
// canonical POUNDS per the Units doctrine — the FEED renders them in the
// viewer's own display unit.

/// The denormalized summary written into `workout_posts.summary`.
struct PostSummary: Codable, Sendable, Equatable {
    struct ExerciseEntry: Codable, Sendable, Equatable {
        struct SetEntry: Codable, Sendable, Equatable {
            let weightLbs: Decimal?
            let reps: Int?
            let isPR: Bool
            let isFailed: Bool

            enum CodingKeys: String, CodingKey {
                case weightLbs = "weight_lbs"
                case reps
                case isPR = "is_pr"
                case isFailed = "is_failed"
            }
        }

        let name: String
        /// The exercise's equipment slug — the feed shows a GSBarLoaderMini
        /// for "barbell" entries (top set), per spec decision 4.
        let equipment: String
        let sets: [SetEntry]
    }

    let durationSeconds: Int
    let totalVolumeLbs: Decimal
    let exercises: [ExerciseEntry]

    enum CodingKeys: String, CodingKey {
        case durationSeconds = "duration_seconds"
        case totalVolumeLbs = "total_volume_lbs"
        case exercises
    }
}

struct WorkoutPost: Codable, Identifiable, Sendable {
    let id: UUID
    let authorID: UUID
    let sessionID: UUID
    let photoPath: String?
    let summary: PostSummary
    let includesHR: Bool
    let avgBpm: Int?
    let maxBpm: Int?
    let isLate: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, summary
        case authorID = "author_id"
        case sessionID = "session_id"
        case photoPath = "photo_path"
        case includesHR = "includes_hr"
        case avgBpm = "avg_bpm"
        case maxBpm = "max_bpm"
        case isLate = "is_late"
        case createdAt = "created_at"
    }
}

enum WorkoutPostRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    private struct PostInsert: Encodable {
        let id: UUID
        let authorID: UUID
        let sessionID: UUID
        let photoPath: String?
        let summary: PostSummary
        let includesHR: Bool
        let avgBpm: Int?
        let maxBpm: Int?
        let isLate: Bool

        enum CodingKeys: String, CodingKey {
            case id, summary
            case authorID = "author_id"
            case sessionID = "session_id"
            case photoPath = "photo_path"
            case includesHR = "includes_hr"
            case avgBpm = "avg_bpm"
            case maxBpm = "max_bpm"
            case isLate = "is_late"
        }
    }

    /// Uploads the photo FIRST, then inserts the row — the storage RLS keys
    /// ownership off the author folder (`posts/{author_id}/{post_id}.jpg`,
    /// 20260731000001), so the object may exist before its row and a failed
    /// insert leaves at worst an orphan in the author's own folder.
    /// HR values are hard-gated on `includesHR` here as well as by the
    /// table CHECK — the client must never ship bpm the user didn't share.
    static func create(sessionID: UUID,
                       summary: PostSummary,
                       photoJPEG: Data?,
                       includesHR: Bool,
                       avgBpm: Int?,
                       maxBpm: Int?,
                       isLate: Bool) async throws -> WorkoutPost {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        let postID = UUID()
        var photoPath: String?
        if let photoJPEG {
            let path = "posts/\(userID.uuidString.lowercased())/\(postID.uuidString.lowercased()).jpg"
            do {
                try await client.storage
                    .from("workout-photos")
                    .upload(path, data: photoJPEG,
                            options: FileOptions(contentType: "image/jpeg"))
            } catch {
                throw ErrorMapping.map(error)
            }
            photoPath = path
        }
        do {
            let row: WorkoutPost = try await client
                .from("workout_posts")
                .insert(PostInsert(
                    id: postID, authorID: userID, sessionID: sessionID,
                    photoPath: photoPath, summary: summary,
                    includesHR: includesHR,
                    avgBpm: includesHR ? avgBpm : nil,
                    maxBpm: includesHR ? maxBpm : nil,
                    isLate: isLate))
                .select()
                .single()
                .execute()
                .value
            return row
        } catch { throw ErrorMapping.map(error) }
    }

    /// Photos live in a PRIVATE bucket (friends-only RLS) — signed URLs,
    /// same idiom as chat images.
    static func signedPhotoURL(path: String) async throws -> URL {
        do {
            return try await client.storage
                .from("workout-photos")
                .createSignedURL(path: path, expiresIn: 3600)
        } catch { throw ErrorMapping.map(error) }
    }

    static func delete(id: UUID, photoPath: String?) async throws {
        do {
            try await client.from("workout_posts").delete()
                .eq("id", value: id.uuidString).execute()
            // Best-effort: the row is authoritative; a surviving orphan
            // object is unreadable by anyone but the author's friends and
            // unreferenced by any feed.
            if let photoPath {
                _ = try? await client.storage.from("workout-photos").remove(paths: [photoPath])
            }
        } catch { throw ErrorMapping.map(error) }
    }

    // MARK: - Feed (P3)

    /// Postgres accepts this full-precision form as a timestamptz literal —
    /// keyset cursor for the feed's "load more".
    private static let cursorFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Newest-first page. RLS does ALL the audience filtering (author +
    /// unblocked accepted friends) — the client sends no friend list.
    static func feed(before: Date? = nil, limit: Int = 20) async throws -> [WorkoutPost] {
        do {
            if let before {
                return try await client.from("workout_posts").select()
                    .lt("created_at", value: cursorFormatter.string(from: before))
                    .order("created_at", ascending: false)
                    .limit(limit)
                    .execute().value
            }
            return try await client.from("workout_posts").select()
                .order("created_at", ascending: false)
                .limit(limit)
                .execute().value
        } catch { throw ErrorMapping.map(error) }
    }

    static func reactions(postIDs: [UUID]) async throws -> [PostReaction] {
        guard !postIDs.isEmpty else { return [] }
        do {
            return try await client.from("post_reactions").select()
                .in("post_id", values: postIDs.map(\.uuidString))
                .execute().value
        } catch { throw ErrorMapping.map(error) }
    }

    private struct ReactionInsert: Encodable {
        let postID: UUID
        let userID: UUID
        let emoji: String
        enum CodingKeys: String, CodingKey {
            case postID = "post_id"
            case userID = "user_id"
            case emoji
        }
    }

    static func react(postID: UUID, emoji: String) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client.from("post_reactions")
                .insert(ReactionInsert(postID: postID, userID: userID, emoji: emoji))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    static func unreact(postID: UUID, emoji: String) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client.from("post_reactions").delete()
                .eq("post_id", value: postID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .eq("emoji", value: emoji)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}

struct PostReaction: Codable, Sendable {
    let postID: UUID
    let userID: UUID
    let emoji: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
        case emoji
    }
}
