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
    /// The routine this session ran — spec §1 line 5's `Push day · 42 min ·
    /// 7,240 lb`. Optional: a freeform workout has no routine, and every post
    /// written before this field existed decodes with nil (a synthesized
    /// `Decodable` uses `decodeIfPresent` for an Optional).
    ///
    /// SNAKE_CASE, unlike this plan's new columns: `PostSummary` declares its
    /// keys explicitly and has spoken snake_case since 2026-07 (:20-25,
    /// :39-43). One jsonb document may not speak two conventions (global
    /// constraint 11).
    let routineName: String?

    enum CodingKeys: String, CodingKey {
        case durationSeconds = "duration_seconds"
        case totalVolumeLbs = "total_volume_lbs"
        case exercises
        case routineName = "routine_name"
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
    /// The session's completion (spec §6), copied at post time. Optional
    /// because old rows have none; `PostLateness` treats that as an absence
    /// rather than as zero.
    let completedAt: Date?
    /// How many times the lifter re-shot before posting (spec §2). OPTIONAL
    /// in Swift though the column is `NOT NULL DEFAULT 0`: a synthesized
    /// `Decodable` does not fall back to a property's default for a missing
    /// key, so an optional is what keeps the feed decoding if a client ever
    /// meets a projection without it. `?? 0` at the one read site.
    let retakeCount: Int?
    let highlight: PostHighlight?
    /// Lines 2 and 3, frozen (see `PostTrajectory`'s doc comment for why this
    /// is not resolved from `goalID`).
    let trajectory: PostTrajectory?
    /// PROVENANCE, not the render source: which block this post belonged to.
    let goalID: UUID?
    /// The rung's week key, `yyyy-MM-dd`. A **String**, because DATE columns
    /// must not go through the SDK's timestamp decoder — the `SessionSeries`
    /// idiom `Models/ProgramEnrollment.swift:36-38` and `WeeklyGoal
    /// .weekStartString` both record.
    let weekStartString: String?

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
        case completedAt = "completed_at"
        case retakeCount = "retake_count"
        case highlight
        case trajectory
        case goalID = "goal_id"
        case weekStartString = "week_start"
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
        let completedAt: Date?
        let retakeCount: Int
        let highlight: PostHighlight?
        let trajectory: PostTrajectory?
        let goalID: UUID?
        let weekStartString: String?

        enum CodingKeys: String, CodingKey {
            case id, summary, highlight, trajectory
            case authorID = "author_id"
            case sessionID = "session_id"
            case photoPath = "photo_path"
            case includesHR = "includes_hr"
            case avgBpm = "avg_bpm"
            case maxBpm = "max_bpm"
            case isLate = "is_late"
            case completedAt = "completed_at"
            case retakeCount = "retake_count"
            case goalID = "goal_id"
            case weekStartString = "week_start"
        }
    }

    /// Uploads the photo FIRST, then inserts the row — the storage RLS keys
    /// ownership off the author folder (`posts/{author_id}/{post_id}.jpg`,
    /// 20260731000001), so the object may exist before its row and a failed
    /// insert leaves at worst an orphan in the author's own folder.
    /// HR values are hard-gated on `includesHR` here as well as by the
    /// table CHECK — the client must never ship bpm the user didn't share.
    ///
    /// `isLate` IS NO LONGER A PARAMETER. Spec §2 makes it a derivation from
    /// `postedAt − completedAt` (`PostLateness.isLate`), so the one place
    /// that writes the row is the one place that decides it — a caller can no
    /// longer hand in a lateness that disagrees with the timestamps beside it.
    /// `capturedLate` survives as the FALLBACK for a session with no
    /// `completed_at`, which is a shape this app no longer writes.
    static func create(sessionID: UUID,
                       summary: PostSummary,
                       photoJPEG: Data?,
                       includesHR: Bool,
                       avgBpm: Int?,
                       maxBpm: Int?,
                       completedAt: Date?,
                       capturedLate: Bool,
                       retakeCount: Int,
                       highlight: PostHighlight?,
                       trajectory: PostTrajectory?,
                       goalID: UUID?,
                       weekStartString: String?,
                       postedAt: Date = .now) async throws -> WorkoutPost {
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
                    isLate: PostLateness.isLate(completedAt: completedAt,
                                                postedAt: postedAt,
                                                fallback: capturedLate),
                    completedAt: completedAt,
                    retakeCount: retakeCount,
                    highlight: highlight,
                    trajectory: trajectory,
                    goalID: goalID,
                    weekStartString: weekStartString))
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
