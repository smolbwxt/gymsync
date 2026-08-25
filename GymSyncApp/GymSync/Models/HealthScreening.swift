import Foundation

// MARK: - HealthScreening
//
// The stored side of HealthTriage. The triage logic could already refuse
// to program; nothing recorded that it had ever asked, which meant the
// gate was a function with no call sites and no memory — see the
// 20260825000007 migration comment.
//
// Clearance is not permanent (PAR-Q+ lapses at 12 months) and a refer-out
// is not a dead end: `clinicianCleared` is how an athlete comes back
// after the conversation Coach asked them to have.
struct HealthScreening: Codable, Equatable, Sendable {
    /// PAR-Q+ question id → answered yes. Open shape on purpose: the
    /// instrument gets revised and our schema should not have to.
    var answers: [String: Bool] = [:]
    var clearedAt: Date?
    /// pregnant | postpartum | nil. Advisory, never a block (ACOG 804).
    var lifeStage: String?
    var clinicianCleared: Bool = false

    enum CodingKeys: String, CodingKey {
        case answers
        case clearedAt = "cleared_at"
        case lifeStage = "life_stage"
        case clinicianCleared = "clinician_cleared"
    }

    var stage: HealthTriage.LifeStage? {
        switch lifeStage {
        case "pregnant":   return .pregnant
        case "postpartum": return .postpartum
        default:           return nil
        }
    }

    /// Whether the athlete must be screened before Coach will program.
    ///
    /// A clinician's clearance survives expiry deliberately: making
    /// someone re-answer the PAR-Q+ every year after their doctor already
    /// signed off would train them to click through it.
    var needsScreening: Bool {
        if clinicianCleared { return false }
        return HealthTriage.clearanceExpired(clearedAt: clearedAt)
    }

    /// Whether this screening clears the athlete to be programmed.
    ///
    /// Extracted from the repository so it can be TESTED: the rule it
    /// encodes is that a refer-out must never stamp `cleared_at`, because
    /// a 12-month clock started by a flagged answer would silently wave
    /// that athlete through on their next visit.
    var clearsTheGate: Bool {
        switch outcome() {
        case .cleared, .clearedWithAdvisory: return true
        case .referOut, .delay:              return false
        }
    }

    /// The decision, from what is stored.
    func outcome(delay: HealthTriage.DelayReason? = nil) -> HealthTriage.Outcome {
        if clinicianCleared, let stage {
            return .clearedWithAdvisory(stage.advisory)
        }
        if clinicianCleared { return .cleared }
        return HealthTriage.evaluate(answers: answers, delay: delay, stage: stage)
    }
}

enum HealthScreeningRepository {

    static func load() async throws -> HealthScreening? {
        do {
            let rows: [HealthScreening] = try await SupabaseService.shared.client
                .from("health_screenings")
                .select("answers, cleared_at, life_stage, clinician_cleared")
                .execute().value          // RLS scopes to the caller
            return rows.first
        } catch { throw ErrorMapping.map(error) }
    }

    /// Records the screening. `clearedAt` is stamped only when the
    /// outcome actually clears — a refer-out must NOT start a 12-month
    /// clock, or a flagged athlete would be silently waved through on
    /// their next visit.
    static func save(_ screening: HealthScreening, userID: UUID) async throws {
        struct Upsert: Encodable {
            let user_id: UUID
            let answers: [String: Bool]
            let cleared_at: Date?
            let life_stage: String?
            let clinician_cleared: Bool
        }
        let cleared = screening.clearsTheGate
        do {
            try await SupabaseService.shared.client
                .from("health_screenings")
                .upsert(Upsert(user_id: userID,
                               answers: screening.answers,
                               cleared_at: cleared ? (screening.clearedAt ?? Date()) : nil,
                               life_stage: screening.lifeStage,
                               clinician_cleared: screening.clinicianCleared))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
