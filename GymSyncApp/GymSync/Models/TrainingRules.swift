import Foundation

// MARK: - TrainingRule
//
// A durable, athlete-authored constraint that outlives a block: "pulls
// before arms", "keep Saturdays light", "never overhead barbell".
//
// These are rows rather than a profile string for two reasons the schema
// comment records: Coach needs to CITE one, and the athlete needs to
// RETIRE one. A newline-joined blob does neither.
struct TrainingRule: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let rule: String
    /// consult | chat | manual — where it came from, so Coach knows how
    /// freely it may challenge it. The same doctrine FieldProvenance
    /// encodes for profile fields.
    var source: String = "consult"
    var active: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, rule, source, active
    }
}

/// Why a rule could not be stored. Exists so the consult can SAY so
/// rather than dropping the athlete's words on the floor.
enum TrainingRuleRejection: LocalizedError, Equatable {
    case tooLong(Int)

    var errorDescription: String? {
        switch self {
        case .tooLong(let n):
            return "That rule is \(n) characters and I can only keep 280. "
                 + "Shorten it and I'll hold on to it."
        }
    }
}

enum TrainingRulesRepository {

    /// Active rules, newest first. RLS scopes to the caller.
    static func active() async throws -> [TrainingRule] {
        do {
            return try await SupabaseService.shared.client
                .from("training_rules")
                .select("id, rule, source, active")
                .eq("active", value: true)
                .order("created_at", ascending: false)
                .execute().value
        } catch { throw ErrorMapping.map(error) }
    }

    /// Store one rule.
    ///
    /// `userID` is a parameter and not a convenience, and this is the
    /// whole reason the table sat empty from the day it shipped until
    /// 2026-08-26.
    ///
    /// `training_rules.user_id` is `uuid NOT NULL REFERENCES profiles(id)`
    /// with NO DEFAULT (migration 20260825000007:44). The Insert payload
    /// carried only `rule` and `source`, so every single call threw
    /// Postgres 23502 not-null-violation - and the one call site swallowed
    /// it with `try?`. The athlete typed a rule, the consult said nothing,
    /// and `public.training_rules` returned 0 rows forever.
    ///
    /// The house pattern was right there: HealthScreeningRepository.save
    /// takes userID explicitly and puts it in the payload. This repository
    /// was the only one in Models/ that did not.
    ///
    /// Owner 2026-08-26: "I asked if I could have each one of my sets,
    /// super set with push-ups and that request was silently ignored."
    static func add(_ rule: String, source: String = "consult",
                    userID: UUID) async throws {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        // The column's CHECK is 1...280. Refusing here rather than letting
        // Postgres reject it keeps a long paste from failing the whole
        // consult save.
        // Refusing here rather than letting Postgres reject it keeps a
        // long paste from failing the whole consult save. The caller is
        // told, so it can say so - a silent length drop is the same defect
        // as the silent insert failure above, one layer up.
        guard (1...280).contains(trimmed.count) else {
            throw TrainingRuleRejection.tooLong(trimmed.count)
        }
        struct Insert: Encodable {
            let user_id: UUID
            let rule: String
            let source: String
        }
        do {
            try await SupabaseService.shared.client
                .from("training_rules")
                .insert(Insert(user_id: userID, rule: trimmed, source: source))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Retiring, not deleting — a rule the athlete drops is still part of
    /// the record of what they once asked for.
    static func retire(_ id: UUID) async throws {
        do {
            try await SupabaseService.shared.client
                .from("training_rules")
                .update(["active": false])
                .eq("id", value: id)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
