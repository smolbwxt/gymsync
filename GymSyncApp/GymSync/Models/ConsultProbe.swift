import Foundation

// MARK: - ConsultProbe
//
// The consult's question bank, as DATA (owner 2026-08-25: "a bag of
// questions that are selected like tools to discern which vectors to
// tune"). Nothing here is a script — a probe is picked when it would
// change the program and skipped when it would not.
//
// The owner's framing decides the division of labour: the five doors on
// My Program give COARSE adjustment; the consult confirms, probes and
// fine-tunes. So a probe reads what the doors already said and either
// leaves it alone, confirms it, or refines it. `FieldProvenance` is what
// makes that decidable — a persona default is cheap to challenge, a
// value the athlete stated is not, and a value the LOG contradicts is
// the most valuable question available.
//
// Stopping is Akinator-shaped, not budgeted: keep asking while some
// unresolved knob would change the program, stop when every remaining
// unknown is safely defaultable. A one-day-a-week lifter genuinely
// determines in three questions; a powerlifter with a bad shoulder and a
// date might need twelve. Neither is capped.
enum ConsultProbe {

    enum Family: String, Equatable, Sendable {
        case goal, path, challenge, constraint, rule
    }

    struct Option: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        /// Shown under the chip when the choice needs a consequence
        /// stated. Used sparingly — the label should usually carry it.
        var detail: String? = nil
    }

    struct Probe: Identifiable, Equatable, Sendable {
        let id: String
        let ask: String
        /// Empty means free text.
        var options: [Option] = []
        /// Which knobs an answer writes. Documentation AND the basis for
        /// gain — a probe that tunes nothing has no business being asked.
        let tunes: [String]
        /// How much the answer moves the program, 1-10.
        let gain: Int
        let family: Family
        var clarifier: String? = nil
    }

    /// What the selector knows when choosing the next probe. Everything
    /// here is READ from the profile, the log, or earlier answers — the
    /// consult never asks for something it can already see.
    struct Context: Equatable, Sendable {
        var answered: Set<String> = []
        /// The opener's answer; branches everything after it.
        var goalBranch: String? = nil
        /// Does this athlete have enough logged history to diagnose?
        /// False sends us to the cold-start bag: an athlete with no log
        /// cannot be asked where their bench is, or confronted with an
        /// attendance pattern that does not exist.
        var hasLog: Bool = false
        /// Sessions per week the log actually shows.
        var loggedDaysPerWeek: Double? = nil
        /// Sessions per week the athlete says they will train.
        var statedDaysPerWeek: Int? = nil
        var equipmentKnown: Bool = false
        var sessionMinutesKnown: Bool = false
        var cautionsKnown: Bool = false
        var isYouth: Bool = false
        /// Provenance of profile fields, so a persona default can be
        /// challenged and a stated value left alone.
        var provenance: [String: FieldProvenance] = [:]
        /// Set once the athlete has given at least one standing rule, so
        /// the free-text prompt is offered rather than repeated.
        var offeredRuleCapture: Bool = false
        /// Days per week the PROGRAM needs to do what the athlete asked
        /// for. Fills the {days} token — see the commitment probe.
        var recommendedDaysPerWeek: Int? = nil

        /// The commitment gap. Positive means they intend more than they
        /// have been doing.
        var commitmentGap: Double? {
            guard let stated = statedDaysPerWeek, let logged = loggedDaysPerWeek else { return nil }
            return Double(stated) - logged
        }
    }

    // MARK: The bank

    static let opener = Probe(
        id: "opener",
        ask: "What's this block chasing?",
        options: [
            Option(id: "numbers", label: "HIT NEW NUMBERS"),
            Option(id: "size", label: "ADD SIZE"),
            Option(id: "date", label: "PREP FOR A DATE"),
            Option(id: "forge", label: "FORGE THE BODY"),
            Option(id: "engine", label: "BUILD THE ENGINE"),
            Option(id: "running", label: "KEEP IT RUNNING"),
        ],
        tunes: ["rankedGoals", "generatorFocus", "bandOverride"],
        gain: 10,
        family: .goal)

    /// Everything after the opener. Order in this array is irrelevant —
    /// `next(in:)` ranks by gain among the probes whose preconditions
    /// pass.
    static let bank: [Probe] = [
        // ── Goal refinement, branched ────────────────────────────────
        Probe(id: "focus_lift",
              ask: "Which lift is the number on?",
              tunes: ["focusMuscles", "starredExerciseIDs", "selectionTilt"],
              gain: 9, family: .goal),
        Probe(id: "focus_areas",
              ask: "Which two areas do you want to look different?",
              tunes: ["focusMuscles"],
              gain: 9, family: .goal,
              clarifier: "Pick two and I'll give them the volume, and pull it back everywhere else."),
        // Note this tunes DURATION, not a phase model. Phase structure is
        // DERIVED — BlockPhase.phases(for:) reads each week's
        // percentOfBaseline and names what it finds. Listing a
        // "phaseModel" knob here would have been fiction: a probe claiming
        // to write something nothing reads, which is the dead-knob bug
        // repAppetite spent months being.
        Probe(id: "the_date",
              ask: "What's on the date, and when is it?",
              tunes: ["durationWeeks", "sportPrepSport"],
              gain: 10, family: .goal),
        // Writing the story tests exposed this hole: five of the six
        // opener doors branched into a refinement and "BUILD THE ENGINE"
        // branched into nothing, so an endurance athlete answered the
        // opener and was handed straight to the generic probes. The
        // meaningful fork for a conditioning goal is which ENGINE — the
        // one that holds a pace, or the one that repeats hard efforts —
        // and cardioStyle already carries it.
        Probe(id: "engine_kind",
              ask: "Which engine — one that holds a pace, or one that repeats hard efforts?",
              options: [
                Option(id: "steady", label: "HOLDS A PACE"),
                Option(id: "intervals", label: "REPEATS HARD EFFORTS"),
              ],
              tunes: ["cardioStyle"],
              gain: 9, family: .goal),
        Probe(id: "whats_off",
              ask: "What feels off right now — energy, breath, stiffness, or the mirror?",
              options: [
                Option(id: "energy", label: "ENERGY"),
                Option(id: "breath", label: "BREATH"),
                Option(id: "stiffness", label: "STIFFNESS"),
                Option(id: "mirror", label: "THE MIRROR"),
              ],
              tunes: ["rankedGoals", "cardioStyle"],
              gain: 8, family: .goal),

        // ── Cold start: no log to diagnose ───────────────────────────
        Probe(id: "anchor_lifts",
              ask: "What can you handle for five solid reps right now? Rough is fine — I just need somewhere to start.",
              tunes: ["liftAnchors"],
              gain: 9, family: .path,
              clarifier: "If you've never done a lift, say so. Starting light and adding is the whole plan."),
        Probe(id: "gym_comfort",
              ask: "Which of these feels genuinely fine to do today?",
              tunes: ["comfortAnswers", "derivedComplexityCap"],
              gain: 8, family: .path,
              clarifier: "This sets how technical your lifts get. Nobody sees the answer."),

        // ── Path ─────────────────────────────────────────────────────
        Probe(id: "days",
              ask: "How many days a week can you actually train?",
              tunes: ["daysPerWeek", "split"],
              gain: 10, family: .path,
              clarifier: "Not the aspirational number. The one you'll hit in a bad week."),
        // The number is a TOKEN, not a word. This probe originally read
        // "the work will take four days a week" no matter what the
        // program actually needed — an improvised number in the one
        // question whose entire weight rests on the number being true.
        // ConsultProbe.ask(_:in:) substitutes from context.
        Probe(id: "commitment",
              ask: "The work will take {days} days a week. Can you commit to that? Or keep your current {current} and the same block just takes longer.",
              options: [
                Option(id: "commit", label: "I'LL COMMIT"),
                Option(id: "current", label: "KEEP MY CADENCE",
                       detail: "Same destination, longer road."),
              ],
              tunes: ["daysPerWeek"],
              gain: 9, family: .path),
        Probe(id: "session_length",
              ask: "How long before you start watching the clock?",
              options: [
                Option(id: "30", label: "30 MIN"),
                Option(id: "45", label: "45 MIN"),
                Option(id: "60", label: "60 MIN"),
                Option(id: "90", label: "90+ MIN"),
              ],
              tunes: ["sessionMinutes"],
              gain: 9, family: .path),
        Probe(id: "equipment",
              ask: "What have you got to lift with?",
              tunes: ["equipment"],
              gain: 10, family: .path),

        // ── What challenging looks like ──────────────────────────────
        Probe(id: "effort",
              ask: "When a set gets hard, what should happen?",
              options: [
                Option(id: "reserved", label: "LEAVE 2-3 IN THE TANK"),
                Option(id: "standard", label: "LAST SET CLOSE TO FAILURE"),
                Option(id: "toFailure", label: "LAST SET TO FAILURE"),
              ],
              tunes: ["effort"],
              gain: 8, family: .challenge,
              clarifier: "All three build muscle — they differ in what they cost you to recover from."),
        Probe(id: "rep_appetite",
              ask: "Heavy and few, or moderate and many?",
              options: [
                Option(id: "heavy_low", label: "HEAVY AND FEW"),
                Option(id: "moderate", label: "SOMEWHERE IN BETWEEN"),
                Option(id: "high_rep_pump", label: "MODERATE AND MANY"),
              ],
              tunes: ["repAppetite"],
              gain: 7, family: .challenge),
        Probe(id: "session_feel",
              ask: "Should a session leave you out of breath, or just tired?",
              options: [
                Option(id: "breath", label: "OUT OF BREATH"),
                Option(id: "tired", label: "JUST TIRED"),
              ],
              tunes: ["sessionStructure", "cardioStyle"],
              gain: 6, family: .challenge),
        Probe(id: "climb_rate",
              ask: "Should the weight climb steady and safe, or push it?",
              options: [
                Option(id: "conservative", label: "STEADY"),
                Option(id: "standard", label: "NORMAL"),
                Option(id: "aggressive", label: "PUSH IT"),
              ],
              tunes: ["intensityAppetite"],
              gain: 6, family: .challenge),

        // ── Constraints ──────────────────────────────────────────────
        Probe(id: "cautions",
              ask: "Anything that hurts, or that you're working around?",
              tunes: ["cautionJoints", "exclusions"],
              gain: 9, family: .constraint),
        Probe(id: "wont_do",
              ask: "Anything you flat-out won't do?",
              tunes: ["excludedPatterns", "exclusions"],
              gain: 7, family: .constraint,
              clarifier: "No justification needed. A lift you skip is worth less than one you'll actually do."),

        // ── Standing rules ───────────────────────────────────────────
        Probe(id: "standing_rule",
              ask: "Anything I should treat as a standing rule?",
              tunes: ["trainingRules"],
              gain: 5, family: .rule,
              clarifier: "Things like \"pulls before arms\" or \"keep Saturdays light\" — I'll hold them across blocks."),
    ]

    // MARK: Tunables

    /// Every destination a probe is allowed to claim, with the type that
    /// actually holds it. A probe whose `tunes` names something outside
    /// this set fails `ConsultProbeTests` — which is the point.
    ///
    /// The consult's whole justification is that each question changes the
    /// program, so a probe writing to a field nothing reads is worse than
    /// no probe at all: it costs the athlete a question and buys them
    /// nothing. This set is the tripwire. Adding a key here is cheap but
    /// deliberate — you have to name the reader.
    static let knownTunables: Set<String> = [
        // → TrainingProfile
        "rankedGoals", "sportPrepSport", "split", "daysPerWeek",
        "sessionMinutes", "repAppetite", "intensityAppetite",
        "sessionStructure", "cardioStyle", "comfortAnswers",
        "derivedComplexityCap", "exclusions", "excludedPatterns",
        "cautionJoints", "equipment", "generatorFocus", "bandOverride",
        // → ProgramGenerator.Inputs (assembled by generatorInputs)
        "focusMuscles", "starredExerciseIDs", "durationWeeks", "effort",
        "selectionTilt",
        // → UserSettings
        "liftAnchors",
        // → public.training_rules, read back through advisoryNotes
        "trainingRules",
    ]

    // MARK: Rendering

    /// The question as the athlete reads it, with every number
    /// substituted from context rather than baked into the string.
    ///
    /// A token left unfilled is not printed raw — the sentence falls back
    /// to a form that stays true without the number, because "{days} days
    /// a week" reaching a real screen is worse than a vaguer sentence.
    static func ask(_ probe: Probe, in context: Context) -> String {
        var text = probe.ask
        if text.contains("{days}") {
            guard let days = context.recommendedDaysPerWeek else {
                return "This block asks for more days than you have been training. Can you commit to that, or should I build for your current cadence and let the block take longer?"
            }
            text = text.replacingOccurrences(of: "{days}", with: "\(days)")
        }
        if text.contains("{current}") {
            let logged = context.loggedDaysPerWeek.map { logged -> String in
                let rounded = (logged * 10).rounded() / 10
                let whole = rounded.rounded()
                let formatted = abs(rounded - whole) < 0.05
                    ? String(Int(whole)) : String(format: "%.1f", rounded)
                return "\(formatted) a week"
            } ?? "current cadence"
            text = text.replacingOccurrences(of: "{current}", with: logged)
        }
        return text
    }

    // MARK: Selection

    /// Whether a probe is worth asking given what we already know. This
    /// is the whole design: preconditions, not a script.
    static func isRelevant(_ probe: Probe, in context: Context) -> Bool {
        if context.answered.contains(probe.id) { return false }
        switch probe.id {
        // Goal branches — only the branch the opener chose.
        case "focus_lift":
            // A cold-start athlete cannot name a focus lift; that was the
            // 13-year-old's failure in the persona sweep.
            return context.goalBranch == "numbers" && context.hasLog
        case "focus_areas":   return context.goalBranch == "size"
        case "the_date":      return context.goalBranch == "date"
        case "engine_kind":   return context.goalBranch == "engine"
        case "whats_off":     return context.goalBranch == "running" || context.goalBranch == "forge"

        // Cold start replaces diagnosis when there is nothing to diagnose.
        case "anchor_lifts", "gym_comfort":
            return !context.hasLog

        // Path.
        case "days":          return context.statedDaysPerWeek == nil
        case "commitment":
            // Only when intent outruns the record, and only by enough to
            // be worth a question rather than a nag.
            guard let gap = context.commitmentGap else { return false }
            return gap >= 1
        case "session_length": return !context.sessionMinutesKnown
        case "equipment":      return !context.equipmentKnown

        // Constraints.
        case "cautions":       return !context.cautionsKnown
        case "wont_do":        return context.answered.contains("cautions")

        // Rules: offered once, at the end.
        case "standing_rule":
            return !context.offeredRuleCapture && context.answered.count >= 3

        // Challenge probes: a persona default is cheap to challenge, a
        // stated value is not.
        case "effort", "rep_appetite", "session_feel", "climb_rate":
            let key = probe.tunes.first ?? probe.id
            switch context.provenance[key] {
            case .stated, .confirmed: return false
            default: return true
            }
        default:
            return true
        }
    }

    /// The next question, or nil when the consult is DONE — meaning no
    /// remaining probe would change the program. Equipment is forced
    /// ahead of anything exercise-specific: proposing lifts an athlete
    /// cannot perform is the credibility failure the consult exists to
    /// avoid.
    static func next(in context: Context) -> Probe? {
        if !context.answered.contains(opener.id) { return opener }
        let candidates = bank.filter { isRelevant($0, in: context) }
        if let equipment = candidates.first(where: { $0.id == "equipment" }) {
            return equipment
        }
        return candidates.max(by: { $0.gain < $1.gain })
    }

    /// How many probes remain — powers an honest "3 of about 6" readout
    /// without pretending to a fixed budget.
    static func remaining(in context: Context) -> Int {
        bank.filter { isRelevant($0, in: context) }.count
    }
}
