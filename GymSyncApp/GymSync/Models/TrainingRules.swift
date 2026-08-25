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

    static func add(_ rule: String, source: String = "consult") async throws {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        // The column's CHECK is 1...280. Refusing here rather than letting
        // Postgres reject it keeps a long paste from failing the whole
        // consult save.
        guard (1...280).contains(trimmed.count) else { return }
        struct Insert: Encodable {
            let rule: String
            let source: String
        }
        do {
            try await SupabaseService.shared.client
                .from("training_rules")
                .insert(Insert(rule: trimmed, source: source))
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
