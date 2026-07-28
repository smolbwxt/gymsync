import Foundation
import Supabase

// ============================================================
// Phase M / Task 2: block/report UI models + repository
// ============================================================
// Backend contract (Task 1, supabase/migrations/20260721000001_moderation_
// block_report.sql — task-1-report.md): `blocked_users` (blocker_id,
// blocked_id) all-ops owner=blocker; `user_reports` (id, reporter_id,
// reported_user_id, reported_content_type, reported_content_id, reason,
// status default 'open') — INSERT reporter=auth.uid(), SELECT reporter-only.
// Decode structs use snake_case CodingKeys per this codebase's convention
// (Friendship.swift, GymGroup.swift, ChatMessage.swift).

/// One row of `blocked_users`. `blockerID` is always the current user for
/// every row this app can read (owner-only RLS — "blocker manages own
/// blocks"), but the field is kept (not dropped) since it's part of the
/// table's real shape and the composite PK.
struct BlockedUser: Codable, Sendable, Equatable {
    let blockerID: UUID
    let blockedID: UUID
    let blockedAt: Date

    enum CodingKeys: String, CodingKey {
        case blockerID = "blocker_id"
        case blockedID = "blocked_id"
        case blockedAt = "blocked_at"
    }
}

struct UserReport: Codable, Sendable, Equatable {
    let id: UUID
    let reporterID: UUID
    let reportedUserID: UUID?
    let reportedContentType: String?
    let reportedContentID: UUID?
    let reason: String?
    let createdAt: Date
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case reporterID = "reporter_id"
        case reportedUserID = "reported_user_id"
        case reportedContentType = "reported_content_type"
        case reportedContentID = "reported_content_id"
        case reason
        case createdAt = "created_at"
        case status
    }
}

/// Fixed reason categories shown in `ReportSheet` (spec: "a small set of
/// fixed reason categories" + freeform text). `rawValue` doubles as the
/// display label — the submitted `reason` string is composed client-side
/// (category label, optionally with the freeform text appended); the DB
/// column is plain `text` with no CHECK constraint on this value (only on
/// `status`), so no server-side enum to keep in sync with.
enum ReportReason: String, CaseIterable, Identifiable {
    case harassment = "Harassment"
    case spam = "Spam"
    case inappropriateContent = "Inappropriate content"
    case other = "Other"

    var id: String { rawValue }
}

/// `reported_content_type` values, per the brief's contract: a profile
/// report uses type='profile'/id=userID; a chat message report uses
/// type='chat_message'/id=messageID; a routine report uses type='routine'/
/// id=routineID.
enum ReportedContentType: String {
    case profile
    case chatMessage = "chat_message"
    case routine
    /// Pump Check post (photos are UGC — App Store 1.2 requires a report
    /// path on every surface that shows them). `reported_content_type` has
    /// no DB CHECK; the string is the contract.
    case post
}

enum ModerationRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    // MARK: - Block

    static func block(userID: UUID) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("blocked_users")
                .insert(["blocker_id": me.uuidString, "blocked_id": userID.uuidString])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func unblock(userID: UUID) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("blocked_users")
                .delete()
                .eq("blocker_id", value: me.uuidString)
                .eq("blocked_id", value: userID.uuidString)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Blocked users, joined against `profiles` for display (You-tab
    /// "Blocked Users" list) — same fetch-ids-then-`fetchMany` shape as
    /// `FriendRepository.friends()`/`GroupRepository.members(groupID:)`
    /// rather than a PostgREST embed, matching this codebase's established
    /// idiom for turning a join table into `[Profile]`.
    ///
    /// `blocked_users` is fetched ordered `blocked_at DESC`, but
    /// `ProfileRepository.fetchMany`'s `.in()` doesn't preserve input order
    /// (PostgREST returns matches in its own order, not the ids-list order),
    /// so the final list is re-sorted to `rows`' order here — same
    /// dictionary-preserve pattern as `GymGroup.members(groupID:)`
    /// (GymSyncApp/GymSync/Models/GymGroup.swift): build an id→Profile
    /// lookup, then walk `rows` (already most-recent-first) and map each to
    /// its profile.
    static func blockedUsers() async throws -> [Profile] {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [BlockedUser] = try await client
                .from("blocked_users")
                .select()
                .eq("blocker_id", value: me.uuidString)
                .order("blocked_at", ascending: false)
                .execute()
                .value
            let profiles = try await ProfileRepository.fetchMany(ids: rows.map(\.blockedID))
            let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            return rows.compactMap { byID[$0.blockedID] }
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    // MARK: - Report

    /// Files a report as the current user. `userID` is the reported user —
    /// for a profile report this is the same value as `contentID`; for a
    /// chat message or routine report it's that content's author/owner.
    static func report(
        userID: UUID,
        contentType: ReportedContentType,
        contentID: UUID,
        reason: String
    ) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("user_reports")
                .insert([
                    "reporter_id": me.uuidString,
                    "reported_user_id": userID.uuidString,
                    "reported_content_type": contentType.rawValue,
                    "reported_content_id": contentID.uuidString,
                    "reason": reason,
                ])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
