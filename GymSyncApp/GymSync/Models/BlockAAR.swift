import Foundation

// MARK: - BlockAAR
//
// The after-action payload for one finished (or abandoned) block.
//
// Owner 2026-08-27: "if it's a completed program, then I should be able
// to open that up and have a conversation with coach about the
// performance... Coach would be fed a prompt of everything about that
// block, and if it was performed, the data from all of the exercises
// from that block."
//
// Same doctrine as the workout debrief: every number is COMPUTED here
// and the model narrates it — the payload tells Coach to cite, never to
// calculate. The review engine is the same one the block's own
// end-of-block settlement ran (BlockReview), so the AAR and the
// carryover can never disagree about what happened.
enum BlockAAR {

    /// Build the opener for a block's after-action thread.
    static func payload(enrollment: ProgramEnrollment,
                        userID: UUID) async -> String {
        let template = enrollment.template
        let name = template?.name ?? enrollment.templateSlug
        var lines: [String] = []

        let status: String
        if let endedAt = enrollment.endedAt {
            let weeksRun = max(0, Calendar.current.dateComponents(
                [.weekOfYear], from: enrollment.startedOn, to: endedAt).weekOfYear ?? 0)
            status = enrollment.endedReason == "completed"
                ? "completed, \(enrollment.weeks) weeks"
                : "abandoned in week \(min(weeksRun + 1, enrollment.weeks)) of \(enrollment.weeks)"
        } else {
            status = "still running, week \(ProgramMath.currentWeek(startedOn: enrollment.startedOn, weeks: enrollment.weeks)) of \(enrollment.weeks)"
        }
        lines.append("BLOCK: \(name) — \(status).")

        // The options that built it, when the block is new enough to
        // carry the frozen snapshot. Older blocks say so honestly.
        if let config = enrollment.config, !config.isEmpty {
            let rendered = config.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }.joined(separator: "; ")
            lines.append("BUILT FROM: \(rendered).")
        } else {
            lines.append("BUILT FROM: (this block predates the config snapshot — its build options were not recorded).")
        }

        // The performance data: the block's own logs, bounded to its
        // window. recentSetLogs takes `since` only; the end bound is
        // applied here so an ended block never absorbs the next block's
        // work.
        let raw = (try? await SessionRepository.recentSetLogs(
            userID: userID, since: enrollment.startedOn)) ?? []
        let cutoff = enrollment.endedAt ?? .now
        let logs = raw.filter { $0.loggedAt <= cutoff }

        guard !logs.isEmpty else {
            lines.append("PERFORMANCE: no sets were logged during this block.")
            return lines.joined(separator: "\n")
        }

        // The SAME review engine the end-of-block settlement runs — the
        // AAR and the carryover can never tell two stories.
        let prescriptions = enrollment.focus.exerciseIDs?.map {
            BlockReview.Prescription(exerciseID: $0, repsLow: 6, repsHigh: 12,
                                     isLowerBody: false)
        } ?? []
        let profile = (try? await TrainingProfileRepository.load()) ?? TrainingProfile()
        let outcome = BlockReview.analyze(
            logs: logs,
            prescriptions: prescriptions,
            plannedSessions: enrollment.weeks * max(1, profile.daysPerWeek),
            weeks: enrollment.weeks)

        let sessions = Set(logs.map(\.sessionID)).count
        lines.append("PERFORMANCE: \(sessions) sessions, \(logs.count) sets logged. Adherence \(Int((outcome.adherence * 100).rounded()))%.")

        // Main-lift strength movement across the window: first vs last
        // qualifying e1RM per focused lift.
        if let focusIDs = enrollment.focus.exerciseIDs, !focusIDs.isEmpty {
            let byExercise = Dictionary(grouping: logs, by: \.exerciseID)
            // Names, not ids - the model cites these lines to the athlete.
            let names = Dictionary(uniqueKeysWithValues:
                ((try? await ExerciseRepository.fetchAll()) ?? [])
                    .map { ($0.id, $0.name) })
            for id in focusIDs.prefix(6) {
                guard let history = byExercise[id], history.count >= 2 else { continue }
                let sorted = history.sorted { $0.loggedAt < $1.loggedAt }
                let half = sorted.count / 2
                guard let early = WorkingWeight.bestQualifyingSet(in: Array(sorted.prefix(max(1, half)))),
                      let late = WorkingWeight.bestQualifyingSet(in: Array(sorted.suffix(max(1, half))))
                else { continue }
                let e1 = StatMath.estimatedOneRepMax(weight: early.weight, reps: early.reps)
                let e2 = StatMath.estimatedOneRepMax(weight: late.weight, reps: late.reps)
                let delta = NSDecimalNumber(decimal: e2 - e1).doubleValue
                let sign = delta >= 0 ? "+" : "\u{2212}"
                lines.append("\(names[id] ?? "Lift"): e1RM \(Int(NSDecimalNumber(decimal: e1).doubleValue)) → \(Int(NSDecimalNumber(decimal: e2).doubleValue)) (\(sign)\(Int(abs(delta)))).")
            }
        }
        if !outcome.strugglingLiftIDs.isEmpty {
            lines.append("STRUGGLING: \(outcome.strugglingLiftIDs.count) lift(s) flagged by the block review.")
        }
        if !outcome.abandonedExerciseIDs.isEmpty {
            lines.append("SKIPPED: \(outcome.abandonedExerciseIDs.count) prescribed exercise(s) were never trained.")
        }

        lines.append("Talk the athlete through what this says — cite these numbers verbatim, never calculate your own. Ask what they want the NEXT block to do differently.")
        return lines.joined(separator: "\n")
    }
}
