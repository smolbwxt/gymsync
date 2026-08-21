import Foundation

// MARK: - CoachLifecycle
//
// The Phase 4 machinery's driver (2026-08-21): BlockReview, BlockPlanner,
// and DriftDetector were tested libraries with no callers — the service-
// level dead knob. This is the caller.
//
// One entry point, run when the Coach surface appears: detect a finished
// block, run the review over what actually happened, fold the outcomes
// into the profile's carryover (the relationship's memory), close the
// enrollment, and hand the UI a completion summary to show. Everything
// best-effort — a failed step degrades to "no completion detected",
// never a broken wizard.

enum CoachLifecycle {

    struct BlockCompletion {
        let outcome: BlockReview.Outcome
        /// Names for the banner, resolved best-effort.
        let strugglingNames: [String]
        /// Non-nil when the novice earned the graduation offer.
        let graduation: DriftDetector.Signal?
    }

    /// Detect and settle a finished block. Returns nil when no block just
    /// ended (the overwhelmingly common case).
    static func checkBlockEnd() async -> BlockCompletion? {
        guard let enrollment = try? await ProgramRepository.active(),
              enrollment.endedAt == nil else { return nil }
        let daysIn = Date.now.timeIntervalSince(enrollment.startedOn) / 86_400
        guard daysIn >= Double(enrollment.weeks * 7) else { return nil }

        guard let userID = await SupabaseService.shared.currentUserID() else { return nil }
        var profile = (try? await TrainingProfileRepository.load()) ?? TrainingProfile()

        // The block's logs, reviewed by the SAME engine the sessions ran.
        let logs = (try? await SessionRepository.recentSetLogs(
            userID: userID, since: enrollment.startedOn)) ?? []
        let prescriptions = enrollment.focus.exerciseIDs?.map {
            BlockReview.Prescription(exerciseID: $0, repsLow: 6, repsHigh: 12,
                                     isLowerBody: false)
        } ?? []
        let outcome = BlockReview.analyze(
            logs: logs,
            prescriptions: prescriptions,
            plannedSessions: enrollment.weeks * max(1, profile.daysPerWeek),
            weeks: enrollment.weeks)

        // Fold into the relationship's memory.
        var carryover = profile.carryover ?? TrainingProfile.Carryover()
        carryover.deprioritizedExerciseIDs = Array(outcome.abandonedExerciseIDs)
        carryover.strugglingLiftIDs = Array(outcome.strugglingLiftIDs)
        carryover.suggestedDaysPerWeek = outcome.suggestedDaysPerWeek
        carryover.lastAdherence = outcome.adherence
        let graduation = DriftDetector.graduationSignal(profile: profile,
                                                       blockOutcome: outcome)
        carryover.pendingGraduation = graduation != nil
        profile.carryover = carryover
        try? await TrainingProfileRepository.save(profile, userID: userID)

        // The block is settled — close it so the next CREATE starts clean.
        try? await ProgramRepository.end(enrollmentID: enrollment.id,
                                         reason: "completed")

        let names = await liftNames(for: Array(outcome.strugglingLiftIDs.prefix(3)))
        return BlockCompletion(outcome: outcome, strugglingNames: names,
                               graduation: graduation)
    }

    private static func liftNames(for ids: [UUID]) async -> [String] {
        guard !ids.isEmpty,
              let all = try? await ExerciseRepository.fetchAll() else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.name) })
        return ids.compactMap { byID[$0] }
    }
}
