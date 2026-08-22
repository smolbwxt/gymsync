import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - CorpusResearch
//
// Coach's research library (owner 2026-08-22): the deep-read swarms'
// distilled findings, shipped to the device so the on-device model can
// CONSULT the field instead of improvising. Retrieval is lexical and
// local (the whole corpus is ~140KB); a question the corpus can't
// answer logs a MISS — the demand queue future swarm passes are run
// against. "Send an agent to research" made asynchronous: Coach answers
// from what exists, says so honestly when nothing exists, and the gap
// becomes the next research pass.

struct CorpusFinding: Codable, Sendable {
    let area: String
    let topic: String
    let claim: String
    let basis: String
    let confidence: String

    enum CodingKeys: String, CodingKey {
        case area, topic, claim, basis, confidence
    }
}

enum CorpusResearchStore {
    private static var cached: [CorpusFinding]?
    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("corpus-findings.json")
    }

    /// The findings, from memory → disk cache → network, refreshed in
    /// the background after a disk hit so the cache tracks the table.
    static func findings() async -> [CorpusFinding] {
        if let cached { return cached }
        if let data = try? Data(contentsOf: cacheURL),
           let disk = try? JSONDecoder().decode([CorpusFinding].self, from: data),
           !disk.isEmpty {
            cached = disk
            Task { await refresh() }
            return disk
        }
        await refresh()
        return cached ?? []
    }

    @discardableResult
    static func refresh() async -> [CorpusFinding] {
        guard let rows: [CorpusFinding] = try? await SupabaseService.shared.client
            .from("corpus_findings")
            .select("area, topic, claim, basis, confidence")
            .execute()
            .value, !rows.isEmpty else { return cached ?? [] }
        cached = rows
        if let data = try? JSONEncoder().encode(rows) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return rows
    }

    /// Lexical retrieval: token overlap between the question and each
    /// finding's claim+topic, confidence-weighted. Local, instant, and
    /// good enough over 400 curated entries — embeddings can replace
    /// this without touching any caller.
    static func search(_ query: String, in findings: [CorpusFinding],
                       limit: Int = 5) -> [CorpusFinding] {
        let stop: Set<String> = ["the", "a", "an", "is", "are", "do", "does",
                                 "should", "i", "my", "for", "to", "of", "in",
                                 "on", "and", "or", "what", "how", "why", "it",
                                 "me", "with", "that", "this", "be", "at", "you"]
        let tokens = Set(query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stop.contains($0) })
        guard !tokens.isEmpty else { return [] }
        let scored: [(Double, CorpusFinding)] = findings.compactMap { finding in
            let hay = (finding.claim + " " + finding.topic + " " + finding.area).lowercased()
            var score = 0.0
            for token in tokens where hay.contains(token) { score += 1 }
            guard score > 0 else { return nil }
            score /= Double(tokens.count)
            if finding.confidence == "strong" { score += 0.15 }
            if finding.basis == "synthesis" { score += 0.1 }
            return (score, finding)
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(limit).map(\.1)
    }

    /// The relevance floor: below this, the corpus honestly has nothing
    /// and the question belongs in the miss queue.
    static let missThreshold = 0.34

    static func bestScore(_ query: String, in findings: [CorpusFinding]) -> Double {
        let top = search(query, in: findings, limit: 1)
        guard let first = top.first else { return 0 }
        let stop: Set<String> = ["the", "a", "an", "is", "are", "do", "does",
                                 "should", "i", "my", "for", "to", "of", "in",
                                 "on", "and", "or", "what", "how", "why", "it",
                                 "me", "with", "that", "this", "be", "at", "you"]
        let tokens = Set(query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stop.contains($0) })
        guard !tokens.isEmpty else { return 0 }
        let hay = (first.claim + " " + first.topic + " " + first.area).lowercased()
        let hits = tokens.filter { hay.contains($0) }.count
        return Double(hits) / Double(tokens.count)
    }

    /// Fire-and-forget miss logging — the demand queue.
    static func logMiss(_ question: String) {
        Task {
            guard let me = await SupabaseService.shared.currentUserID() else { return }
            struct Insert: Encodable {
                let user_id: String
                let question: String
            }
            _ = try? await SupabaseService.shared.client
                .from("corpus_misses")
                .insert(Insert(user_id: me.uuidString,
                               question: String(question.prefix(300))))
                .execute()
        }
    }

    /// The tool-facing answer: top findings as computed text, or the
    /// honest miss line (which also queues the research).
    static func toolAnswer(for query: String) async -> String {
        let all = await findings()
        let hits = search(query, in: all)
        guard !hits.isEmpty, bestScore(query, in: all) >= missThreshold else {
            logMiss(query)
            return "No field research on this in the library yet — it's been logged for the research queue. Answer from general coaching principles and say the deep dive is coming."
        }
        let lines = hits.map { "- [\($0.area) · \($0.confidence)] \($0.claim)" }
        return (["FIELD RESEARCH (verbatim findings from the coaching-science corpus — cite, don't recompute):"] + lines)
            .joined(separator: "\n")
    }
}

#if canImport(FoundationModels)
/// Tool: consult the coaching-research corpus for general training
/// questions (as opposed to the athlete's own numbers, which the trend
/// and volume tools carry).
@available(iOS 26.0, *)
struct CorpusResearchTool: Tool {
    let name = "fieldResearch"
    let description = "Search the coaching-science research library (distilled from the field's top educators) for what the research says about a general training question — exercise selection, programming, recovery, technique tradeoffs. Use for any question that is about training knowledge rather than the athlete's own logged numbers."

    @Generable
    struct Arguments {
        @Guide(description: "The training question or topic, e.g. 'are smith machines effective for strength'")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        await CorpusResearchStore.toolAnswer(for: arguments.query)
    }
}
#endif
