import Foundation

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
