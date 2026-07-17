import Foundation
import Supabase

// MARK: - UserStreak (Phase S Task 5)
//
// One `user_streaks` row (20260719000006_streaks.sql) — RLS: owner + accepted
// friends can read (`is_friend()`), no client write policy exists at all
// (INSERT/UPDATE happen only via the `streak_bump_user`/`streak_break_user`
// SECURITY DEFINER helpers, fired by the `streak_on_no_show` /
// `streak_on_session_state_change` triggers). This app never writes this
// table directly — read-only DTO, same idiom as `GroupBurpeeLedgerAggregate`
// (Session.swift).
//
// `currentStreak`/`longestStreak` decode as non-optional `Int`: both columns
// carry a `DEFAULT 0`, and every writer (`streak_bump_user`, `streak_break_
// user`) always assigns a concrete integer — `COALESCE(..., 0) + 1` / literal
// `0` — never NULL. `lastStreakSessionID`/`brokenAt`/`brokenBySessionID` stay
// genuinely optional: a fresh row (or one that's never broken) leaves those
// NULL by design.
struct UserStreak: Decodable, Sendable, Equatable {
    let userID: UUID
    let currentStreak: Int
    let longestStreak: Int
    let lastStreakSessionID: UUID?
    let brokenAt: Date?
    let brokenBySessionID: UUID?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case lastStreakSessionID = "last_streak_session_id"
        case brokenAt = "broken_at"
        case brokenBySessionID = "broken_by_session_id"
    }
}

// MARK: - GroupStreak (Phase F Task 5)
//
// One `group_streaks` row (20260719000006_streaks.sql) — RLS: "members can
// read group streaks" (`is_group_member`), no client write policy (writes
// happen only via the same `streak_bump_group`/`streak_break_group`
// SECURITY DEFINER trigger helpers as `user_streaks`). Read-only DTO,
// field-for-field parallel to `UserStreak` above (`group_id` in place of
// `user_id`, otherwise identical shape and NULL-ability reasoning).
struct GroupStreak: Decodable, Sendable, Equatable {
    let groupID: UUID
    let currentStreak: Int
    let longestStreak: Int
    let lastStreakSessionID: UUID?
    let brokenAt: Date?
    let brokenBySessionID: UUID?

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case lastStreakSessionID = "last_streak_session_id"
        case brokenAt = "broken_at"
        case brokenBySessionID = "broken_by_session_id"
    }
}

enum StreakRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// The given user's streak row — `nil` when none exists yet. A user who
    /// has never carried a scheduled session through to a 'ready' completion
    /// has no `user_streaks` row at all (the two SECURITY DEFINER helpers
    /// above are the only writers, and both insert-on-first-touch); callers
    /// must treat `nil` as the zero-state (0 current / 0 longest), same
    /// pattern `ProfileRepository.fetch(userID:)` already uses for a missing
    /// `profiles` row (PGRST116 -> nil, not an error).
    static func userStreak(userID: UUID) async throws -> UserStreak? {
        do {
            let row: UserStreak = try await client
                .from("user_streaks")
                .select()
                .eq("user_id", value: userID.uuidString)
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

    /// The given group's streak row — `nil` when none exists yet, same
    /// PGRST116 -> nil idiom as `userStreak(userID:)` (a group whose
    /// sessions have never yet produced an all-ready completion has no
    /// `group_streaks` row — insert-on-first-touch, same as the user table).
    static func groupStreak(groupID: UUID) async throws -> GroupStreak? {
        do {
            let row: GroupStreak = try await client
                .from("group_streaks")
                .select()
                .eq("group_id", value: groupID.uuidString)
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
}
