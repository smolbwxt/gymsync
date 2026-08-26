import Foundation

// MARK: - TrainingRule
//
// A durable, athlete-authored constraint that outlives a block: "pulls
// before arms", "keep Saturdays light", "never overhead barbell".
//
// These are rows rather than a profile string for two reasons the schema
// comment records: Coach needs to CITE one, and the athlete needs to
// RETIRE one. A newline-joined blob does neither.
/// What an athlete MEANT by a rule, and - separately - whether THIS
/// BUILD of the generator can act on it.
///
/// The registry of Coach's rule-shaped capabilities. Adding a lever means
/// adding a case here and wiring `apply` at the one call site; every rule
/// ever recorded with that intent becomes live at once, including rules
/// typed long before the lever existed. That is why buildability lives
/// here and not in a database column - it is a property of the app, not
/// of the athlete's sentence.
///
/// Owner 2026-08-26: "we should have unfulfilled request log that we then
/// accumulate parts and upgrade the generator to account for in the
/// future."
enum RuleIntent: String, Codable, CaseIterable, Sendable {
    /// "superset every set with push-ups" - pair a named lift onto every
    /// working slot.
    case pairWith = "pair_with"
    /// "never overhead barbell" - keep a movement out of selection.
    case avoid
    /// "pulls before arms" - order two muscle groups within a day.
    case orderBefore = "order_before"
    /// "keep Saturdays light" - a scheduling wish, not a generator one.
    case lightDay = "light_day"
    /// Heard, not understood. The honest default, and the most useful
    /// value in the column: a pile of these is the queue of levers worth
    /// building next.
    case unknown

    /// Can the generator in THIS build act on it?
    ///
    /// Deliberately exhaustive rather than defaulting to false, so adding
    /// a case forces a decision here instead of silently landing in the
    /// unbuildable pile.
    var isBuildable: Bool {
        switch self {
        case .pairWith: return true
        case .avoid: return true
        // No lever yet. Both are real asks with no substrate: ordering
        // needs new day-assembly logic, and a light day belongs to the
        // scheduler rather than the generator.
        case .orderBefore, .lightDay, .unknown: return false
        }
    }

    /// How Coach describes the rule back to the athlete before building
    /// it. The confirmation step exists because a misread rule is worse
    /// than an unread one - it silently changes their training.
    func reading(slots: [String: String]) -> String {
        let what = slots["exercise_name"] ?? slots["muscle"] ?? "that"
        switch self {
        case .pairWith:   return "Pair \(what) with every lift."
        case .avoid:      return "Keep \(what) out of your program."
        case .orderBefore:
            let after = slots["after_muscle"] ?? "the other"
            return "Train \(what) before \(after)."
        case .lightDay:   return "Keep \(what) light."
        case .unknown:    return "I could not work out what to change."
        }
    }
}

struct TrainingRule: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let rule: String
    /// The structured reading, confirmed by the athlete. Defaults to
    /// `.unknown` so a rule stored before classification existed still
    /// decodes - and correctly reports itself as not yet buildable.
    var intent: RuleIntent = .unknown
    /// Parameters for the intent. Free-form because each intent wants
    /// different slots and a new one should not need a migration.
    var slots: [String: String]? = nil
    /// When a generated block last acted on this rule. nil means it is
    /// still waiting: either no lever exists, or one now does and the
    /// athlete has not rebuilt since. Drives the "Coach can do this now"
    /// notice, the mirror of "the research came back".
    var appliedAt: Date? = nil
    /// Did the athlete agree with how Coach read this rule? A lever fires
    /// only for a confirmed reading - a misread rule silently changes
    /// training nobody asked to change, which is worse than not acting.
    var confirmed: Bool = false
    /// consult | chat | manual — where it came from, so Coach knows how
    /// freely it may challenge it. The same doctrine FieldProvenance
    /// encodes for profile fields.
    var source: String = "consult"
    var active: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, rule, source, active, intent, slots, confirmed
        case appliedAt = "applied_at"
    }

    /// Waiting on the generator: Coach can build this now, and the block
    /// on the bar predates the lever. The athlete is told to rebuild.
    var isWaitingToBeBuilt: Bool {
        intent.isBuildable && confirmed && appliedAt == nil
    }

    /// Coach has a reading and has not been told whether it is right.
    var needsConfirmation: Bool { intent != .unknown && !confirmed }
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
                .select("id, rule, source, active, intent, slots, confirmed, applied_at")
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
                    intent: RuleIntent = .unknown,
                    slots: [String: String]? = nil,
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
            let intent: String
            let slots: [String: String]?
        }
        do {
            try await SupabaseService.shared.client
                .from("training_rules")
                .insert(Insert(user_id: userID, rule: trimmed, source: source,
                               intent: intent.rawValue, slots: slots))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Record the athlete's verdict on Coach's reading.
    ///
    /// A rejected reading drops to `.unknown` rather than being deleted:
    /// they still asked for something, it still counts in the queue of
    /// levers worth building, and Coach still owes them an answer about
    /// it. Only the misreading goes away.
    static func setConfirmed(_ id: UUID, _ agreed: Bool) async {
        let client = SupabaseService.shared.client
        if agreed {
            struct Yes: Encodable { let confirmed: Bool }
            _ = try? await client.from("training_rules")
                .update(Yes(confirmed: true))
                .eq("id", value: id).execute()
        } else {
            // Both, together: the reading was wrong, so it must not sit
            // there looking confirmable, and it must stop being a lever
            // candidate. Two updates could leave the pair inconsistent.
            struct No: Encodable { let confirmed: Bool; let intent: String }
            _ = try? await client.from("training_rules")
                .update(No(confirmed: false, intent: RuleIntent.unknown.rawValue))
                .eq("id", value: id).execute()
        }
    }

    /// Stamp the rules a build actually acted on.
    ///
    /// Called after a program is written, with the ids of the rules whose
    /// levers were pulled. Until a rule is stamped it reads as waiting -
    /// which is what lets Coach say "I can do this now" when a lever
    /// ships for something the athlete asked for months ago.
    static func markApplied(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        struct Update: Encodable { let applied_at: Date }
        _ = try? await SupabaseService.shared.client
            .from("training_rules")
            .update(Update(applied_at: .now))
            .in("id", values: ids.map(\.uuidString))
            .execute()
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
