import Foundation
import Supabase

// MARK: - Exercise substitution graph (20260817000001)
//
// Mined from the educational-fitness corpus (tools/youtube-research): when
// does an educator say one exercise legitimately stands in for another?
//
// Coach could previously only walk a RANKED LIST — the next-best candidate
// for a slot — which is not the same as knowing a swap. This answers the
// question a lifter actually asks mid-session: the machine is taken, my gym
// has no barbell, that hurts my shoulder — what do I do instead?
//
// Every edge carries its provenance so the UI can be honest about why a swap
// is offered, and so a thinly-sourced edge never outranks a well-sourced one.

struct ExerciseSubstitution: Decodable, Identifiable, Sendable {
    let fromSlug: String
    let toSlug: String
    /// full = genuinely interchangeable · partial = covers most of it with a
    /// tradeoff · inferior = works, but worse.
    let equivalence: String
    /// equipment · injury_pain · skill · time · preference · crowding
    let trigger: String
    let reason: String
    /// cited_study · mechanistic · experience
    let basis: String
    /// strong · moderate · hedged
    let confidence: String
    /// Independent videos asserting this swap — more sources, more trust.
    let sources: Int

    var id: String { "\(fromSlug)->\(toSlug)" }

    enum CodingKeys: String, CodingKey {
        case fromSlug = "from_slug"
        case toSlug = "to_slug"
        case equivalence, trigger, reason, basis, confidence, sources
    }

    /// Situational swaps are the ones a session UI surfaces ("it's taken",
    /// "that hurts"); `preference`/`time` edges are programming choices and
    /// rank below them.
    var isSituational: Bool {
        ["equipment", "injury_pain", "crowding"].contains(trigger)
    }

    /// Ranking key: closest equivalence first, then corroboration, then
    /// evidence quality. Deliberately deterministic — same inputs, same order.
    var rank: (Int, Int, Int) {
        let equiv = ["full": 0, "partial": 1, "inferior": 2][equivalence] ?? 3
        let basisRank = ["cited_study": 0, "mechanistic": 1, "experience": 2][basis] ?? 3
        return (equiv, -sources, basisRank)
    }
}

enum ExerciseSubstitutionRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Swaps for one exercise, best first. Globally readable by RLS.
    static func forExercise(slug: String) async throws -> [ExerciseSubstitution] {
        do {
            let rows: [ExerciseSubstitution] = try await client
                .from("exercise_substitutions")
                .select()
                .eq("from_slug", value: slug)
                .execute()
                .value
            return rows.sorted { $0.rank < $1.rank }
        } catch { throw ErrorMapping.map(error) }
    }

    /// The whole graph — small enough to hold (tens to low thousands of
    /// edges) and the generator wants it in memory during selection.
    static func all() async throws -> [ExerciseSubstitution] {
        do {
            let rows: [ExerciseSubstitution] = try await client
                .from("exercise_substitutions")
                .select()
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }
}

// MARK: - Pure graph helpers (see ExerciseSubstitutionTests)

enum SubstitutionGraph {
    /// Adjacency built once from a flat edge list.
    static func index(_ edges: [ExerciseSubstitution]) -> [String: [ExerciseSubstitution]] {
        var out: [String: [ExerciseSubstitution]] = [:]
        for edge in edges { out[edge.fromSlug, default: []].append(edge) }
        for key in out.keys { out[key]?.sort { $0.rank < $1.rank } }
        return out
    }

    /// Best available swap for `slug` given what the gym actually has.
    /// `availableSlugs` nil = everything available.
    ///
    /// Situational triggers win when the lifter is REACTING to something (a
    /// taken machine, a painful joint); otherwise closest-equivalence wins.
    static func bestSwap(for slug: String,
                         in index: [String: [ExerciseSubstitution]],
                         availableSlugs: Set<String>? = nil,
                         situationalOnly: Bool = false) -> ExerciseSubstitution? {
        let candidates = (index[slug] ?? []).filter { edge in
            if situationalOnly && !edge.isSituational { return false }
            guard let available = availableSlugs else { return true }
            return available.contains(edge.toSlug)
        }
        return candidates.first
    }
}
