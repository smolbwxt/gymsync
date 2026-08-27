import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - ConsultCloseSession
//
// The consult's closing conversation. Owner 2026-08-27:
//
//   "The consult should feel more like a conversation, not like a form.
//    ... At some point, we should be dumped into a chat with coach that
//    summarizes our intent, then the vectors are finalized, and the
//    rules discussed."
//
// So the consult's terminal state is a CHAT: Coach opens by summarizing
// what the probes established, then discusses standing rules. Rule
// capture rides the debrief's proven mechanism — the model PROPOSES its
// reading through a tool, an on-screen consent card renders the athlete's
// verbatim words beside the reading, and the ATHLETE decides. The model
// can never store a rule itself; a misread rule silently reshaping
// training is the failure this whole pipeline exists to prevent.
//
// Availability rides CoachDebrief.isConversationAvailable. Devices
// without the model keep the free-text probe and heard-only storage —
// one honest line, no theater.

/// One rule the model proposes, awaiting the athlete's verdict.
struct StandingRuleProposal: Equatable, Sendable {
    /// The athlete's own words, exactly as they said them. Stored
    /// verbatim on acceptance — the reading is Coach's interpretation,
    /// never a rewrite of what they said.
    let verbatim: String
    let reading: RuleClassifier.Reading
}

enum ConsultClose {

    /// Same gate as the debrief conversation — one definition of "can
    /// this device chat", never two that drift.
    static var isAvailable: Bool { CoachDebrief.isConversationAvailable }

    /// The consult's answers rendered for the model — what Coach "heard",
    /// with the probes' own question text so the summary can speak the
    /// athlete's language rather than probe ids.
    ///
    /// Deterministic and computed, per the debrief doctrine: the model
    /// NARRATES facts, it never invents them.
    static func digest(_ answers: ConsultAnswers) -> String {
        let asks = Dictionary(uniqueKeysWithValues:
            ([ConsultProbe.opener] + ConsultProbe.bank).map { ($0.id, $0) })
        var lines: [String] = []
        for (probeID, values) in answers.byProbe.sorted(by: { $0.key < $1.key }) {
            guard !values.isEmpty else { continue }
            guard let probe = asks[probeID] else { continue }
            // Render option ids through their labels where the probe has
            // options; free text passes through as given.
            let labels = Dictionary(uniqueKeysWithValues:
                probe.options.map { ($0.id, $0.label) })
            var rendered = values.map { labels[$0] ?? $0 }.joined(separator: ", ")
            if probeID == "injury_severity" {
                // "hip=severe" -> what it means for the build.
                let injured = values.compactMap { $0.hasSuffix("=severe") ? String($0.dropLast(7)) : nil }
                rendered = injured.isEmpty
                    ? "every named joint is a caution (steer clear where possible)"
                    : "INJURED, every lift that loads it is OUT of the block: " + injured.joined(separator: ", ")
            }
            lines.append("- \(probe.ask) -> \(rendered)")
        }
        return lines.isEmpty ? "(the athlete kept every default)" : lines.joined(separator: "\n")
    }
}

#if canImport(FoundationModels)

/// Tool: propose Coach's reading of a standing rule for the athlete to
/// accept or reject. Mirrors ProposeRoutineEditTool: the tool records the
/// proposal for an on-screen consent card and tells the model the ball is
/// in the athlete's court.
@available(iOS 26.0, *)
struct ProposeStandingRuleTool: Tool {
    let name = "proposeStandingRule"
    let description = "When the athlete states a training rule, propose your reading of it. The athlete sees a card with their words and your reading, and decides. Use it for EVERY rule they state. Never claim a rule is saved unless the tool's reply confirms the athlete accepted it."
    let catalog: [Exercise]
    let onPropose: @Sendable (StandingRuleProposal) -> Void

    @Generable
    struct Arguments {
        @Guide(description: "The athlete's rule in their exact words, verbatim")
        var athleteWords: String
        @Guide(description: "ONE line in the structured vocabulary from your instructions, e.g. 'PAIR push-ups' or 'SWAP back squat FOR hack squat WHEN knees ache'")
        var structured: String
    }

    func call(arguments: Arguments) async throws -> String {
        // The tested parser grounds the model's line against the real
        // catalog — the model proposes, the parser verifies. A line that
        // does not ground produces NO card; the model is told to ask the
        // athlete to say it differently, which keeps the retry inside the
        // conversation where it belongs.
        let reading = RuleClassifier.parse(arguments.structured, catalog: catalog)
        guard reading.intent != .unknown else {
            return "That did not ground against the athlete's exercise list. Ask them to say it differently - name the exercise the way the app does - and try once more. If it still does not ground, tell them you will keep it in their words on your list."
        }
        onPropose(StandingRuleProposal(verbatim: arguments.athleteWords,
                                       reading: reading))
        return "Proposal shown to the athlete - they decide. Do not claim it is saved; move the conversation on and wait."
    }
}

/// The live closing conversation. One per consult close; instructions are
/// rebuilt from the CURRENT answers, so nothing stales.
@available(iOS 26.0, *)
@MainActor
final class ConsultCloseSession {
    private let session: LanguageModelSession

    init(digest: String, persona: CoachPersona?, profile: TrainingProfile,
         catalog: [Exercise],
         onPropose: @escaping @Sendable (StandingRuleProposal) -> Void) {
        var instructions = DebriefInstructions.build(persona: persona, profile: profile)
        instructions += """


        THIS IS THE CLOSE OF A CONSULT. The athlete just answered your \
        questions. What they told you (computed - cite, don't invent):
        \(digest)

        Open by saying what you are going to DO with what they told you \
        - two or three sentences of reasoning, never a readback. They \
        just gave these answers; do not list them again. Say how the \
        build leans because of them, with the trade-off: for example, \
        "You're comfortable with the technical lifts, so barbell work \
        leads your days and I'll keep the movements challenging" or \
        "Your knee gets a wide berth - nothing deep and loaded there, so \
        the leg work stays on hinges and machines." Consequences, not a \
        summary. Then ask whether there are any standing rules you should \
        hold: things you CAN build in are pairing an exercise with every \
        lift, avoiding an exercise, swapping one exercise for another, \
        training one muscle before another, and capping or flooring a \
        muscle's weekly sets. Do not promise anything beyond those.

        When they state a rule, call proposeStandingRule with their exact \
        words and ONE line of this vocabulary:
        \(RuleClassifier.structuredVocabulary)

        If a rule has a trigger you cannot check ("if my elbows hurt"), \
        say plainly: you will keep the rule as they said it, and when the \
        trigger happens they should tell you in chat and you will make \
        the change then. Never quietly drop their condition.

        Keep replies to 2-4 sentences. When they are done, tell them to \
        hit the build button - never claim the program is already built.
        """
        session = LanguageModelSession(
            tools: [ProposeStandingRuleTool(catalog: catalog, onPropose: onPropose)],
            instructions: instructions)
    }

    /// Coach speaks first — the summary is the opening turn.
    func open() async throws -> String {
        try await session.respond(
            to: "Open the close: greet in a few words, then say how you will build their block BECAUSE of what they told you - the consequences and trade-offs, not a readback of their answers - and ask about standing rules.").content
    }

    func reply(to message: String) async throws -> String {
        try await session.respond(to: message).content
    }

    /// Feed the athlete's card verdict back so the conversation flows —
    /// the model never sees the card, only its outcome.
    func noteVerdict(accepted: Bool, verbatim: String) async -> String? {
        let note = accepted
            ? "SYSTEM: the athlete ACCEPTED your reading of \"\(verbatim)\" - it is saved. Acknowledge in one short sentence and continue."
            : "SYSTEM: the athlete said your reading of \"\(verbatim)\" was NOT what they meant. Ask them to say it differently, once."
        return try? await session.respond(to: note).content
    }
}
#endif
