import Foundation

/// Pure, testable aggregation for the Burpee Ledger (Canvas Completion Task 3,
/// proof p25). No repository/network dependency — callers pass already-fetched
/// rows in (mirrors `StatMath`'s pattern): `crewDebts` takes the
/// `group_burpee_ledger` RPC's pre-aggregated `GroupBurpeeLedgerAggregate`
/// rows (Fix round 1 — server-side, membership-gated); `youOweSummary` still
/// takes raw self-only `BurpeeLedgerRow`s (own rows are always RLS-visible).
///
/// SCHEMA GAP (recorded for product — see task-3-report.md): the proof shows a
/// "paid off 20 · Jul 9" crew-debt state. No paid/cleared concept exists
/// anywhere in the schema. `session_participants.burpees_owed` is computed
/// once by `evaluate_lateness` at session start and is never decremented —
/// not even when the owing participant actually logs the penalty burpees as a
/// set (`GroupSessionLiveView.penaltyLogged` only subtracts client-side, for
/// the duration of that one live view, and is never written back to the DB).
/// This math can only ever SUM the raw stored value; it cannot distinguish
/// "never owed" from "owed and settled elsewhere," so it renders owed-only —
/// a settled participant reads identically to one who was never late.
enum BurpeeLedgerMath {

    struct CrewDebt: Identifiable, Sendable, Equatable {
        let userID: UUID
        let totalOwed: Int
        let lateCount: Int
        let noShowCount: Int
        /// Most recent session (scheduled_for, falling back to started_at)
        /// that actually contributed debt (burpees_owed > 0) — server-computed
        /// by `group_burpee_ledger` (Fix round 1). Not currently rendered by
        /// `crewDebtRow`, kept for parity with the RPC's contract.
        let lastLateAt: Date?

        var id: UUID { userID }

        /// "3 no-shows · 2 late" / "1 late" / "all clear" — matches the
        /// proof's per-row subtext (pluralized "no-show(s)", singular "late").
        var summaryText: String {
            guard lateCount > 0 || noShowCount > 0 else { return "all clear" }
            var parts: [String] = []
            if noShowCount > 0 {
                parts.append("\(noShowCount) no-show\(noShowCount == 1 ? "" : "s")")
            }
            if lateCount > 0 {
                parts.append("\(lateCount) late")
            }
            return parts.joined(separator: " · ")
        }
    }

    struct YouOweSummary: Sendable, Equatable {
        let total: Int
        let mostRecentLateMinutes: Int?
        let mostRecentDate: Date?
        let mostRecentPerMinute: Int?
        let mostRecentSessionID: UUID?
        let mostRecentSessionIsLive: Bool
    }

    /// Per-user crew debts, sorted by total owed descending — ties broken by
    /// user ID for a deterministic, stable order (the view layers profile
    /// names on top; it doesn't need this function to know about them).
    ///
    /// Fix round 1 (task-3-report.md): summation/counting used to happen
    /// HERE, client-side, over raw `session_participants` rows fetched under
    /// RLS — which undercounted every crew member's total for any caller who
    /// joined the group after some of its sessions had already run (RLS hid
    /// rows for sessions they weren't invited to). That aggregation now
    /// happens server-side in `group_burpee_ledger` (membership-gated, not
    /// session-participant-gated); this function's remaining job is just the
    /// deterministic sort the view needs.
    static func crewDebts(aggregates: [GroupBurpeeLedgerAggregate]) -> [CrewDebt] {
        aggregates.map { aggregate in
            CrewDebt(
                userID: aggregate.userID,
                totalOwed: aggregate.totalOwed,
                lateCount: aggregate.lateCount,
                noShowCount: aggregate.noShowCount,
                lastLateAt: aggregate.lastLateAt
            )
        }.sorted { lhs, rhs in
            if lhs.totalOwed != rhs.totalOwed { return lhs.totalOwed > rhs.totalOwed }
            return lhs.userID.uuidString < rhs.userID.uuidString
        }
    }

    /// The current user's "YOU OWE" summary: total owed across every row for
    /// `userID`, plus the most-recent burpees-owed-contributing session's
    /// detail (late minutes + per-minute rate + date) for the proof's
    /// "N min late to {group} · {date} · {rate} burpees / min" subtext.
    /// `nil` detail fields mean that segment couldn't be determined — the
    /// view should omit it rather than fabricate a value.
    static func youOweSummary(rows: [BurpeeLedgerRow], userID: UUID) -> YouOweSummary {
        let mine = rows.filter { $0.userID == userID }
        let total = mine.reduce(0) { $0 + $1.burpeesOwed }

        let mostRecent = mine
            .filter { $0.burpeesOwed > 0 }
            .max { lhs, rhs in
                (lhs.session.effectiveDate ?? .distantPast) < (rhs.session.effectiveDate ?? .distantPast)
            }

        return YouOweSummary(
            total: total,
            mostRecentLateMinutes: mostRecent?.lateMinutes,
            mostRecentDate: mostRecent?.session.effectiveDate,
            mostRecentPerMinute: mostRecent?.session.latePenalty?.perMinute,
            mostRecentSessionID: mostRecent?.session.id,
            mostRecentSessionIsLive: mostRecent?.session.state == "in_progress"
        )
    }
}
