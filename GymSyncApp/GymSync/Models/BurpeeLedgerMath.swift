import Foundation

/// Pure, testable aggregation for the Burpee Ledger (Canvas Completion Task 3,
/// proof p25). No repository/network dependency — callers pass already-fetched
/// `BurpeeLedgerRow`s in (mirrors `StatMath`'s pattern).
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

    /// Per-user crew debts across every row supplied (the caller's query is
    /// already group-scoped), sorted by total owed descending — ties broken
    /// by user ID for a deterministic, stable order (the view layers profile
    /// names on top; it doesn't need this function to know about them).
    static func crewDebts(rows: [BurpeeLedgerRow]) -> [CrewDebt] {
        var totals: [UUID: Int] = [:]
        var lateCounts: [UUID: Int] = [:]
        var noShowCounts: [UUID: Int] = [:]

        for row in rows {
            totals[row.userID, default: 0] += row.burpeesOwed
            switch row.checkInState {
            case "late":    lateCounts[row.userID, default: 0] += 1
            case "no_show": noShowCounts[row.userID, default: 0] += 1
            default: break
            }
        }

        return totals.keys.map { userID in
            CrewDebt(
                userID: userID,
                totalOwed: totals[userID] ?? 0,
                lateCount: lateCounts[userID] ?? 0,
                noShowCount: noShowCounts[userID] ?? 0
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
