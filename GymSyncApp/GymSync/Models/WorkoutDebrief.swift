import Foundation

// MARK: - WorkoutDebrief
//
// The deterministic layer under BOTH debrief tiers (concept, owner
// 2026-08-20): the free post-workout card renders `headline`; the PRO
// conversation hands `corePrompt` to the on-device model as its first
// prompt. ONE builder, so the free card can never contradict what the
// coach says — the same shared-oracle property as BlockReview.
//
// Every number here is computed in Swift. The model narrates; it never
// does arithmetic — one hallucinated PR ends the relationship. Token
// budget: the core prompt targets <= ~900 tokens of the on-device
// model's ~4k window (tests pin a character ceiling); everything deeper
// arrives via tool calls whose backends live here too.

struct WorkoutDebrief: Equatable, Sendable {
    /// The free card's one-liner — experience-aware, computed, specific.
    let headline: String
    /// The PRO conversation's first prompt (the CORE payload).
    let corePrompt: String
    /// Rendered FIRST and identically under every persona and tier —
    /// never behind a model.
    let safetyNotes: [String]
}

enum DebriefBuilder {

    /// One exercise's story for the session: what was asked, what
    /// happened, what the engine decided.
    struct ExerciseReport {
        let name: String
        let prescribedSets: Int
        let repsLow: Int?
        let repsHigh: Int?
        /// This session's logged sets for the lift, in order.
        let sets: [SetLog]
        /// The engine's session-start decision, if one was shown.
        let decision: BlockProgression.Decision?
        var isSkipped: Bool { sets.isEmpty }
    }

    struct Context {
        var profile = TrainingProfile()
        /// Block position, when enrolled (week N of M, goal of the block).
        var blockWeek: Int? = nil
        var blockWeeks: Int? = nil
        var blockGoal: TrainingGoal? = nil
        /// PR strings the summary screen already computed — reused, never
        /// re-derived (PersonalRecordMath is the oracle).
        var personalRecords: [String] = []
        /// Athlete-reported flags (pain, unusual fatigue) — safety lines.
        var safetyNotes: [String] = []
        /// A drift probe waiting to be asked, if the cooldown allows.
        var pendingProbe: DriftDetector.Signal? = nil
        var sessionMinutes: Int? = nil
        /// Sessions completed this calendar week INCLUDING this one — the
        /// novice headline's raw material.
        var weekSessionCount: Int? = nil
    }

    // MARK: Build

    static func build(reports: [ExerciseReport], context: Context) -> WorkoutDebrief {
        WorkoutDebrief(
            headline: headline(reports: reports, context: context),
            corePrompt: corePrompt(reports: reports, context: context),
            safetyNotes: context.safetyNotes)
    }

    // MARK: The free card's one-liner

    /// Experience-aware selection: a novice's real win is showing up, so
    /// consistency leads; intermediate/advanced lead with the PR or the
    /// engine's advance. Always specific — "great workout!" is noise; a
    /// computed fact is a relationship.
    static func headline(reports: [ExerciseReport], context: Context) -> String {
        let done = reports.filter { !$0.isSkipped }
        let advance = reports.compactMap { report -> String? in
            if case .advanceLoad(_, let note)? = report.decision {
                return "\(report.name): \(note.summary.lowercased())"
            }
            return nil
        }.first

        switch context.profile.trainingAge {
        case .novice:
            if let count = context.weekSessionCount, count >= 2 {
                return "Session \(count) this week — consistency is the whole game right now, and you're winning it."
            }
            if let pr = context.personalRecords.first {
                return "\(pr) — and you showed up. That's the job."
            }
            return "\(done.count) exercise\(done.count == 1 ? "" : "s") done. Every session you finish is money in the bank."
        case .intermediate, .advanced:
            if let pr = context.personalRecords.first { return pr }
            if let advance { return advance.prefix(1).capitalized + String(advance.dropFirst()) }
            if let count = context.weekSessionCount, count >= 3 {
                return "Session \(count) this week — the volume is banking."
            }
            return "\(done.count) of \(reports.count) exercises done — logged and counted."
        }
    }

    // MARK: The CORE payload

    static func corePrompt(reports: [ExerciseReport], context: Context) -> String {
        var lines: [String] = ["WORKOUT DATA (computed — cite these numbers verbatim, never calculate your own):"]

        // Goals + block context — the athlete's WANTS, ranked.
        let goals = context.profile.rankedGoals.map(\.rawValue).joined(separator: " then ")
        var goalLine = "GOALS: \(goals.isEmpty ? "general training" : goals)"
        if let week = context.blockWeek, let weeks = context.blockWeeks {
            goalLine += " · block: week \(week) of \(weeks)"
            if let goal = context.blockGoal { goalLine += " (\(goal.rawValue))" }
        }
        lines.append(goalLine)

        // Safety FIRST among the facts — instructions require it be
        // delivered first, and its position here reinforces that.
        for note in context.safetyNotes { lines.append("SAFETY: \(note)") }

        // Today, per exercise: prescription -> actual -> engine decision.
        let done = reports.filter { !$0.isSkipped }
        var todayLine = "TODAY: \(done.count) of \(reports.count) exercises completed"
        if let minutes = context.sessionMinutes { todayLine += " · \(minutes) min" }
        lines.append(todayLine)
        for report in reports {
            lines.append(exerciseLine(report))
        }

        for pr in context.personalRecords { lines.append("PR: \(pr)") }
        if let probe = context.pendingProbe {
            lines.append("PENDING QUESTION (ask naturally when the moment fits): \(probe.evidence) Suggested framing: \(probe.probe)")
        }
        return lines.joined(separator: "\n")
    }

    private static func exerciseLine(_ report: ExerciseReport) -> String {
        let upper = report.name.uppercased()
        var range = ""
        if let low = report.repsLow, let high = report.repsHigh {
            range = "\(report.prescribedSets)×\(low)-\(high)"
        } else {
            range = "\(report.prescribedSets) sets"
        }
        guard !report.isSkipped else { return "\(upper): prescribed \(range) → SKIPPED" }
        let sets = report.sets.map { log -> String in
            let reps = log.completedReps.map(String.init) ?? "?"
            // .doubleValue, never .intValue: NSDecimalNumber.intValue
            // returns 0 for full-precision Decimal mantissas (CI caught
            // it printing "estimated 1RM 0 → 0 lb").
            let weight = log.weight.map { "\(Int(NSDecimalNumber(decimal: $0).doubleValue.rounded()))" } ?? "-"
            return "\(reps)@\(weight)"
        }.joined(separator: ", ")
        var line = "\(upper): prescribed \(range) → did \(sets)"
        if let decision = report.decision, let note = note(for: decision) {
            line += " · coach: \(note.summary)"
        }
        return line
    }

    private static func note(for decision: BlockProgression.Decision) -> BlockProgression.CoachNote? {
        switch decision {
        case .advanceLoad(_, let note), .advanceReps(_, let note),
             .proposeDeload(_, let note), .flagStall(let note),
             .warnFatigue(let note):
            return note
        case .hold(let note):
            return note
        }
    }

    // MARK: Tool backends (computed sentences, never raw rows)
    //
    // The conversation's tools call THESE — display-ready facts with the
    // arithmetic already done and rounded. The model is never allowed to
    // compute; it narrates.

    /// e1RM trend for one lift over its recent history, as a sentence.
    static func trendSentence(name: String, logs: [SetLog]) -> String {
        let bySession = Dictionary(grouping: logs.filter { !$0.isPenalty },
                                   by: \.sessionID)
        let sessions: [(date: Date, e1rm: Decimal)] = bySession.values.compactMap { sessionLogs in
            guard let best = WorkingWeight.bestQualifyingSet(in: sessionLogs) else { return nil }
            let date = sessionLogs.map(\.loggedAt).max() ?? .distantPast
            return (date, StatMath.estimatedOneRepMax(weight: best.weight, reps: best.reps))
        }.sorted { $0.date < $1.date }
        guard let first = sessions.first, let last = sessions.last,
              sessions.count >= 2 else {
            return "\(name): not enough logged history for a trend yet."
        }
        let firstLb = Int(NSDecimalNumber(decimal: first.e1rm).doubleValue.rounded())
        let lastLb = Int(NSDecimalNumber(decimal: last.e1rm).doubleValue.rounded())
        let days = Int(last.date.timeIntervalSince(first.date) / 86_400)
        let delta = lastLb - firstLb
        let direction = delta > 0 ? "+\(delta)" : "\(delta)"
        return "\(name): estimated 1RM \(firstLb) → \(lastLb) lb over \(max(days, 1)) days (\(direction) lb), across \(sessions.count) sessions."
    }

    /// This week's per-muscle effective sets, as a sentence.
    static func volumeSentence(tally: [String: Double]) -> String {
        guard !tally.isEmpty else { return "No lifting volume logged this week yet." }
        let parts = tally.sorted { $0.value > $1.value }.prefix(6).map {
            "\($0.key) \(String(format: "%.1f", $0.value))"
        }
        return "Effective weekly sets (1.0 primary, 0.5 secondary): " + parts.joined(separator: ", ") + "."
    }
}
