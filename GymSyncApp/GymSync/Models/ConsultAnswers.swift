import Foundation

// MARK: - ConsultAnswers
//
// What the consult LEARNED, and the single place that turns it into
// program inputs. The view collects; this applies. Keeping the two apart
// is what lets the mapping be tested — "does answering FORGE THE BODY
// actually produce a recomposition block?" is a question about this file,
// not about a SwiftUI hierarchy.
//
// Doctrine, inherited from CoachPersona: an answer is STATED. Every field
// the consult writes gets its provenance upgraded, which is precisely
// what stops Coach re-litigating it later and what stops a persona
// default overwriting it. The consult is where a guess becomes a fact.
struct ConsultAnswers: Equatable, Sendable {

    /// probe id → the option ids (or free text) the athlete gave. Always a
    /// list: single-choice probes write one element, so multi-select
    /// probes need no separate storage shape.
    private(set) var byProbe: [String: [String]] = [:]

    init(_ byProbe: [String: [String]] = [:]) { self.byProbe = byProbe }

    mutating func record(_ probeID: String, _ values: [String]) {
        byProbe[probeID] = values
    }

    func values(_ probeID: String) -> [String] { byProbe[probeID] ?? [] }
    func first(_ probeID: String) -> String? { byProbe[probeID]?.first }

    // MARK: - Goal mapping
    //
    // The opener's six doors, in the athlete's words, mapped to the goal
    // vocabulary the generator already speaks. These are PRODUCT calls —
    // written down here rather than buried in a switch inside a view, so
    // they can be argued with.

    static func goals(forOpener option: String) -> [TrainingGoal] {
        switch option {
        // "GET STRONGER" — the number is the point.
        case "numbers": return [.maxStrength]
        // "BUILD MUSCLE" — the one goal whose name matches its mechanism.
        case "size":    return [.hypertrophy]
        // "TRAIN FOR AN EVENT" — sport prep leads; the date sets duration and
        // the sport sets the lens (see TrainingProfile's sport lenses).
        case "date":    return [.sportPrep, .maxStrength]
        // "BUILD MUSCLE, LOSE FAT" — recomposition. Ranked, not blended: the
        // corpus is consistent that chasing both at once stalls both, so
        // hypertrophy LEADS and fat loss rides second at 0.3 weight,
        // which is exactly what the block planner alternates on.
        case "forge":   return [.hypertrophy, .fatLoss]
        // "IMPROVE CONDITIONING"
        case "engine":  return [.conditioning]
        // "STAY FIT & HEALTHY" — maintenance. Not a lesser goal; it is the
        // one most people are actually in, and general health rides
        // hypertrophy's balanced template.
        default:        return [.generalHealth]
        }
    }

    /// The diagnostic branch. "What feels off" is a symptom, and the goal
    /// it implies is the treatment.
    static func goals(forSymptom symptom: String) -> [TrainingGoal]? {
        switch symptom {
        case "energy":    return [.generalHealth, .conditioning]
        case "breath":    return [.conditioning]
        case "stiffness": return [.mobility]
        case "mirror":    return [.hypertrophy]
        default:          return nil
        }
    }

    // MARK: - Typed reads
    //
    // Answers the generator needs that are NOT profile fields, exposed as
    // parsed values rather than left as strings for a caller to re-parse.

    /// Two areas, at most — the probe promises "pick two and I'll give
    /// them the volume", and honoring more than two would make that
    /// sentence false. Filtered to the vocabulary the coverage check uses.
    var focusMuscles: Set<String>? {
        focusMuscles(in: [])
    }

    /// Focus areas, plus the muscle behind a named focus lift.
    ///
    /// The catalog is needed because "bench press" has to become "chest"
    /// before the generator can do anything with it — focusMuscles is a
    /// muscle set, and the coverage check only speaks
    /// GeneratorScience.majorMuscles.
    func focusMuscles(in catalog: [Exercise]) -> Set<String>? {
        var picked = values("focus_areas")
            .filter { GeneratorScience.majorMuscles.contains($0) }
            .prefix(2)
            .map { $0 }
        // Every focus lift's muscle, not just the first - the athlete can
        // name several now (owner 2026-08-27).
        for lift in focusLifts(in: catalog)
        where GeneratorScience.majorMuscles.contains(lift.primaryMuscle)
            && !picked.contains(lift.primaryMuscle) {
            picked.append(lift.primaryMuscle)
        }
        return picked.isEmpty ? nil : Set(picked)
    }

    /// Every focus lift the athlete named, resolved. The picker records
    /// exercise ids; a legacy free-text answer resolves by name through
    /// the same forgiving-but-unambiguous matcher as focusLift(in:).
    /// Order preserved, duplicates dropped.
    func focusLifts(in catalog: [Exercise]) -> [Exercise] {
        var seen: Set<UUID> = []
        var lifts: [Exercise] = []
        for raw in values("focus_lift") {
            let resolved: Exercise?
            if let id = UUID(uuidString: raw) {
                resolved = catalog.first { $0.id == id }
            } else {
                resolved = Self.resolveByName(raw, in: catalog)
            }
            if let lift = resolved, !seen.contains(lift.id) {
                seen.insert(lift.id)
                lifts.append(lift)
            }
        }
        return lifts
    }

    /// The catalog exercise behind the athlete's answer to "which lift is
    /// the number on?".
    ///
    /// Forgiving on purpose — people type "bench", not "Barbell Bench
    /// Press". An exact match wins, then a containment match, and an
    /// answer that matches nothing resolves to nothing rather than to the
    /// first plausible row: silently focusing the wrong lift is worse
    /// than focusing none, because the athlete would never see it happen.
    func focusLift(in catalog: [Exercise]) -> Exercise? {
        focusLifts(in: catalog).first
    }

    private static func resolveByName(_ raw: String, in catalog: [Exercise]) -> Exercise? {
        let typed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard typed.count >= 3 else { return nil }
        if let exact = catalog.first(where: { $0.name.lowercased() == typed }) { return exact }
        let matches = catalog.filter { $0.name.lowercased().contains(typed) }
        if matches.count == 1 { return matches.first }
        // Several rows contain what they typed — "bench" hits incline,
        // decline and close-grip too. The shortest name is the plainest
        // variant, and it wins only when it is unambiguously the shortest.
        guard let shortest = matches.map(\.name.count).min() else { return nil }
        let plainest = matches.filter { $0.name.count == shortest }
        return plainest.count == 1 ? plainest.first : nil
    }

    /// Weeks to the date. Free text; a date the athlete cannot state
    /// leaves duration alone rather than guessing one.
    var durationWeeks: Int? {
        guard let raw = first("the_date"), let weeks = Int(raw.filter(\.isNumber)),
              (1...52).contains(weeks) else { return nil }
        return weeks
    }

    var effort: GeneratorScience.EffortAppetite? {
        first("effort").flatMap(GeneratorScience.EffortAppetite.init(rawValue:))
    }

    /// Standing rules — durable across blocks, so they go to
    /// public.training_rules rather than onto the profile.
    var standingRules: [String] {
        values("standing_rule")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 280 }
    }

    /// Cold-start anchors, destined for UserSettings.liftAnchors. Stored
    /// as "<lift>=<weight>" pairs by the view.
    var liftAnchors: [String: Decimal] {
        var anchors: [String: Decimal] = [:]
        for entry in values("anchor_lifts") {
            let parts = entry.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  let weight = Decimal(string: String(parts[1])), weight > 0 else { continue }
            anchors[String(parts[0])] = weight
        }
        return anchors
    }

    // MARK: - Apply

    /// Fold every answer into the profile. Unanswered probes leave their
    /// fields exactly as they were — the consult refines what the five
    /// doors set and never resets it.
    func apply(to profile: TrainingProfile,
               catalog: [Exercise] = []) -> TrainingProfile {
        var p = profile

        func state(_ key: String) { p.provenance[key] = .stated }

        if let focus = focusMuscles(in: catalog) {
            p.focusMuscles = focus.sorted()
            state("focusMuscles")
        }
        let lifts = focusLifts(in: catalog)
        if !lifts.isEmpty {
            p.focusExerciseIDs = lifts.map(\.id)
            state("focusExerciseIDs")
        }
        if let opener = first("opener") {
            p.rankedGoals = Self.goals(forOpener: opener)
            state("rankedGoals")
        }
        // The symptom refines the goal the opener set, and only for the
        // diagnostic doors — it must never overwrite an athlete who came
        // in naming a number.
        if let symptom = first("whats_off"), let goals = Self.goals(forSymptom: symptom) {
            p.rankedGoals = goals
            state("rankedGoals")
        }
        if let sport = first("the_date"), !sport.isEmpty {
            p.sportPrepSport = Self.sport(in: sport) ?? p.sportPrepSport
            if p.sportPrepSport != nil { state("sportPrepSport") }
        }
        // Commitment: taking the work sets the days it needs; keeping the
        // current cadence leaves the stated number alone, because the
        // honest trade is a LONGER block, not a broken promise.
        if let days = first("days").flatMap({ Int($0.filter(\.isNumber)) }),
           (1...7).contains(days) {
            p.daysPerWeek = days
            state("daysPerWeek")
        }
        // The view records the commitment as ["commit", "<days>"] — the
        // number the athlete was actually shown, so what we write is what
        // they agreed to rather than a default recomputed afterwards.
        let commitment = values("commitment")
        if commitment.first == "commit", commitment.count > 1,
           let days = Int(commitment[1]), (1...7).contains(days) {
            p.daysPerWeek = days
            state("daysPerWeek")
        }
        if let minutes = first("session_length").flatMap({ Int($0) }), minutes > 0 {
            p.sessionMinutes = minutes
            state("sessionMinutes")
        }
        let equipment = values("equipment").filter(Venue.equipmentClasses.contains)
        if !equipment.isEmpty {
            p.equipment = Set(equipment)
            state("equipment")
        }
        if let appetite = first("rep_appetite") {
            p.repAppetite = appetite
            state("repAppetite")
        }
        if let variety = first("accessory_variety").flatMap(
                TrainingProfile.AccessoryVariety.init(rawValue:)) {
            p.accessoryVariety = variety
            state("accessoryVariety")
        }
        if let climb = first("climb_rate") {
            p.intensityAppetite = climb
            state("intensityAppetite")
        }
        if let feel = first("session_feel") {
            // "Out of breath" is a STRUCTURE answer (circuits and short
            // rests produce it), not a cardio prescription bolted on.
            p.sessionStructure = feel == "breath" ? .circuit : .straight
            state("sessionStructure")
        }
        // Cardio style has two possible sources; the explicit engine
        // question outranks the inferred one.
        if let style = first("engine_kind").flatMap(TrainingProfile.CardioStyle.init(rawValue:)) {
            p.cardioStyle = style
            state("cardioStyle")
        } else if first("whats_off") == "breath" {
            p.cardioStyle = .steady
            state("cardioStyle")
        }
        let joints = values("cautions").filter { !$0.isEmpty }
        if !joints.isEmpty {
            // Union, never replace: a joint named in a previous consult is
            // not healed by going unmentioned in this one.
            p.cautionJoints = Array(Set(p.cautionJoints).union(joints)).sorted()
            state("cautionJoints")
        }
        let patterns = values("wont_do").filter { !$0.isEmpty }
        if !patterns.isEmpty {
            p.excludedPatterns = Array(Set(p.excludedPatterns).union(patterns)).sorted()
            state("excludedPatterns")
        }
        // Comfort is a multi-select over a CLOSED list, so an unpicked
        // probe is a "no", not a silence — and the distinction matters:
        // GeneratorScience.derivedComplexityCap reads an empty dictionary
        // as "never asked" and returns nil, so recording only the yeses
        // would leave an athlete who is comfortable with NOTHING carrying
        // whatever training age was guessed for them, instead of the
        // honest floor of 2. Keying off whether the probe was answered
        // (not whether anything was picked) is what makes "none of these"
        // a real answer.
        if let picked = byProbe["gym_comfort"] {
            var comfort = p.comfortAnswers ?? [:]
            // The ladder (ComfortLadderView) reports its verdict as a
            // "cap=N" token: the highest complexity rung the athlete fully
            // confirmed against real catalog lifts. The comfort dictionary
            // is then DERIVED from the cap (every probe at or under it is
            // a yes) so anything still reading it sees a consistent
            // answer. The legacy checklist path - picked probe slugs, no
            // token - keeps its original derivation.
            if let token = picked.first(where: { $0.hasPrefix("cap=") }),
               let cap = Int(token.dropFirst(4)) {
                let bounded = max(1, min(5, cap))
                for probe in GeneratorScience.comfortProbes {
                    comfort[probe.slug] = probe.complexity <= bounded
                }
                p.comfortAnswers = comfort
                p.derivedComplexityCap = bounded
            } else {
                for probe in GeneratorScience.comfortProbes {
                    comfort[probe.slug] = picked.contains(probe.slug)
                }
                p.comfortAnswers = comfort
                p.derivedComplexityCap = GeneratorScience.derivedComplexityCap(from: comfort)
            }
            state("comfortAnswers")
            state("derivedComplexityCap")
        }
        return p
    }

    /// Sports the generator has a real lens for. Anything else leaves the
    /// sport unset rather than claiming a lens that does not exist —
    /// there is no generic "sport mode", and pretending otherwise would
    /// put a football prescription in front of a swimmer.
    static func sport(in text: String) -> String? {
        let lowered = text.lowercased()
        for sport in ["football", "baseball", "wrestling"] where lowered.contains(sport) {
            return sport
        }
        return nil
    }
}
