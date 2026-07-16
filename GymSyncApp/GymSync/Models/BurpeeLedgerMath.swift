import Foundation

/// Pure, testable aggregation for the Burpee Ledger (Canvas Completion Task 3,
/// proof p25). No repository/network dependency — callers pass already-fetched
/// rows in (mirrors `StatMath`'s pattern): `crewDebts` takes the
/// `group_burpee_ledger` RPC's pre-aggregated `GroupBurpeeLedgerAggregate`
/// rows (Fix round 1 — server-side, membership-gated); `youOweSummary` still
/// takes raw self-only `BurpeeLedgerRow`s (own rows are always RLS-visible).
///
/// SCHEMA GAP — CLOSED (Phase S Task 5, 20260719000005_burpee_ledger_paid.sql):
/// the proof's "paid off 20 · Jul 9" crew-debt state used to be unrenderable —
/// `session_participants.burpees_owed` is computed once by `evaluate_lateness`
/// and never decremented, so the RPC's `total_owed` alone could never
/// distinguish "never owed" from "owed and settled elsewhere." The RPC now
/// also returns `paid` (derived: summed `is_penalty` set_logs reps in the
/// group's sessions) and `settled` (`paid >= total_owed`); `CrewDebt.
/// outstanding` nets the two so a settled participant's displayed number
/// reads 0, same as one who was never late — but `isPaidOff` still lets the
/// view tell the two apart for the subtext ("paid off 20" vs "all clear"),
/// which is what the schema couldn't do before.
enum BurpeeLedgerMath {

    struct CrewDebt: Identifiable, Sendable, Equatable {
        let userID: UUID
        /// Raw lifetime total from the RPC — never decremented, so this
        /// alone is NOT what the row displays or sorts by; see `outstanding`.
        let totalOwed: Int
        /// Summed `is_penalty` set_logs reps for this user in the group's
        /// sessions (RPC-derived, never stored) — see the file header.
        let paid: Int
        /// `paid >= totalOwed`, straight from the RPC.
        let settled: Bool
        let lateCount: Int
        let noShowCount: Int
        /// Most recent session (scheduled_for, falling back to started_at)
        /// that actually contributed debt (burpees_owed > 0) — server-computed
        /// by `group_burpee_ledger` (Fix round 1). Doubles as the "paid off
        /// N · {date}" row's date (Phase S Task 5) — the RPC has no separate
        /// "paid at" timestamp, so this is the closest faithful date to show.
        let lastLateAt: Date?

        var id: UUID { userID }

        /// What's actually left to pay TODAY — `totalOwed` net of `paid`,
        /// floored at 0. This, not `totalOwed`, is what `crewDebtRow` shows
        /// as the row's headline number and what `crewDebts` sorts by: the
        /// proof's "Sam — paid off 20" row displays and sorts as 0, not 20.
        var outstanding: Int { max(totalOwed - paid, 0) }

        /// True once this participant has actually paid something off
        /// (`paid > 0`) and is caught up (`settled`) — as opposed to simply
        /// never having owed anything. Both read as `outstanding == 0`, but
        /// only one is a former debtor; distinguishes the proof's "Sam —
        /// paid off 20" row from its "Jordan — all clear" row.
        var isPaidOff: Bool { settled && paid > 0 }

        /// "3 no-shows · 2 late" / "1 late" / "all clear" / "paid off N" —
        /// matches the proof's per-row subtext (pluralized "no-show(s)",
        /// singular "late"). The paid-off check runs FIRST: `lateCount`/
        /// `noShowCount` are raw historical counts that a later payment never
        /// reduces, so a settled participant could still have `lateCount > 0`
        /// and must not fall into the "N late" branch below.
        var summaryText: String {
            if isPaidOff { return "paid off \(paid)" }
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

    /// Per-user crew debts, sorted by OUTSTANDING amount descending (Phase S
    /// Task 5 — was raw `totalOwed` before `paid`/`settled` existed; see the
    /// file header) — ties broken by user ID for a deterministic, stable
    /// order (the view layers profile names on top; it doesn't need this
    /// function to know about them). Sorting by `outstanding` rather than
    /// `totalOwed` is what puts a fully-paid-off high historical total (the
    /// proof's Sam, `totalOwed: 20, paid: 20`) at the bottom with the
    /// never-late rows instead of ranking it above someone who genuinely
    /// still owes less today.
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
                paid: aggregate.paid,
                settled: aggregate.settled,
                lateCount: aggregate.lateCount,
                noShowCount: aggregate.noShowCount,
                lastLateAt: aggregate.lastLateAt
            )
        }.sorted { lhs, rhs in
            if lhs.outstanding != rhs.outstanding { return lhs.outstanding > rhs.outstanding }
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
