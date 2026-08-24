import Foundation
import Supabase
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - CoachChat
//
// The dedicated Coach thread (owner 2026-08-24): one persistent
// conversation per athlete, Claude-style. The on-device model's ~4k
// window can't hold a long relationship, so the thread COMPACTS: when
// the live tail grows past the turn budget, the model writes a short
// summary of everything so far, the summary is stored, and the next
// exchange runs on a fresh session seeded with it. The athlete never
// sees a seam.

struct CoachChatMessage: Codable, Identifiable, Sendable {
    let id: UUID
    let role: String        // athlete | coach
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role, body
        case createdAt = "created_at"
    }

    var isCoach: Bool { role == "coach" }
}

enum CoachChatRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    static func recent(limit: Int = 40) async -> [CoachChatMessage] {
        guard let me = await SupabaseService.shared.currentUserID() else { return [] }
        let rows: [CoachChatMessage]? = try? await client
            .from("coach_chat_messages")
            .select("id, role, body, created_at")
            .eq("user_id", value: me.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return (rows ?? []).reversed()
    }

    @discardableResult
    static func append(role: String, body: String) async -> CoachChatMessage? {
        guard let me = await SupabaseService.shared.currentUserID() else { return nil }
        struct Insert: Encodable {
            let user_id: String
            let role: String
            let body: String
        }
        return try? await client
            .from("coach_chat_messages")
            .insert(Insert(user_id: me.uuidString, role: role, body: body))
            .select("id, role, body, created_at")
            .single()
            .execute()
            .value
    }

    struct ChatState: Codable {
        let summary: String
        let summarizedThrough: Date?
        enum CodingKeys: String, CodingKey {
            case summary
            case summarizedThrough = "summarized_through"
        }
    }

    static func state() async -> ChatState? {
        guard let me = await SupabaseService.shared.currentUserID() else { return nil }
        let rows: [ChatState]? = try? await client
            .from("coach_chat_state")
            .select("summary, summarized_through")
            .eq("user_id", value: me.uuidString)
            .execute()
            .value
        return rows?.first
    }

    static func saveState(summary: String, through: Date) async {
        guard let me = await SupabaseService.shared.currentUserID() else { return }
        struct Upsert: Encodable {
            let user_id: String
            let summary: String
            let summarized_through: Date
        }
        _ = try? await client
            .from("coach_chat_state")
            .upsert(Upsert(user_id: me.uuidString, summary: summary,
                           summarized_through: through))
            .execute()
    }

    /// The athlete's researched misses — "the research came back."
    static func researchedQuestions() async -> [String] {
        guard let me = await SupabaseService.shared.currentUserID() else { return [] }
        struct Row: Decodable { let question: String }
        let rows: [Row]? = try? await client
            .from("corpus_misses")
            .select("question")
            .eq("user_id", value: me.uuidString)
            .eq("status", value: "researched")
            .limit(3)
            .execute()
            .value
        return (rows ?? []).map(\.question)
    }
}

#if canImport(FoundationModels)
/// The live thread engine: seeds a session from the stored summary plus
/// the recent tail, answers with the full tool belt, and compacts when
/// the tail outgrows the budget.
@available(iOS 26.0, *)
@MainActor
final class CoachChatEngine {
    private var session: LanguageModelSession?
    private var turnsSinceSeed = 0
    /// Past this many live turns, the next reply also triggers a
    /// background compaction. Chosen well inside the ~4k window.
    private let compactionBudget = 12

    private let profile: TrainingProfile
    private let persona: CoachPersona?
    private let trendLookup: @Sendable (String) -> String
    private let volumeLookup: @Sendable () -> String

    init(profile: TrainingProfile, persona: CoachPersona?,
         trendLookup: @escaping @Sendable (String) -> String,
         volumeLookup: @escaping @Sendable () -> String) {
        self.profile = profile
        self.persona = persona
        self.trendLookup = trendLookup
        self.volumeLookup = volumeLookup
    }

    private func seedSession(summary: String, tail: [CoachChatMessage]) {
        var instructions = DebriefInstructions.build(persona: persona, profile: profile)
        instructions += "\n\nThis is an ONGOING relationship thread, not a one-off debrief. Keep replies chat-length (2-5 sentences) unless asked to go deep."
        if !summary.isEmpty {
            instructions += "\n\nWHAT HAS HAPPENED SO FAR (your own memory of this conversation — trust it):\n" + summary
        }
        if !tail.isEmpty {
            let rendered = tail.suffix(8).map { "\($0.isCoach ? "You" : "Athlete"): \($0.body)" }
                .joined(separator: "\n")
            instructions += "\n\nRECENT MESSAGES:\n" + rendered
        }
        session = LanguageModelSession(
            tools: [ExerciseTrendTool(lookup: trendLookup),
                    WeeklyVolumeTool(lookup: volumeLookup),
                    CorpusResearchTool(),
                    NutritionTool()],
            instructions: instructions)
        turnsSinceSeed = 0
    }

    /// Answer one athlete message; persists both sides and compacts in
    /// the background when the tail is long.
    func reply(to message: String) async throws -> String {
        if session == nil {
            let state = await CoachChatRepository.state()
            let tail = await CoachChatRepository.recent(limit: 10)
            seedSession(summary: state?.summary ?? "", tail: tail)
        }
        guard let session else { throw GymSyncError.unknown("Coach chat session unavailable") }
        let reply = try await session.respond(to: message).content
        turnsSinceSeed += 2
        if turnsSinceSeed >= compactionBudget {
            await compact()
        }
        return reply
    }

    /// Claude-style compaction: the model summarizes the thread so far;
    /// the summary is stored and the session resets seeded with it.
    private func compact() async {
        guard let session else { return }
        let prompt = "Write a compact memory note (under 150 words) of this conversation so far: the athlete's situation, decisions made, advice given, and anything you promised to follow up on. Plain prose, no preamble — this note becomes your memory when the conversation continues."
        guard let summary = try? await session.respond(to: prompt).content else { return }
        await CoachChatRepository.saveState(summary: summary, through: Date())
        seedSession(summary: summary, tail: [])
    }
}
#endif
