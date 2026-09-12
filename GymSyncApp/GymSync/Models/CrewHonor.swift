import Foundation
import Supabase

// MARK: - The crew's frequency honor
//
// Spec: docs/superpowers/specs/2026-09-11-social-cards-design.md §3.
// Plan: docs/superpowers/plans/2026-09-11-social-cards-plan.md, task S1.3.
//
// FREQUENCY, NOT PERFORMANCE (owner decision 5). The crown is "who showed up
// most this month" over a rolling 30 days — pace-, weight- and volume-blind,
// and continuously losable. Volume already has two homes (the recap and the
// venue hub); this is deliberately not a third.

/// One row of `group_consistency_honor(p_group_id)` (migration
/// 20260911000001).
struct CrewHonorRow: Decodable, Sendable, Equatable {
    let userID: UUID
    let username: String
    let sessions: Int
    /// The member's LATEST qualifying completion — the moment they reached
    /// the count they now hold, and therefore the tie-break.
    let reachedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case username
        case sessions
        case reachedAt = "reached_at"
    }
}

/// The one name the card prints.
struct CrewHonor: Equatable, Sendable {
    let username: String
    let sessions: Int
}

enum CrewHonorMath {

    /// The crown, or **nil when nobody has trained in the window** — which is
    /// how the honor DECAYS (spec §3: "a crown that decays when they stop").
    /// A crew at rest has no honor line at all; it does not have an honor
    /// line reading zero.
    ///
    /// The server already orders the rows, and this re-derives the winner
    /// anyway: an ORDER BY is a detail of one query, and the card's meaning
    /// should not move if that query is ever paged, cached or re-sorted.
    static func crown(_ rows: [CrewHonorRow]) -> CrewHonor? {
        let earned = rows.filter { $0.sessions > 0 }
        guard let best = earned.min(by: { lhs, rhs in
            // Most sessions first; on a tie, the EARLIER achiever (spec §3).
            if lhs.sessions != rhs.sessions { return lhs.sessions > rhs.sessions }
            return lhs.reachedAt < rhs.reachedAt
        }) else { return nil }
        return CrewHonor(username: best.username, sessions: best.sessions)
    }

    /// `MOST CONSISTENT · SAM · 9 SESSIONS` — spec §3's line, verbatim.
    ///
    /// Caps because it is a kicker (design rule 3), and the username is
    /// upper-cased here rather than by the view so the one place that decides
    /// the sentence also decides its case.
    static func line(_ honor: CrewHonor) -> String {
        let noun = honor.sessions == 1 ? "SESSION" : "SESSIONS"
        return "MOST CONSISTENT · \(honor.username.uppercased()) · \(honor.sessions) \(noun)"
    }
}

extension GroupRepository {
    /// The crew's 30-day frequency honor. Best-effort, like every other read
    /// the Crews tab makes: a failure leaves the card without an honor line,
    /// never with an error.
    static func consistencyHonor(groupID: UUID) async throws -> [CrewHonorRow] {
        do {
            return try await SupabaseService.shared.client
                .rpc("group_consistency_honor", params: ["p_group_id": groupID.uuidString])
                .execute()
                .value
        } catch { throw ErrorMapping.map(error) }
    }
}
