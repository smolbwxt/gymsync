import Foundation

// MARK: - BlockProgression
//
// Session-to-session progression for one lift — the layer above
// `SetProgression` (which only prefills the next set within a session).
// This is what advances an athlete through a block: double progression
// through the rep range, a fast fatigue signal that proposes a deload, and
// a slow true-stall detector that says the PROGRAM needs to change.
//
// Rules are corpus-derived (educational-fitness deep read, progression
// pass, 2026-08; per-channel consensus):
// - Double progression (4 channels): add reps within the range; once the
//   working sets top the range with technique intact, add load and reset
//   reps to the bottom. Isolations advance by the smallest increment — a
//   plate jump is a huge relative step on a lateral raise (3DMJ).
// - Fatigue deload (RP): underperforming the rep floor two sessions
//   running means fatigue caught up — cut ~10% and rebuild. Consumes
//   `GeneratorScience.noviceStallSessions` / `noviceStallDeloadPercent`.
// - True stall (Barbell Medicine): only ~3+ weeks with no measurable
//   progress marks a lift as genuinely stalled; the response is a
//   programming change (swap via the substitution graph, volume change),
//   not another load tweak. Consumes `GeneratorScience.trueStallDays`.
//   Progress is measured by e1RM, not raw reps — rep counts are noisy when
//   loads vary between sessions (BBM's matched-comparison warning).
//
// Authority rails (owner 2026-08-20):
// - Advances (load/reps) apply directly, surfaced as a compact note with
//   a reason. The athlete sees every change; Coach never edits silently.
// - A deload is only ever PROPOSED — `.proposeDeload` requires explicit
//   athlete confirmation before any number changes. The 2026-08-01 rule
//   ("the app never volunteers a deload") still governs the within-session
//   prefill; across sessions Coach may now ask, never act.
//
// Reads `SetLog.completedReps`, never raw reps, so the failure doctrine
// (a failed set's last rep doesn't count; a prescribed failure set is the
// assignment fulfilled) holds here automatically. Loaded lifts only:
// bodyweight progressions are a different animal (reps/leverage, not
// load steps) and are out of scope for this engine.
enum BlockProgression {

    /// Compact-note-plus-reason, per the owner's visibility decision:
    /// `summary` renders inline in the session ("+5 lb — topped the rep
    /// range"); `reason` is the expandable why.
    struct CoachNote: Equatable, Sendable {
        let summary: String
        let reason: String
    }

    enum Decision: Equatable, Sendable {
        /// Topped the range — new working load, reps reset to the floor.
        case advanceLoad(toPounds: Decimal, note: CoachNote)
        /// Inside the range — aim for `target` reps next session.
        case advanceReps(target: Int, note: CoachNote)
        /// Nothing to change (insufficient data, or the athlete already
        /// adjusted on their own).
        case hold(note: CoachNote?)
        /// Fatigue signal fired. REQUIRES athlete confirmation — the UI
        /// must present accept/dismiss and change nothing until accepted.
        case proposeDeload(toPounds: Decimal, note: CoachNote)
        /// True stall — a load tweak won't fix it; surface programming
        /// options (exercise swap, volume change).
        case flagStall(note: CoachNote)
        /// Early fatigue warning (diagnostics pass, BBM): the same load and
        /// reps are costing more RPE session over session — fatigue is
        /// accumulating BEFORE performance drops. Numbers unchanged; the
        /// note is the whole intervention.
        case warnFatigue(note: CoachNote)
    }

    /// One training session's evidence for this lift.
    private struct SessionSummary {
        let date: Date
        let topLoad: Decimal
        /// Weakest / strongest completed reps among WORKING sets (>= 90%
        /// of the session's top load — the conventional warmup cutoff, so
        /// a 45 lb warmup can't veto a topped-out range).
        let minRepsAtWork: Int
        let maxRepsAtWork: Int
        let bestE1RM: Decimal
        /// Mean logged RPE across working sets — nil when none carried RPE.
        let avgWorkRPE: Decimal?
    }

    /// Decide what changes for this lift next session.
    ///
    /// - Parameters:
    ///   - history: this lift's set logs, any order; grouped by session
    ///     internally. Pass a bounded window (e.g. last 60 days).
    ///   - repsLow/repsHigh: the prescribed rep range (double-progression
    ///     primitives on `RoutineExercise`).
    ///   - lastSetToFailure: prescription ends in a to-failure set — that
    ///     set is the assignment fulfilled and never a stall signal, so it
    ///     is excluded from rep-target checks.
    static func decide(
        history: [SetLog],
        repsLow: Int,
        repsHigh: Int,
        isLowerBody: Bool,
        isIsolation: Bool,
        lastSetToFailure: Bool = false,
        unit: WeightUnit = .lbs
    ) -> Decision {
        guard repsHigh >= repsLow, repsLow > 0 else { return .hold(note: nil) }
        let sessions = summarize(history, lastSetToFailure: lastSetToFailure)
        guard let latest = sessions.first else { return .hold(note: nil) }

        // 1 — Fatigue deload (fast signal). Both recent sessions missed the
        // rep floor even on their best set, at non-decreasing load. If the
        // athlete already cut load themselves, they self-deloaded — hold
        // rather than propose a second cut.
        let window = GeneratorScience.noviceStallSessions
        if sessions.count >= window {
            let recent = Array(sessions.prefix(window))
            let allMissedFloor = recent.allSatisfy { $0.maxRepsAtWork < repsLow }
            if allMissedFloor {
                let nonDecreasing = latest.topLoad >= recent.last!.topLoad
                guard nonDecreasing else {
                    return .hold(note: CoachNote(
                        summary: "Holding — you already reduced the load",
                        reason: "Recent sessions came in under the \(repsLow)-rep floor, but you've cut the weight yourself. Rebuild from here; no further change suggested."))
                }
                let deloaded = deloadPounds(from: latest.topLoad, unit: unit)
                return .proposeDeload(toPounds: deloaded, note: CoachNote(
                    summary: "Under the rep floor \(window) sessions running — deload ~\(Int(GeneratorScience.noviceStallDeloadPercent))%?",
                    reason: "Your best sets fell short of \(repsLow) reps \(window) sessions in a row at the same or heavier load — the classic sign fatigue has caught up, not that strength is gone. Dropping about \(Int(GeneratorScience.noviceStallDeloadPercent))% and rebuilding usually clears it. Your call — nothing changes unless you accept."))
            }
        }

        // 2 — True stall (slow signal): no e1RM best in `trueStallDays`
        // despite 3+ sessions since. Only checked when the fast signal
        // didn't fire — fatigue explains-away apparent stalls.
        if let bestSession = sessions.max(by: { $0.bestE1RM < $1.bestE1RM }),
           bestSession.date < latest.date {
            let sessionsSinceBest = sessions.filter { $0.date > bestSession.date }.count
            let daysSinceBest = latest.date.timeIntervalSince(bestSession.date) / 86_400
            if sessionsSinceBest >= 3, daysSinceBest >= Double(GeneratorScience.trueStallDays) {
                return .flagStall(note: CoachNote(
                    summary: "No progress on this lift in \(Int(daysSinceBest)) days",
                    reason: "Your estimated 1RM hasn't improved across \(sessionsSinceBest) sessions over \(Int(daysSinceBest)) days. That's past the point where a load tweak fixes it — worth considering a variation swap or a volume change for this lift."))
            }
        }

        // 3 — Double progression: every working set topped the range → add
        // load, reps reset to the floor.
        if latest.minRepsAtWork >= repsHigh {
            let newLoad: Decimal
            if isIsolation {
                // Smallest loadable step — a percent jump is too coarse
                // relative to isolation loads.
                let increment = unit.displayIncrement
                let unitLoad = Units.fromPounds(latest.topLoad, to: unit)
                newLoad = Units.toPounds(
                    Units.roundToIncrement(unitLoad + increment, step: increment),
                    from: unit)
            } else {
                newLoad = SetProgression.steppedPounds(
                    fromPounds: latest.topLoad, isLowerBody: isLowerBody, unit: unit)
            }
            return .advanceLoad(toPounds: newLoad, note: CoachNote(
                summary: "Load up — you topped the rep range",
                reason: "Every working set hit \(repsHigh)+ reps, the top of the \(repsLow)-\(repsHigh) range. Time to add weight and build back up from \(repsLow)."))
        }

        // 4 — Early fatigue warning (diagnostics pass, BBM): the same load
        // costing strictly more RPE across three sessions with no rep gain
        // means fatigue is accumulating BEFORE performance drops. Checked
        // only after the advance gate — RPE creep alongside actual progress
        // is just effort accumulating normally. Matched load is required
        // (BBM again): RPE across different loads compares nothing.
        if sessions.count >= 3 {
            let recent3 = Array(sessions.prefix(3))       // newest first
            let rpes = recent3.compactMap(\.avgWorkRPE)
            if rpes.count == 3,
               recent3.allSatisfy({ $0.topLoad == latest.topLoad }),
               rpes[0] > rpes[1], rpes[1] > rpes[2],      // strictly rising
               rpes[0] - rpes[2] >= 1,
               recent3.first!.minRepsAtWork <= recent3.last!.minRepsAtWork {
                return .warnFatigue(note: CoachNote(
                    summary: "Same weight is costing more effort each session",
                    reason: "Your RPE at this load has climbed \(rpes[2])→\(rpes[0]) over three sessions without the reps improving — fatigue is stacking up before it shows in performance. An easier session or an extra rest day now usually beats grinding into a stall. Nothing changed; just a heads-up."))
            }
        }

        // 5 — Inside the range: chase one more rep on the weakest working
        // set, never past the ceiling and never below the floor.
        let target = max(repsLow, min(latest.minRepsAtWork + 1, repsHigh))
        return .advanceReps(target: target, note: CoachNote(
            summary: "Aim for \(target) reps this session",
            reason: "Your weakest working set last time was \(latest.minRepsAtWork) reps in a \(repsLow)-\(repsHigh) range. One more rep before more weight — load comes when every set tops the range."))
    }

    // MARK: - Internals

    private static func summarize(_ history: [SetLog],
                                  lastSetToFailure: Bool) -> [SessionSummary] {
        let bySession = Dictionary(grouping: history, by: \.sessionID)
        var out: [SessionSummary] = []
        for (_, rawLogs) in bySession {
            var logs = rawLogs.sorted { $0.setIndex < $1.setIndex }
            // A prescribed to-failure finisher is the assignment fulfilled,
            // never evidence against the rep target.
            if lastSetToFailure, !logs.isEmpty { logs.removeLast() }
            let qualifying = logs.compactMap { log -> (reps: Int, weight: Decimal, date: Date, rpe: Decimal?)? in
                guard !log.isPenalty,
                      let reps = log.completedReps,
                      let weight = log.weight, weight > 0 else { return nil }
                return (reps, weight, log.loggedAt, log.rpe)
            }
            guard let top = qualifying.map(\.weight).max() else { continue }
            // Exact decimal arithmetic — Decimal(0.9) via a Double literal
            // is not exactly 0.9 and would misclassify boundary loads.
            let working = qualifying.filter { $0.weight >= top * 9 / 10 }
            guard !working.isEmpty else { continue }
            let e1rm = qualifying
                .map { StatMath.estimatedOneRepMax(weight: $0.weight, reps: $0.reps) }
                .max() ?? 0
            let rpes = working.compactMap(\.rpe)
            out.append(SessionSummary(
                date: qualifying.map(\.date).max()!,
                topLoad: top,
                minRepsAtWork: working.map(\.reps).min()!,
                maxRepsAtWork: working.map(\.reps).max()!,
                bestE1RM: e1rm,
                avgWorkRPE: rpes.isEmpty ? nil
                    : rpes.reduce(0, +) / Decimal(rpes.count)))
        }
        return out.sorted { $0.date > $1.date }   // newest first
    }

    private static func deloadPounds(from pounds: Decimal, unit: WeightUnit) -> Decimal {
        // (100 - percent) / 100 in exact Decimal — a Double-literal factor
        // (0.9) would land loads a hair off the increment grid.
        let keep = Decimal(100 - Int(GeneratorScience.noviceStallDeloadPercent))
        let increment = unit.displayIncrement
        let unitLoad = Units.fromPounds(pounds, to: unit) * keep / 100
        return Units.toPounds(Units.roundToIncrement(unitLoad, step: increment), from: unit)
    }
}
