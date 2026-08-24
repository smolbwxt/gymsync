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

/// A routine change Coach proposes mid-conversation (owner
/// 2026-08-22: "Yes — want me to edit your routine to reflect this?"
/// and then it actually does). The tool never writes; it surfaces THIS
/// for the athlete's explicit Apply tap — the #38 no-silent-tweaks
/// ruling holds even for Coach's own suggestions.
struct RoutineEditProposal: Equatable {
    let exerciseName: String
    /// In the athlete's display unit; nil = leave load untouched.
    let weight: Double?
    let repsLow: Int?
    let repsHigh: Int?
    let reason: String
}

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
         volumeLookup: @escaping @Sendable () -> String,
         onProposeEdit: (@Sendable (RoutineEditProposal) -> Void)? = nil) {
        self.debrief = debrief
        var tools: [any Tool] = [ExerciseTrendTool(lookup: trendLookup),
                                 WeeklyVolumeTool(lookup: volumeLookup),
                                 // The research library (owner 2026-08-22):
                                 // general training questions consult the
                                 // corpus; misses queue the next pass.
                                 CorpusResearchTool(),
                                 // Diet via Apple Health (owner 2026-08-24).
                                 NutritionTool()]
        if let onProposeEdit {
            tools.append(ProposeRoutineEditTool(onPropose: onProposeEdit))
        }
        self.session = LanguageModelSession(
            tools: tools,
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
struct ExerciseTrendTool: Tool {
    let name = "exerciseTrend"
    let description = "Get the athlete's strength trend for one exercise, by name."
    let lookup: @Sendable (String) -> String

    @Generable
    struct Arguments {
        @Guide(description: "The exercise name, e.g. 'Bench Press'")
        var exerciseName: String
    }

    // Shipped API: `Tool.call` returns the associated Output
    // (any PromptRepresentable); the beta-era `ToolOutput` wrapper was
    // removed from the SDK. Archive job caught it - build-test runs an
    // older Xcode where canImport(FoundationModels) is false, so this
    // file had never met a compiler until the first master deploy.
    func call(arguments: Arguments) async throws -> String {
        lookup(arguments.exerciseName)
    }
}

/// Tool: propose a concrete routine change for the athlete to APPLY.
/// The tool records the proposal for an on-screen consent card and
/// tells the model the ball is in the athlete's court - the model must
/// never claim the change was made.
@available(iOS 26.0, *)
private struct ProposeRoutineEditTool: Tool {
    let name = "proposeRoutineEdit"
    let description = "When the athlete AGREES a prescription change is right (a different starting weight, a new rep range), propose the concrete edit. The athlete sees an Apply card and decides. Use only after the athlete has said yes to the idea in conversation."
    let onPropose: @Sendable (RoutineEditProposal) -> Void

    @Generable
    struct Arguments {
        @Guide(description: "The exercise name exactly as it appears in the workout data")
        var exerciseName: String
        @Guide(description: "New working weight in the athlete's display unit, omit to keep current")
        var weight: Double?
        @Guide(description: "New rep range low, omit to keep current")
        var repsLow: Int?
        @Guide(description: "New rep range high, omit to keep current")
        var repsHigh: Int?
        @Guide(description: "One plain sentence on why, citing the session's numbers")
        var reason: String
    }

    func call(arguments: Arguments) async throws -> String {
        onPropose(RoutineEditProposal(
            exerciseName: arguments.exerciseName,
            weight: arguments.weight,
            repsLow: arguments.repsLow,
            repsHigh: arguments.repsHigh,
            reason: arguments.reason))
        return "Proposal is on the athlete's screen with an Apply button. Tell them it's ready to apply - do NOT claim the routine has been changed; they decide."
    }
}

/// Tool: the athlete's recent diet from Apple Health — every major
/// tracker (MyFitnessPal, MyNetDiary, Cronometer, Lose It) syncs there,
/// so one read integrates them all. Returns a computed sentence.
@available(iOS 26.0, *)
struct NutritionTool: Tool {
    let name = "nutritionSummary"
    let description = "Get the athlete's average daily calories and macros (protein, carbs, fat) over the last week, from their diet tracker via Apple Health. Use when the conversation touches diet, protein intake, cutting, bulking, or recovery fuel."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await HealthKitBridge.nutritionSummaryLine()
    }
}

/// Tool: this week's per-muscle volume — returns a computed sentence.
@available(iOS 26.0, *)
struct WeeklyVolumeTool: Tool {
    let name = "weeklyVolume"
    let description = "Get the athlete's per-muscle training volume for this week."
    let lookup: @Sendable () -> String

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        lookup()
    }
}
#endif
