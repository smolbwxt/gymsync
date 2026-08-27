import Foundation
import Supabase
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - CoachChat
//
// Coach conversations, Claude-style (owner 2026-08-24: "threads, not
// one long persistent chat" — go to a thread, continue it, back out,
// jump into a different one). Each thread carries its own compaction
// state: when its live tail outgrows the model's window, the model
// writes a memory note onto the THREAD row and the session reseeds
// from it. The athlete never sees a seam.

struct CoachChatThread: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var summary: String
    var summarizedThrough: Date?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, summary
        case summarizedThrough = "summarized_through"
        case updatedAt = "updated_at"
    }
}

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

    // MARK: Threads

    static func threads() async -> [CoachChatThread] {
        guard let me = await SupabaseService.shared.currentUserID() else { return [] }
        let rows: [CoachChatThread]? = try? await client
            .from("coach_chat_threads")
            .select("id, title, summary, summarized_through, updated_at")
            .eq("user_id", value: me.uuidString)
            .order("updated_at", ascending: false)
            .execute()
            .value
        return rows ?? []
    }

    static func createThread(title: String = "New thread") async -> CoachChatThread? {
        guard let me = await SupabaseService.shared.currentUserID() else { return nil }
        struct Insert: Encodable {
            let user_id: String
            let title: String
        }
        return try? await client
            .from("coach_chat_threads")
            .insert(Insert(user_id: me.uuidString, title: title))
            .select("id, title, summary, summarized_through, updated_at")
            .single()
            .execute()
            .value
    }

    /// First athlete message names a default-titled thread — the Claude
    /// idiom: the opening line IS the title until someone renames it.
    static func autoTitle(threadID: UUID, from firstMessage: String) async {
        let title = String(firstMessage.prefix(48))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        _ = try? await client
            .from("coach_chat_threads")
            .update(["title": title])
            .eq("id", value: threadID.uuidString)
            .eq("title", value: "New thread")
            .execute()
    }

    static func deleteThread(id: UUID) async {
        _ = try? await client
            .from("coach_chat_threads")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: Messages

    static func recent(threadID: UUID, limit: Int = 60) async -> [CoachChatMessage] {
        let rows: [CoachChatMessage]? = try? await client
            .from("coach_chat_messages")
            .select("id, role, body, created_at")
            .eq("thread_id", value: threadID.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return (rows ?? []).reversed()
    }

    @discardableResult
    static func append(threadID: UUID, role: String, body: String) async -> CoachChatMessage? {
        guard let me = await SupabaseService.shared.currentUserID() else { return nil }
        struct Insert: Encodable {
            let user_id: String
            let thread_id: String
            let role: String
            let body: String
        }
        return try? await client
            .from("coach_chat_messages")
            .insert(Insert(user_id: me.uuidString, thread_id: threadID.uuidString,
                           role: role, body: body))
            .select("id, role, body, created_at")
            .single()
            .execute()
            .value
    }

    // MARK: Compaction state (lives on the thread row)

    static func saveState(threadID: UUID, summary: String, through: Date) async {
        struct Update: Encodable {
            let summary: String
            let summarized_through: Date
        }
        _ = try? await client
            .from("coach_chat_threads")
            .update(Update(summary: summary, summarized_through: through))
            .eq("id", value: threadID.uuidString)
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
/// One thread's live engine: seeds a session from the thread's stored
/// summary plus its recent tail, answers with the full tool belt, and
/// compacts onto the thread row when the tail outgrows the budget.
@available(iOS 26.0, *)
@MainActor
final class CoachChatEngine {
    private var session: LanguageModelSession?
    private var turnsSinceSeed = 0
    /// Past this many live turns, the next reply also triggers a
    /// background compaction. Chosen well inside the ~4k window.
    private let compactionBudget = 12

    private let thread: CoachChatThread
    private let profile: TrainingProfile
    private let persona: CoachPersona?
    /// Field 2026-08-24: "let coach see all of your past routines,
    /// saved routines, and scheduled routines" — computed lines the
    /// view assembles from the repositories; empty string = no data.
    private let routinesRail: String
    private let trendLookup: @Sendable (String) -> String
    private let volumeLookup: @Sendable () -> String
    /// The app's math as a tool (owner 2026-08-25) — nil omits the tool.
    private let progressionLookup: (@Sendable (String, Int?) -> String)?
    /// The Apply loop in threads (owner 2026-08-25: "a huge hook that I
    /// want enabled") — nil omits the tool (e.g. unavailable devices).
    private let onProposeEdit: (@Sendable (RoutineEditProposal) -> Void)?
    /// Durable constraints the athlete authored (public.training_rules).
    /// Passed in rather than fetched here for the same reason the
    /// generator takes them as a parameter: this type stays deterministic
    /// and testable, and the network stays at the edges.
    private let standingRules: [String]
    private let catalog: [Exercise]
    private let onProposeRule: (@Sendable (StandingRuleProposal) -> Void)?

    init(thread: CoachChatThread,
         profile: TrainingProfile, persona: CoachPersona?,
         routinesRail: String = "",
         trendLookup: @escaping @Sendable (String) -> String,
         volumeLookup: @escaping @Sendable () -> String,
         progressionLookup: (@Sendable (String, Int?) -> String)? = nil,
         standingRules: [String] = [],
         onProposeEdit: (@Sendable (RoutineEditProposal) -> Void)? = nil,
         catalog: [Exercise] = [],
         onProposeRule: (@Sendable (StandingRuleProposal) -> Void)? = nil) {
        self.thread = thread
        self.profile = profile
        self.persona = persona
        self.routinesRail = routinesRail
        self.trendLookup = trendLookup
        self.volumeLookup = volumeLookup
        self.progressionLookup = progressionLookup
        self.onProposeEdit = onProposeEdit
        self.standingRules = standingRules
        self.catalog = catalog
        self.onProposeRule = onProposeRule
    }

    private func seedSession(summary: String, tail: [CoachChatMessage]) {
        var instructions = DebriefInstructions.build(persona: persona, profile: profile)
        instructions += "\n\nThis is an ONGOING conversation thread, not a one-off debrief. Keep replies chat-length (2-5 sentences) unless asked to go deep."
        if !routinesRail.isEmpty {
            instructions += "\n\nTHE ATHLETE'S ROUTINES AND SCHEDULE (computed — cite, don't invent):\n" + routinesRail
        }
        if !standingRules.isEmpty {
            // The athlete's OWN words, held across blocks. Coach must be
            // able to cite one ("you asked me to keep pulls before arms")
            // rather than silently obeying it, which is the difference
            // between a coach who listened and a setting that took effect.
            instructions += "\n\nSTANDING RULES THE ATHLETE GAVE YOU (honor these; say so when one shapes your answer):\n"
                + standingRules.map { "- \($0)" }.joined(separator: "\n")
        }
        if !summary.isEmpty {
            instructions += "\n\nWHAT HAS HAPPENED SO FAR IN THIS THREAD (your own memory — trust it):\n" + summary
        }
        if !tail.isEmpty {
            let rendered = tail.suffix(8).map { "\($0.isCoach ? "You" : "Athlete"): \($0.body)" }
                .joined(separator: "\n")
            instructions += "\n\nRECENT MESSAGES:\n" + rendered
        }
        var tools: [any Tool] = [ExerciseTrendTool(lookup: trendLookup),
                                 WeeklyVolumeTool(lookup: volumeLookup),
                                 CorpusResearchTool(),
                                 NutritionTool()]
        if let progressionLookup {
            tools.append(ProgressionCheckTool(lookup: progressionLookup))
            instructions += "\n\nBefore discussing or proposing any specific weight, call progressionCheck — never compute your own numbers."
        }
        if let onProposeEdit {
            tools.append(ProposeRoutineEditTool(onPropose: onProposeEdit))
            instructions += "\nWhen the athlete agrees a concrete change is right, use proposeRoutineEdit with the numbers progressionCheck gave you. To replace an exercise entirely, set swapToExerciseName. Never claim a change was made unless the tool's reply confirms the athlete applied it."
        }
        // The standing-rule lever, in chat (owner 2026-08-27: requests
        // through chat should effect change, always via consent). Same
        // tool the consult close uses; same card; same grounding through
        // the tested parser.
        if let onProposeRule, !catalog.isEmpty {
            tools.append(ProposeStandingRuleTool(catalog: catalog,
                                                 onPropose: onProposeRule))
            instructions += "\nWhen the athlete states a durable training RULE (not a one-off tweak) - a pairing, an exercise to avoid, a swap they always want, an order, a weekly-set cap or floor - call proposeStandingRule with their exact words and one line of this vocabulary:\n"
                + RuleClassifier.structuredVocabulary
                + "\nThe athlete confirms on a card; never claim a rule is saved unless the tool's reply says they accepted."
        }
        session = LanguageModelSession(
            tools: tools,
            instructions: instructions)
        turnsSinceSeed = 0
    }

    /// Answer one athlete message; compacts in the background when the
    /// tail is long. Persistence belongs to the caller.
    func reply(to message: String) async throws -> String {
        if session == nil {
            let tail = await CoachChatRepository.recent(threadID: thread.id, limit: 10)
            seedSession(summary: thread.summary, tail: tail)
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
    /// the summary lands on the thread row and the session reseeds.
    private func compact() async {
        guard let session else { return }
        let prompt = "Write a compact memory note (under 150 words) of this conversation so far: the athlete's situation, decisions made, advice given, and anything you promised to follow up on. Plain prose, no preamble — this note becomes your memory when the conversation continues."
        guard let summary = try? await session.respond(to: prompt).content else { return }
        await CoachChatRepository.saveState(threadID: thread.id, summary: summary, through: Date())
        seedSession(summary: summary, tail: [])
    }
}
#endif
