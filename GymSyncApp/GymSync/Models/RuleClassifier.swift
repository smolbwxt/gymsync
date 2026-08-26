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
// FAILURE IS ALWAYS `.unknown`, never a guess. No model on this OS, a
// refusal, a reply that does not parse - all land in the same place: the
// rule is stored verbatim, reported as heard-not-built, and counted in
// the queue of levers worth building. That queue is the point (see
// migration 20260826000007).
enum RuleClassifier {

    /// One reading of one rule. `intent` is `.unknown` whenever we could
    /// not do better, which is a legitimate outcome and not an error.
    struct Reading: Equatable, Sendable {
        var intent: RuleIntent = .unknown
        var slots: [String: String] = [:]
    }

    /// The vocabulary the model is allowed to answer in.
    ///
    /// Deliberately tiny, and every line names something the app can
    /// actually represent. Offering the model a richer taxonomy than the
    /// generator has levers for would just move the silent-drop one layer
    /// inward - the model would classify confidently into a bucket
    /// nothing reads.
    private static let instructions = """
    You convert a gym athlete's training rule into ONE line of structured \
    output. Reply with the line and nothing else. No explanation.

    Allowed forms, exactly:
      PAIR <exercise name>          - do this exercise alongside every lift
      AVOID <exercise name>         - never include this exercise
      ORDER <muscle> <muscle>       - train the first muscle before the second
      LIGHT <day name>              - keep that day easy
      UNKNOWN                       - anything else, or if you are unsure

    Choose UNKNOWN rather than guessing. A wrong reading changes an \
    athlete's training without their knowledge; UNKNOWN simply means we \
    ask them.

    Examples:
      "superset every set with push-ups"        -> PAIR push-ups
      "chuck some pushups in between sets"      -> PAIR push-ups
      "finish every lift with pushups"          -> PAIR push-ups
      "never overhead barbell"                  -> AVOID overhead press
      "no leg extensions, they hurt my knees"   -> AVOID leg extension
      "pulls before arms"                       -> ORDER back biceps
      "keep Saturdays light"                    -> LIGHT Saturday
      "I want to look like Arnold"              -> UNKNOWN
      "train hard"                              -> UNKNOWN
    """

    /// Classify one rule. `catalog` resolves an exercise name to the id
    /// the generator needs; a name that matches nothing stays `.unknown`,
    /// because a lever pointed at no exercise is worse than no lever.
    static func read(_ rule: String,
                     catalog: [Exercise]) async -> Reading {
        guard let line = await answer(for: rule) else { return Reading() }
        return parse(line, catalog: catalog)
    }

    /// Turn the model's one line into a reading. Separated from the model
    /// call so it is testable without a device that has one.
    static func parse(_ line: String, catalog: [Exercise]) -> Reading {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1,
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
        case "ORDER":
            let muscles = rest.split(separator: " ").map(String.init)
            guard muscles.count >= 2 else { return Reading() }
            return Reading(intent: .orderBefore,
                           slots: ["muscle": muscles[0],
                                   "after_muscle": muscles[1]])
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
