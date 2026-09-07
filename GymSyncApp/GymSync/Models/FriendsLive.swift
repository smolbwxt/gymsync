import Foundation
import Supabase

// MARK: - FriendsLive
//
// Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
// -goal-design.md §A item 6 (the crew pulse strip). Plan:
// docs/superpowers/plans/2026-09-06-home-v3-production-plan.md, task 0.5.
//
// Who from your crew is in the gym RIGHT NOW. One row feeds
// `HomeCrewPulseStrip`; the rest is headroom for the "and 2 more" the strip
// does not show yet.
//
// The server side is Stream A: a `friends_live()` SECURITY DEFINER RPC
// (task A8 — the sessions/session_participants policies reference each
// other, so a cross-table subquery from a policy re-enters the other
// table's RLS and cycles; `20260709000006_create_sessions.sql:31-33`
// documents the precedent), and `LiveFriendsLiveRepository` behind it
// (task A9).

/// A friend who is mid-session.
struct FriendLive: Identifiable, Equatable, Sendable {
    let id: UUID              // friend's profile id
    let initials: String      // two letters, the HomeCrewPulseStrip idiom
    let displayName: String
    let sessionID: UUID
    let groupID: UUID?
    let groupName: String?
    let startedAt: Date?
}

/// Reads who is live. `async` with no `throws`, like every other Home fetch:
/// a failure means "nobody is lifting", which renders as nothing at all
/// rather than as an error on a strip.
protocol FriendsLiveRepository: Sendable { func live() async -> [FriendLive] }

/// The shipping default until Stream A task A9 lands.
///
/// Deliberate, not a placeholder. Owner ruling 2 says the crew-pulse strip
/// is ABSENT unless a friend is actually lifting — no "nobody's training"
/// empty state, no reserved gap — and an empty repository is exactly that
/// state. So Home is correct at every point in the build rather than only
/// at the end: `app-tab-home` renders the strip's absence today, which is
/// what most captures will show once the RPC is live anyway.
struct EmptyFriendsLiveRepository: FriendsLiveRepository { func live() async -> [FriendLive] { [] } }

// MARK: - The live one (task A9)

/// One row of the `friends_live()` RPC
/// (`supabase/migrations/20260906000002_friends_live.sql`).
///
/// A private DTO rather than `Codable` on `FriendLive`, for two reasons the
/// model itself makes plain: `FriendLive.initials` has no column — it is
/// derived from the display name here — and `FriendLive.displayName` must
/// fall back to `username`, which is `NOT NULL`, when a profile has never
/// set one. Both are decisions about presentation, and they belong on this
/// side of the decode rather than in the type four streams share.
private struct FriendLiveRow: Decodable {
    let userID: UUID
    let username: String
    let displayName: String?
    let sessionID: UUID
    let groupID: UUID?
    let groupName: String?
    let startedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case displayName = "display_name"
        case sessionID = "session_id"
        case groupID = "group_id"
        case groupName = "group_name"
        case startedAt = "started_at"
    }
}

/// Who from your crew is lifting right now, from the server.
///
/// The RPC is `SECURITY DEFINER` and takes no parameters — every row it can
/// return is already reachable from `auth.uid()` through an accepted
/// friendship, so there is nothing to pass and nothing to authorize
/// client-side.
struct LiveFriendsLiveRepository: FriendsLiveRepository {

    /// Two letters from the first two words of a name — the exact
    /// derivation `TrainingCalendarWidget.initials(_:)`
    /// (`TrainingCalendarWidget.swift:287`) uses for its avatar chips.
    /// DUPLICATED rather than extracted: that one is a `private func` on a
    /// SwiftUI view Stream D takes ownership of in D1, and reaching into it
    /// from a repository would couple this fetch to a view's lifetime for
    /// three lines of string handling. If a third caller appears, that is
    /// the moment to lift it into a shared helper.
    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        return words.map { String($0.prefix(1)).uppercased() }.joined()
    }

    /// Best-effort, like every other Home fetch: any failure — no session,
    /// no network, a decode change — means "nobody is lifting", which the
    /// strip renders as nothing at all rather than as an error. The failure
    /// is logged so a silently-empty pulse is diagnosable.
    func live() async -> [FriendLive] {
        do {
            let rows: [FriendLiveRow] = try await SupabaseService.shared.client
                .rpc("friends_live")
                .execute().value
            return rows.map { row in
                let name = row.displayName?.isEmpty == false
                    ? (row.displayName ?? row.username)
                    : row.username
                return FriendLive(id: row.userID,
                                  initials: Self.initials(name),
                                  displayName: name,
                                  sessionID: row.sessionID,
                                  groupID: row.groupID,
                                  groupName: row.groupName,
                                  startedAt: row.startedAt)
            }
        } catch {
            AppLogger.db.error("friends_live failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
