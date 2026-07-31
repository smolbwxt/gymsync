import Foundation

// MARK: - SessionScoreboard
//
// ROUND SCOREBOARD math (composite v5, BOARD page). Self-referenced only:
// % SELF compares each lifter's best set TODAY against their OWN best-ever
// est-1RM for that exercise (Epley via StatMath.estimatedOneRepMax — the
// one 1RM formula app-wide) — no bodyweight, no sex, nothing the app
// doesn't collect. Crossing 100 means the ceiling itself moved: that IS a
// PR, and the row celebrates it. LOAD is Foster's session-RPE internal
// load, Σ reps × RPE — comparable across lifters because it measures
// effort, not iron.
enum SessionScoreboard {

    struct Row: Equatable, Identifiable {
        let userID: UUID
        let sets: Int
        /// Σ reps × RPE over today's non-penalty sets (sets without an
        /// RPE contribute nothing — never invented).
        let load: Int
        /// Best today-vs-ceiling percentage (100 = matched best ever);
        /// nil = no pre-session baseline for anything lifted today — the
        /// honest cold-start dash, never a fake number.
        let pctSelf: Int?
        var ceilingBroken: Bool { (pctSelf ?? 0) > 100 }
        var id: UUID { userID }
    }

    /// Best PRE-SESSION est-1RM per exercise from a lifter's history — the
    /// ceiling. `excludingSessionID` keeps today's own sets out of the
    /// baseline: folding them in would cap % SELF at 100 by construction
    /// and silently erase every ceiling-broken moment.
    static func baseline(history: [SetLog], excludingSessionID: UUID) -> [UUID: Decimal] {
        var best: [UUID: Decimal] = [:]
        for log in history where log.sessionID != excludingSessionID
            && !log.isFailed && !log.isPenalty {
            guard let w = log.weight, w > 0, let reps = log.reps, reps > 0 else { continue }
            let e = StatMath.estimatedOneRepMax(weight: w, reps: reps)
            if e > (best[log.exerciseID] ?? 0) { best[log.exerciseID] = e }
        }
        return best
    }

    /// Ranked rows: % SELF descending, baseline-less rows after ranked
    /// ones, ties broken by sets then load.
    static func rows(
        participants: [UUID],
        sessionSets: [SetLog],
        baselines: [UUID: [UUID: Decimal]]
    ) -> [Row] {
        let byUser = Dictionary(grouping: sessionSets.filter { !$0.isPenalty },
                                by: \.userID)
        let rows = participants.map { userID -> Row in
            let sets = byUser[userID] ?? []
            let load = sets.reduce(0) { sum, log in
                guard let reps = log.reps, let rpe = log.rpe else { return sum }
                return sum + reps * NSDecimalNumber(decimal: rpe).intValue
            }
            var bestPct: Int? = nil
            if let ceilings = baselines[userID] {
                for log in sets where !log.isFailed {
                    guard let w = log.weight, w > 0, let reps = log.reps, reps > 0,
                          let ceiling = ceilings[log.exerciseID], ceiling > 0 else { continue }
                    let e = StatMath.estimatedOneRepMax(weight: w, reps: reps)
                    let pct = wholePercent(e, of: ceiling)
                    if pct > (bestPct ?? Int.min) { bestPct = pct }
                }
            }
            return Row(userID: userID, sets: sets.count, load: load, pctSelf: bestPct)
        }
        return rows.sorted { a, b in
            switch (a.pctSelf, b.pctSelf) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if a.sets != b.sets { return a.sets > b.sets }
                return a.load > b.load
            }
        }
    }

    /// `numerator / denominator` as a whole percent, rounded DOWN (the
    /// board never overstates an achievement: 100 means the ceiling was
    /// genuinely matched, 101 genuinely beaten).
    ///
    /// The Decimal must be rounded to an integral value BEFORE the
    /// NSDecimalNumber conversion: division like 275/247.5 yields a
    /// repeating decimal whose 38-digit mantissa overflows
    /// `NSDecimalNumber.intValue` and returns 0 (caught by
    /// testCeilingBrokenAbove100 on CI run 30603130193 — every
    /// pipeline-vs-pipeline assertion sailed right past it).
    private static func wholePercent(_ numerator: Decimal, of denominator: Decimal) -> Int {
        var raw = numerator / denominator * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .down)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
