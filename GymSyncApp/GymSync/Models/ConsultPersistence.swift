import Foundation

// MARK: - ConsultPersistence
//
// What finishing a consult WRITES, extracted so both hosts share one
// write path. CoachHomeView had the only copy; the onboarding offer
// flow needed the same and a second copy would drift — this repo's
// history is exactly that defect, twice over.
enum ConsultPersistence {

    struct Outcome {
        /// The tuned profile — the caller's screen state should adopt it.
        let profile: TrainingProfile
        /// Set when a standing rule could not be stored. Never nil in
        /// silence: if the athlete's words did not stick, they are told.
        let ruleTrouble: String?
    }

    /// Apply the consult's answers: tune the profile, persist it, and
    /// store any standing rules the FALLBACK path carried.
    ///
    /// Rules reach the loop below ONLY on devices without the on-device
    /// model: with it, the consult-close chat captures, classifies and
    /// confirms each rule at the moment it is typed, and pre-seeds the
    /// probe flag so `answers` never carries a standing_rule entry — one
    /// write path per device class, never both. Here, no model means no
    /// classification: the rule is stored honestly heard-only (.unknown,
    /// unconfirmed), reported as heard-not-built, and counted in the
    /// demand queue.
    static func apply(_ answers: ConsultAnswers,
                      to profile: TrainingProfile,
                      catalog: [Exercise],
                      userID: UUID) async -> Outcome {
        let tuned = answers.apply(to: profile, catalog: catalog)
        // Best-effort by design: a failed profile save must never cost
        // the rules below or the build the athlete is about to run.
        try? await TrainingProfileRepository.save(tuned, userID: userID)

        // The five-rep anchors. ConsultAnswers.liftAnchors parsed them
        // for months and nothing read the result - the probe asked, the
        // athlete answered, and every suggestion still seeded from
        // nothing. Merged, never wholesale: an earlier anchor survives a
        // consult that only restated one lift.
        let anchors = answers.liftAnchors
        if !anchors.isEmpty, var settings = try? await UserSettingsRepository.get() {
            var held = settings.liftAnchors ?? [:]
            for (slug, pounds) in anchors where pounds > 0 { held[slug] = pounds }
            settings.liftAnchors = held
            try? await UserSettingsRepository.upsert(settings)
        }

        // NOT `try?` on the rules. The swallowed error here is what made
        // the original defect invisible: every add() threw 23502 and
        // nobody heard it.
        var trouble: String?
        for rule in answers.standingRules {
            do {
                try await TrainingRulesRepository.add(
                    rule, source: "consult", userID: userID)
            } catch {
                trouble = ErrorMapping.map(error).errorDescription
            }
        }
        return Outcome(profile: tuned, ruleTrouble: trouble)
    }
}
