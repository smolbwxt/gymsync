import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - RuleClassifier
//
// Reads a rule the athlete typed in their own words into a structured
// intent the generator can act on.
//
// Owner 2026-08-26 chose classify-then-confirm over a hand-written
// whitelist: "superset every set with push-ups", "chuck some pushups in
// between sets" and "finish every lift with pushups" all mean the same
// thing, and a keyword matcher would honour the first and silently drop
// the other two. The model handles the phrasing; the ATHLETE handles the
// judgement, because a misread rule is worse than an unread one - it
// changes training they never asked to change.
//
// Runs on Apple's on-device model, same engine as Coach chat, so this
// costs no network and no money and works on a plane.
//
// THE VOCABULARY IS MEASURED, NOT INVENTED, and that is a correction.
// The first version of this file offered the model four forms written
// from four example rules. A grammar wave over 656 real coaching
// instructions (tools/youtube-research/route_grammar.py, roadmap in
// passes/grammar/roadmap.json) found those four expressed 9% of the
// language, and that all three predicates believed covered were
// NAME-ONLY matches with the wrong slot types.
//
// The forms below are the shapes with real speaker counts behind them.
// `WHEN` is the biggest change and it is not a form at all - it is a
// SUFFIX available on every line, because `conditional` (162 instances,
// 11 speakers, the top shape by 3x) never stood alone in the corpus. It
// always arrived fused onto another predicate as a trigger. Adding it as
// a fifth form would have reproduced the same 9% problem one level down.
//
// FAILURE IS ALWAYS `.unknown`, never a guess. No model on this OS, a
// refusal, a reply that does not parse - all land in the same place: the
// rule is stored verbatim, reported as heard-not-built, and counted in
// the queue of levers worth building (migration 20260826000007).
enum RuleClassifier {

    /// One reading of one rule. `intent` is `.unknown` whenever we could
    /// not do better, which is a legitimate outcome and not an error.
    struct Reading: Equatable, Sendable {
        var intent: RuleIntent = .unknown
        var slots: [String: String] = [:]
    }

    /// The vocabulary the model is allowed to answer in.
    ///
    /// Every form names something the app can represent, and two of them
    /// (CUE, LIGHT) name things it can represent but not yet ACT on -
    /// included deliberately, because classifying a rule Coach cannot
    /// build is what puts it in the demand queue with its shape intact.
    /// Leaving them out would send them to `.unknown`, where they would
    /// be indistinguishable from noise.
    private static let instructions = """
    You convert a gym athlete's training rule into ONE line of structured \
    output. Reply with the line and nothing else. No explanation.

    Allowed forms, exactly:
      PAIR <exercise>               do this exercise alongside every lift
      AVOID <exercise>              never include this exercise
      SWAP <exercise> FOR <exercise>  stop doing the first, prefer the second
      ORDER <muscle> <muscle>       train the first muscle before the second
      CAP <muscle> <number>         at most this many sets per week
      FLOOR <muscle> <number>       at least this many sets per week
      CUE <exercise> <instruction>  how to perform the exercise
      LIGHT <day name>              keep that day easy
      UNKNOWN                       anything else, or if you are unsure

    Any line may end with a condition:
      ... WHEN <condition>

    Use WHEN only when the athlete stated a trigger. Most rules have none.

    Choose UNKNOWN rather than guessing. A wrong reading changes an \
    athlete's training without their knowledge; UNKNOWN simply means we \
    ask them.

    Examples:
      "superset every set with push-ups"        -> PAIR push-ups
      "chuck some pushups in between sets"      -> PAIR push-ups
      "finish every lift with pushups"          -> PAIR push-ups
      "never overhead barbell"                  -> AVOID overhead press
      "no leg extensions, they hurt my knees"   -> AVOID leg extension
      "use hack squats instead of back squats"  -> SWAP back squat FOR hack squat
      "pulls before arms"                       -> ORDER back biceps
      "no more than 20 sets of chest a week"    -> CAP chest 20
      "at least 12 sets for back each week"     -> FLOOR back 12
      "control the eccentric on rows"           -> CUE row control the eccentric
      "keep Saturdays light"                    -> LIGHT Saturday
      "swap to neutral grip if my elbows hurt"  -> SWAP barbell curl FOR hammer curl WHEN elbows hurt
      "I want to look like Arnold"              -> UNKNOWN
      "train hard"                              -> UNKNOWN
    """

    /// Classify one rule. `catalog` resolves an exercise name to the id
    /// the generator needs; a name that matches nothing stays `.unknown`,
    /// because a lever pointed at no exercise is worse than no lever.
    static func read(_ rule: String, catalog: [Exercise]) async -> Reading {
        guard let line = await answer(for: rule) else { return Reading() }
        return parse(line, catalog: catalog)
    }

    /// Turn the model's one line into a reading. Separated from the model
    /// call so it is testable without a device that has one.
    static func parse(_ line: String, catalog: [Exercise]) -> Reading {
        var body = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Peel the condition off first, so every form below parses the
        // same whether or not the athlete stated a trigger.
        var condition = ""
        if let r = body.range(of: " WHEN ", options: [.caseInsensitive, .backwards]) {
            condition = String(body[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            body = String(body[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        var reading = parseBody(body, catalog: catalog)
        if reading.intent != .unknown, !condition.isEmpty {
            // Recorded, and it makes the rule unbuildable by design -
            // Coach has no reading of the athlete's elbows. Saying which
            // PART it cannot check beats a bare "I did not understand".
            reading.slots["condition"] = condition
        }
        return reading
    }

    private static func parseBody(_ body: String, catalog: [Exercise]) -> Reading {
        let parts = body.split(separator: " ", maxSplits: 1,
                               omittingEmptySubsequences: true)
        guard let head = parts.first?.uppercased() else { return Reading() }
        let rest = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

        switch head {
        case "PAIR", "AVOID":
            guard let match = resolve(rest, in: catalog) else { return Reading() }
            return Reading(intent: head == "PAIR" ? .pairWith : .avoid,
                           slots: ["exercise_id": match.id.uuidString,
                                   "exercise_name": match.name])

        case "SWAP":
            guard let r = rest.range(of: " FOR ", options: .caseInsensitive)
            else { return Reading() }
            let fromName = String(rest[..<r.lowerBound])
            let toName = String(rest[r.upperBound...])
            guard let from = resolve(fromName, in: catalog),
                  let to = resolve(toName, in: catalog),
                  from.id != to.id
            else { return Reading() }
            return Reading(intent: .swap,
                           slots: ["from_id": from.id.uuidString,
                                   "from_name": from.name,
                                   "to_id": to.id.uuidString,
                                   "to_name": to.name])

        case "ORDER":
            let muscles = rest.split(separator: " ").map(String.init)
            guard muscles.count >= 2, muscles[0].lowercased() != muscles[1].lowercased()
            else { return Reading() }
            return Reading(intent: .orderBefore,
                           slots: ["muscle": muscles[0],
                                   "after_muscle": muscles[1]])

        case "CAP", "FLOOR":
            let bits = rest.split(separator: " ").map(String.init)
            guard bits.count >= 2, let n = Int(bits[1]), n > 0, n <= 60
            else { return Reading() }
            return Reading(intent: head == "CAP" ? .capVolume : .floorVolume,
                           slots: ["muscle": bits[0], "number": String(n)])

        case "CUE":
            let bits = rest.split(separator: " ", maxSplits: 1,
                                  omittingEmptySubsequences: true)
            guard bits.count == 2, let match = resolve(String(bits[0]), in: catalog)
            else { return Reading() }
            return Reading(intent: .cue,
                           slots: ["exercise_id": match.id.uuidString,
                                   "exercise_name": match.name,
                                   "technique": String(bits[1])])

        case "LIGHT":
            guard !rest.isEmpty else { return Reading() }
            return Reading(intent: .lightDay, slots: ["muscle": rest])

        default:
            return Reading()
        }
    }

    /// Name to catalog row. Exact match first, then a contains match, so
    /// "push-ups" finds "Push-Up" without matching half the catalog.
    private static func resolve(_ name: String,
                                in catalog: [Exercise]) -> Exercise? {
        let needle = normalize(name)
        guard !needle.isEmpty else { return nil }
        if let exact = catalog.first(where: { normalize($0.name) == needle }) {
            return exact
        }
        // Shortest containing match: "row" should not resolve to
        // "Single-Arm Dumbbell Row" when plain "Row" exists.
        return catalog
            .filter { normalize($0.name).contains(needle) || needle.contains(normalize($0.name)) }
            .min { $0.name.count < $1.name.count }
    }

    /// Fold the punctuation and plurals that separate "push-ups" from
    /// "Push Up" without pulling in a stemmer.
    private static func normalize(_ s: String) -> String {
        var out = s.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
        if out.hasSuffix("s") { out.removeLast() }
        return out
    }

    // MARK: The model

    #if canImport(FoundationModels)
    private static func answer(for rule: String) async -> String? {
        guard #available(iOS 26.0, *) else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        return try? await session.respond(to: rule).content
    }
    #else
    /// No on-device model in this build. Every rule reads as `.unknown`,
    /// which is exactly the pre-classifier behaviour: stored, shown,
    /// queued, not built.
    private static func answer(for rule: String) async -> String? { nil }
    #endif
}
