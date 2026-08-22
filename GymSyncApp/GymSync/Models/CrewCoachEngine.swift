import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - CrewCoachEngine
//
// @Coach in crew chats (spec 2026-08-22 §3). The data boundary, enforced
// here and only here: Coach reads the ASKER's own training data (made
// public by the act of asking — consent by venue) plus crew-shared data
// any member already sees. Never another member's personal logbook.
//
// Runtime: the asker's device runs the on-device model; devices without
// Apple Intelligence degrade to the computed report-card sentences —
// honest, never silent. The reply is a plain string; posting it as a
// chat message is the caller's job.
enum CrewCoachEngine {

    /// The crew gate (spec: ONE Pro member lights @Coach for the whole
    /// crew — the only non-Pro venue, deliberately). While the paywall
    /// is dormant every crew qualifies; the shape is what ships.
    static func crewHasCoach(memberProfiles: [Profile]) -> Bool {
        guard Monetization.paywallEnabled else { return true }
        return memberProfiles.contains { Monetization.isPro($0) }
    }

    struct Context {
        var profile = TrainingProfile()
        /// The asker's recent logs, grouped by lowercased exercise name.
        var logsByName: [String: [SetLog]] = [:]
        /// Crew-shared lines (streak, week count) — data any member sees.
        var crewLines: [String] = []
    }

    /// Assemble the asker-scoped context. Best effort — a failed fetch
    /// just means fewer facts.
    static func assembleContext(askerID: UUID, groupID: UUID,
                                exercises: [Exercise]) async -> Context {
        var context = Context()
        if let profile = try? await TrainingProfileRepository.load() {
            context.profile = profile
        }
        let nameByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0.name) })
        if let logs = try? await SessionRepository.recentSetLogs(
            userID: askerID, since: Date(timeIntervalSinceNow: -42 * 86_400)) {
            for log in logs where !log.isPenalty {
                guard let name = nameByID[log.exerciseID]?.lowercased() else { continue }
                context.logsByName[name, default: []].append(log)
            }
        }
        if let streak = try? await StreakRepository.groupStreak(groupID: groupID) {
            context.crewLines.append("Crew streak: \(streak.currentStreak) week\(streak.currentStreak == 1 ? "" : "s").")
        }
        return context
    }

    /// The WORKOUT DATA payload for the model — same computed-facts
    /// doctrine as the debrief: the model narrates arithmetic done in
    /// Swift, it never computes.
    static func corePayload(question: String, context: Context) -> String {
        var lines = ["CREW CHAT QUESTION FROM THE ATHLETE: \(question)",
                     "",
                     "WORKOUT DATA (computed — cite these numbers verbatim, never calculate your own):"]
        let goals = context.profile.rankedGoals.map(\.rawValue).joined(separator: " then ")
        lines.append("GOALS: \(goals.isEmpty ? "general training" : goals)")
        // Trends for the lifts the question names; the top lifts otherwise.
        let mentioned = context.logsByName.keys.filter { question.lowercased().contains($0) }
        let liftNames = mentioned.isEmpty
            ? Array(context.logsByName.sorted { $0.value.count > $1.value.count }
                .prefix(4).map(\.key))
            : Array(mentioned.prefix(4))
        for name in liftNames {
            guard let logs = context.logsByName[name], logs.count > 1 else { continue }
            lines.append(DebriefBuilder.trendSentence(name: name.capitalized, logs: logs))
        }
        lines.append(contentsOf: context.crewLines)
        return lines.joined(separator: "\n")
    }

    /// The extra rail a group chat needs on top of the debrief's rules.
    static let crewRail = """
        You are answering INSIDE A CREW GROUP CHAT. The data above belongs to the athlete who asked — you have no other member's personal training data, so if asked about someone else's numbers, say plainly that each lifter asks about their own training. Keep answers to 2-4 sentences — this is a chat, not a report.
        """

    /// The computed fallback (no Apple Intelligence): the same trend
    /// sentences the model would have narrated, stitched plainly.
    static func computedAnswer(question: String, context: Context) -> String {
        let mentioned = context.logsByName.keys.filter { question.lowercased().contains($0) }
        var lines: [String] = []
        for name in mentioned.prefix(2) {
            guard let logs = context.logsByName[name], logs.count > 1 else { continue }
            lines.append(DebriefBuilder.trendSentence(name: name.capitalized, logs: logs))
        }
        if lines.isEmpty {
            let top = context.logsByName.sorted { $0.value.count > $1.value.count }.prefix(2)
            for (name, logs) in top where logs.count > 1 {
                lines.append(DebriefBuilder.trendSentence(name: name.capitalized, logs: logs))
            }
        }
        lines.append(contentsOf: context.crewLines)
        guard !lines.isEmpty else {
            return "Not enough logged history to say anything useful yet — a few more sessions and I'll have real numbers for you."
        }
        return (["Here's what the log says:"] + lines).joined(separator: " ")
    }

    /// The full pipeline: context → model (or computed fallback) → reply
    /// text. Never throws; the worst case is the honest not-enough-data
    /// line.
    static func answer(question: String, askerID: UUID, groupID: UUID,
                       exercises: [Exercise]) async -> String {
        let context = await assembleContext(askerID: askerID, groupID: groupID,
                                            exercises: exercises)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), CoachDebrief.isConversationAvailable {
            if let reply = await modelAnswer(question: question, context: context) {
                return reply
            }
        }
        #endif
        return computedAnswer(question: question, context: context)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func modelAnswer(question: String, context: Context) async -> String? {
        let instructions = [DebriefInstructions.build(
            persona: CoachPersona.bySlug(context.profile.persona),
            profile: context.profile), crewRail].joined(separator: "\n\n")
        let session = LanguageModelSession(
            tools: [CorpusResearchTool()],
            instructions: instructions)
        return try? await session.respond(
            to: corePayload(question: question, context: context)).content
    }
    #endif
}

