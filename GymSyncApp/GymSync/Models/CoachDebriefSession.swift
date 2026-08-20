import Foundation

// MARK: - CoachDebriefSession
//
// The Foundation Models adapter — deliberately the THINNEST layer in the
// debrief stack, because it is the only part CI cannot compile until the
// runners carry the iOS 26 SDK (`canImport` excludes it cleanly today).
// Everything with logic lives below it, ungated and tested:
// DebriefBuilder (payload + tool backends), DebriefInstructions
// (persona x register x rails), CoachPersona (the voice data).
//
// Availability doctrine (concept 2026-08-20): the conversation is an
// EXPRESSION of the coaching relationship where the device allows it,
// never the product. `isConversationAvailable` gates the "talk through
// it?" invitation; devices without it render the structured report card
// from the same WorkoutDebrief — one pipeline, two presentations.

enum CoachDebrief {

    /// Whether this device can host the conversational tier at all.
    /// False on every OS below 26 and on hardware without Apple
    /// Intelligence — the free card and report card carry those devices.
    static var isConversationAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
        #else
        return false
        #endif
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// The live conversation: one fresh session per debrief, instructions
/// rebuilt from the CURRENT profile (a coach switch or register change
/// takes effect immediately; persona drift cannot accumulate across
/// sessions).
@available(iOS 26.0, *)
@MainActor
final class CoachDebriefSession {

    private let session: LanguageModelSession
    private let debrief: WorkoutDebrief

    /// - Parameters:
    ///   - trendLookup: tool backend — lift name to a COMPUTED trend
    ///     sentence (`DebriefBuilder.trendSentence`). The model narrates
    ///     arithmetic done in Swift; it never computes.
    ///   - volumeLookup: tool backend — this week's per-muscle sentence.
    init(debrief: WorkoutDebrief,
         persona: CoachPersona?,
         profile: TrainingProfile,
         trendLookup: @escaping @Sendable (String) -> String,
         volumeLookup: @escaping @Sendable () -> String) {
        self.debrief = debrief
        self.session = LanguageModelSession(
            tools: [ExerciseTrendTool(lookup: trendLookup),
                    WeeklyVolumeTool(lookup: volumeLookup)],
            instructions: DebriefInstructions.build(persona: persona,
                                                    profile: profile))
    }

    /// Call when the summary screen appears so the tap opens instantly.
    func prewarm() { session.prewarm() }

    /// The coach's opening message.
    func open() async throws -> String {
        try await respond(to: debrief.corePrompt
            + "\n\nOpen the debrief with your single most important observation about this session, in character, in 2-4 sentences.")
    }

    func reply(to userMessage: String) async throws -> String {
        try await respond(to: userMessage)
    }

    private func respond(to prompt: String) async throws -> String {
        do {
            return try await session.respond(to: prompt).content
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Long conversations overflow the ~4k window: surface a clean
            // hand-back instead of a broken turn. The UI offers a fresh
            // session seeded from the same debrief.
            return "We've covered a lot — let's pick this up fresh. Your numbers are all saved."
        }
    }
}

/// Tool: e1RM trend for a named lift — returns a computed sentence.
@available(iOS 26.0, *)
private struct ExerciseTrendTool: Tool {
    let name = "exerciseTrend"
    let description = "Get the athlete's strength trend for one exercise, by name."
    let lookup: @Sendable (String) -> String

    @Generable
    struct Arguments {
        @Guide(description: "The exercise name, e.g. 'Bench Press'")
        var exerciseName: String
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        ToolOutput(lookup(arguments.exerciseName))
    }
}

/// Tool: this week's per-muscle volume — returns a computed sentence.
@available(iOS 26.0, *)
private struct WeeklyVolumeTool: Tool {
    let name = "weeklyVolume"
    let description = "Get the athlete's per-muscle training volume for this week."
    let lookup: @Sendable () -> String

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> ToolOutput {
        ToolOutput(lookup())
    }
}
#endif
