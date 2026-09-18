import Foundation
import Supabase

// MARK: - The crew's week, from the server (owner decision 21, plan task S7)
//
// `CrewWeekStrip`, `CrewWeek` and `CrewWeekMath` all shipped in Phase A with
// no read behind them: `LobbyView.crewWeek` returned nil in production and
// explained, in twenty lines, that the per-member weekly count existed nowhere
// — `SocialTabView`'s bar counts the whole crew and `group_consistency_honor`
// is per member but over thirty days, which is the right shape on the wrong
// window. `crew_week` is that read, and this is the client half of it.
//
// THIS TASK IS THE READ AND NOTHING ELSE. The strip's composition does not
// change and frame 135 keeps its fixture.

/// One row of `crew_week(p_session_id uuid, p_week_start timestamptz)`.
/// **R-B2-16**: `p_week_start` was `date` when this file was first written;
/// review found that a device-local date cast at the server's own time zone
/// silently moves the week boundary for anyone not on it, so the parameter
/// is timestamptz and the client sends the INSTANT, with its own offset —
/// see `WeekMath.weekStartISO8601(_:calendar:)`.
///
/// The RPC's shape is `group_consistency_honor`'s, deliberately: the
/// participant gate runs FIRST (`private.is_session_participant`), one
/// `LEFT JOIN LATERAL` per member so two cardinalities cannot multiply, and a
/// `REVOKE` then `GRANT`. Two departures, both named in the migration's own
/// header: the window is a PARAMETER rather than `now() - interval '30 days'`,
/// and **a member with zero sessions is a row, not an absence** — the honor
/// RPC drops them because a crown decays, but a crew's week must show the
/// lifter who has not trained yet, or the strip lies about the crew's size.
struct CrewWeekRow: Decodable, Sendable, Equatable {
    let userID: UUID
    let username: String
    /// `profiles.weekly_session_goal`, as the EFFECTIVE goal for that week
    /// (ruling R-B2-14): the server applies the same rule as
    /// `Profile.effectiveWeeklyGoal`, so a goal LOWERED after the week started
    /// still reports the week's own figure. **The app maps it straight across
    /// and must not re-apply the rule client-side** — doing it twice is how a
    /// number comes to disagree with itself.
    ///
    /// The column is `NOT NULL DEFAULT 3`, so the RPC never returns SQL NULL;
    /// the optional here is for the fixture's nil case and for a future
    /// opt-out, and `CrewWeekLifter.goal` keeps the same shape.
    let goal: Int?
    /// DISTINCT completed sessions inside the window, joined through
    /// `session_participants` — attendance, exactly as
    /// `group_consistency_honor` counts it.
    let done: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username, goal, done
    }
}

enum CrewWeekRepository {
    /// The crew's week. Best-effort, like every other read the lobby makes:
    /// a failure leaves the lobby without the strip, never with an error.
    ///
    /// `GroupRepository.consistencyHonor`'s idiom verbatim, including the
    /// `ErrorMapping.map` on the catch. `weekStart` is
    /// `WeekMath.weekStartISO8601()` (ruling R-B2-16) — the device-local
    /// week-start INSTANT, offset and all, not the `yyyy-MM-dd` key
    /// `weekly_goals` rows are filed under; the RPC's own `p_week_start` is
    /// timestamptz, so a date string here would let the server's time zone
    /// silently pick a different week for anyone not on it.
    ///
    /// THE GATE IS THE SERVER'S. A caller who is not a participant of the
    /// session raises `P0001` inside the function rather than reading somebody
    /// else's crew, which reaches the lobby as a thrown error and therefore as
    /// NO STRIP — never as an error surface, because a lifter who cannot see a
    /// chart has not done anything wrong.
    static func week(sessionID: UUID, weekStart: String) async throws -> [CrewWeekRow] {
        do {
            return try await SupabaseService.shared.client
                .rpc("crew_week", params: ["p_session_id": sessionID.uuidString,
                                           "p_week_start": weekStart])
                .execute()
                .value
        } catch { throw ErrorMapping.map(error) }
    }
}
