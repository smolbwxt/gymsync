import Foundation

// MARK: - DriftDetector
//
// The profile says one thing; the logbook says another. Drift is a signal
// to ASK, never to silently override (design spec section 8: provenance
// gates challenges — stated goals only get probed with evidence, and the
// probe cadence is the owner's ~2 weeks, triggered by drift rather than
// the calendar).
//
// Pure over logs; the caller decides where a probe renders. Every probe
// is phrased as an OFFER — "want a plan that fits?" — because the
// athlete's answer updates the profile with provenance `confirmed`,
// which ends the probing on that field.

enum DriftDetector {

    struct Signal: Equatable, Sendable {
        /// adherence_gap | rep_style_gap | conditioning_skipped
        let kind: String
        /// The evidence, in plain sentences — shown with the probe so
        /// the athlete sees WHY Coach is asking.
        let evidence: String
        /// The question Coach asks. An offer, never a verdict.
        let probe: String
    }

    /// - Parameters:
    ///   - logs: recent set logs across all exercises (bounded window,
    ///     e.g. 28 days).
    ///   - windowWeeks: how many weeks `logs` spans.
    ///   - lastProbeDate: when Coach last asked anything — the cooldown
    ///     (GeneratorScience.driftProbeCooldownDays) suppresses nagging.
    static func detect(profile: TrainingProfile,
                       logs: [SetLog],
                       windowWeeks: Double,
                       lastProbeDate: Date?,
                       now: Date = .now) -> [Signal] {
        // Cooldown first: silence inside it, whatever the evidence.
        if let last = lastProbeDate,
           now.timeIntervalSince(last) <
               Double(GeneratorScience.driftProbeCooldownDays) * 86_400 {
            return []
        }
        guard windowWeeks >= 2, !logs.isEmpty else { return [] }
        var signals: [Signal] = []

        // 1 — Adherence gap: stated days/week vs actual, sustained.
        let sessionsPerWeek = Double(Set(logs.map(\.sessionID)).count) / windowWeeks
        if sessionsPerWeek < 0.6 * Double(profile.daysPerWeek) {
            let actual = String(format: "%.1f", sessionsPerWeek)
            signals.append(Signal(
                kind: "adherence_gap",
                evidence: "The plan schedules \(profile.daysPerWeek) days a week; the last \(Int(windowWeeks)) weeks averaged \(actual).",
                probe: "Life happens — want a \(max(1, Int(sessionsPerWeek.rounded())))-day plan that actually fits your week? A plan you complete beats a plan you admire."))
        }

        // 2 — Rep-style gap: the dominant goal implies a rep world the
        // logbook contradicts. Judged on qualifying working sets only.
        let reps = logs.compactMap { log -> Int? in
            guard !log.isPenalty, let r = log.completedReps,
                  let w = log.weight, w > 0 else { return nil }
            return r
        }.sorted()
        if reps.count >= 20 {
            let median = reps[reps.count / 2]
            if profile.dominantGoal == .hypertrophy, median <= 5 {
                signals.append(Signal(
                    kind: "rep_style_gap",
                    evidence: "Your goal is hypertrophy, but your median working set is \(median) reps — heavy-single territory.",
                    probe: "You train like a strength athlete. Want to make strength the primary goal, or keep hypertrophy and let the plan pull you back toward its rep ranges?"))
            } else if profile.dominantGoal == .maxStrength, median >= 12 {
                signals.append(Signal(
                    kind: "rep_style_gap",
                    evidence: "Your goal is strength, but your median working set is \(median) reps — pump territory.",
                    probe: "You train like a physique athlete. Switch the primary goal to hypertrophy, or keep strength and commit to the heavy work?"))
            }
        }
        return signals
    }

    /// The on-ramp is a RAMP (audit 2026-08-20): a novice who completes a
    /// block with solid adherence has EARNED the technical lifts — the
    /// probe offers graduation, and a confirmed yes advances trainingAge,
    /// which raises the complexity allowance, unfloors the reps, and opens
    /// the intensity ceiling. Offered, never imposed; the athlete's answer
    /// commits with provenance `confirmed`.
    static func graduationSignal(profile: TrainingProfile,
                                 blockOutcome: BlockReview.Outcome) -> Signal? {
        guard profile.trainingAge == .novice,
              blockOutcome.adherence >= 0.75 else { return nil }
        return Signal(
            kind: "graduation",
            evidence: "Block complete at \(Int(blockOutcome.adherence * 100))% adherence — the consistency a first block is for.",
            probe: "Solid month of showing up. Ready to graduate to the barbell versions and a bit more weight, or happy with the current groove for another block?")
    }
}

// MARK: - SchedulePlanner
//
// Coach owns the calendar (longitudinal spec 3d): given how many days a
// week the plan runs, place the sessions with maximum recovery spacing —
// the 48-hour law the generator already reasons about, applied to actual
// dates. Pure date math; the booking write is the UI pass's job.

enum SchedulePlanner {

    /// Weekday OFFSETS from the week's anchor day, by training days per
    /// week — the classic maximum-spacing patterns (3 days -> Mon/Wed/Fri
    /// shape). Deterministic; no calendar cleverness.
    static let spacingOffsets: [Int: [Int]] = [
        1: [0],
        2: [0, 3],
        3: [0, 2, 4],
        4: [0, 1, 3, 4],
        5: [0, 1, 2, 4, 5],
        6: [0, 1, 2, 3, 4, 5],
        7: [0, 1, 2, 3, 4, 5, 6],
    ]

    /// Session dates for a whole block. `anchor` is day 1 (the athlete's
    /// chosen start); each subsequent week repeats the spacing pattern.
    static func sessionDates(daysPerWeek: Int, weeks: Int, anchor: Date,
                             calendar: Calendar = .current) -> [Date] {
        let days = max(1, min(7, daysPerWeek))
        let offsets = spacingOffsets[days] ?? [0]
        var out: [Date] = []
        for week in 0..<max(1, weeks) {
            for offset in offsets {
                if let date = calendar.date(byAdding: .day,
                                            value: week * 7 + offset,
                                            to: anchor) {
                    out.append(date)
                }
            }
        }
        return out
    }
}
