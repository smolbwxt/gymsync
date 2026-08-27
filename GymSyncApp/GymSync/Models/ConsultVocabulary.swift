import Foundation

// MARK: - ConsultVocabulary
//
// What a probe's chips SAY, and where the words come from.
//
// The rule that shapes this file: a chip must offer a value the rest of
// the system already recognises. Offering "lower back" when the catalog
// labels it "low_back" produces a caution that silently does nothing —
// the athlete tells us where it hurts, we write it down, and selection
// never sees it. So the constraint vocabularies are DERIVED from the
// loaded catalog rather than typed out here, and the focus vocabulary
// comes from GeneratorScience.majorMuscles, which is the same list the
// coverage check reads.
//
// Only genuinely open answers stay free text (which lift, which date,
// what weight, what rule) — everything a label taxonomy owns is a chip.
enum ConsultVocabulary {

    /// Probes where more than one answer is true at once.
    static let multiSelect: Set<String> = [
        "equipment", "focus_areas", "gym_comfort", "cautions", "wont_do",
        // The focus-lift picker (2026-08-27) shares the multi-select
        // commit path; its values are exercise ids.
        "focus_lift",
        // Severity rows: values are "<joint>=severe" for injured joints;
        // an unmarked joint is a caution.
        "injury_severity",
    ]

    static func isMultiSelect(_ probeID: String) -> Bool {
        multiSelect.contains(probeID)
    }

    /// The seven joints the catalog labels (shoulder 461 rows, lower_back
    /// 308, knee 240, elbow 179, wrist 170, hip 115, ankle 2 - measured
    /// 2026-08-27). Pinned rather than derived-only because the probe
    /// rendered as FREE TEXT whenever the catalog was empty or late, and a
    /// typed "knees" never matched the label "knee" - a caution the
    /// athlete gave and selection never saw.
    static let knownJoints: [(id: String, detail: String)] = [
        ("shoulder",   "Pressing overhead, dips, wide-grip work"),
        ("lower_back", "Deadlifts, heavy squats, bent-over rows"),
        ("knee",       "Deep squats, lunges, step-ups"),
        ("elbow",      "Curls, skull crushers, close-grip pressing"),
        ("wrist",      "Front rack, push-ups, heavy holds"),
        ("hip",        "Deep hinges, sumo stance, wide squats"),
        ("ankle",      "Deep squats, jumps, calf work"),
    ]

    /// Joints a caution can land on: the pinned seven, plus anything
    /// else the loaded catalog labels.
    static func joints(in catalog: [Exercise]) -> [String] {
        let pinned = knownJoints.map(\.id)
        let extra = Set(catalog.flatMap { $0.jointStress ?? [] }).subtracting(pinned)
        return pinned + extra.sorted()
    }

    /// Movement patterns the catalog actually carries.
    static func patterns(in catalog: [Exercise]) -> [String] {
        Array(Set(catalog.compactMap(\.movementPattern))).sorted()
    }

    /// The chips for a probe, or [] when the honest answer is free text.
    static func options(for probe: ConsultProbe.Probe,
                        catalog: [Exercise]) -> [ConsultProbe.Option] {
        if !probe.options.isEmpty { return probe.options }
        switch probe.id {
        case "equipment":
            return Venue.equipmentClasses.map {
                ConsultProbe.Option(id: $0, label: display($0))
            }
        case "focus_areas":
            return GeneratorScience.majorMuscles.map {
                ConsultProbe.Option(id: $0, label: display($0))
            }
        case "gym_comfort":
            // The comfort ladder carries its own copy — each probe has a
            // plain-language detail written for someone who has never
            // been in a gym, which is exactly who answers it.
            return GeneratorScience.comfortProbes.map {
                ConsultProbe.Option(id: $0.slug, label: $0.name.uppercased(),
                                    detail: $0.detail)
            }
        case "cautions":
            let details = Dictionary(uniqueKeysWithValues: knownJoints.map { ($0.id, $0.detail) })
            return joints(in: catalog).map {
                ConsultProbe.Option(id: $0, label: display($0), detail: details[$0])
            }
        case "wont_do":
            return patterns(in: catalog).map {
                ConsultProbe.Option(id: $0, label: display($0))
            }
        case "days":
            return (1...7).map {
                ConsultProbe.Option(id: "\($0)", label: $0 == 1 ? "1 DAY" : "\($0) DAYS")
            }
        default:
            return []
        }
    }

    /// A catalog slug as a chip reads it. Nothing clever — the taxonomy's
    /// own words, made legible.
    static func display(_ slug: String) -> String {
        slug.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    /// "bench 135, squat 185" → ["bench=135", "squat=185"], the pair form
    /// ConsultAnswers.liftAnchors reads.
    ///
    /// Deliberately forgiving about the lift name and strict about the
    /// number: a lift we cannot match still gets stored (the athlete's
    /// own word for it is better than nothing), but a chunk with no
    /// number is DROPPED rather than stored at zero, because a zero
    /// anchor seeds the entire progression at nothing. Someone typing
    /// "I've never benched" gets that chunk ignored, which is what the
    /// probe's own clarifier promises.
    static func parseAnchors(_ text: String) -> [String] {
        text.split(separator: ",").compactMap { chunk -> String? in
            let parts = chunk.split(separator: " ").map(String.init)
                .filter { !$0.isEmpty }
            guard parts.count >= 2 else { return nil }
            let digits = parts[parts.count - 1].filter { $0.isNumber || $0 == "." }
            guard !digits.isEmpty, let value = Double(digits), value > 0 else { return nil }
            let name = parts.dropLast().joined(separator: "_").lowercased()
            guard !name.isEmpty else { return nil }
            return "\(name)=\(digits)"
        }
    }

    /// Free-text probes need a prompt that says what shape of answer is
    /// useful; a bare cursor gets a bare answer.
    static func placeholder(for probeID: String) -> String {
        switch probeID {
        case "focus_lift":     return "bench press"
        case "the_date":       return "state meet, 10 weeks out"
        case "anchor_lifts":   return "bench 135, squat 185"
        case "standing_rule":  return "pulls before arms"
        case "injury_severity": return "working around it"
        default:               return "type your answer"
        }
    }
}
