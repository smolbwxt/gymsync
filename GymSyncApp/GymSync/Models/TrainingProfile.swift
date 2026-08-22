import Foundation
import Supabase

// MARK: - TrainingProfile
//
// The athlete, as data the generator can read (design spec
// 2026-08-20-coach-training-profile-design.md). The architecture in one
// line: personality = profile prior + voice, conversation = delta,
// PROFILE = TRUTH, generator = the only thing that prescribes.
//
// Three field classes with three override semantics:
// - Ranked goals: elicited as an ORDERING (people can rank; nobody can
//   emit "0.45"), converted to weights deterministically.
// - Preferences: persona-seeded, athlete-overridable; science pushes back
//   exactly once, with a citation, then respects the answer.
// - Hard constraints: NEVER overridden — not by weights, not by personas,
//   not by science. An exclusion carries its reason class because reason
//   determines blast radius.
//
// Goal support is TIERED (owner 2026-08-20): all nine goals live in the
// schema from day one so it never migrates; five get full band treatment,
// three ride as selection weights, sport_prep acts as a context modifier.
// Blending is DOMINANT-BAND + WEIGHTED SELECTION (owner 2026-08-20): the
// top-ranked goal drives prescriptions so they stay crisp — the corpus
// warns that parallel blending stalls both goals (RP: pivot to
// specialization blocks, which Phase 4 makes mechanical over time).

// MARK: - Persistence
//
// One `training_profiles` row per athlete (20260820000002): jsonb payload
// versioned in code — the Codable schema IS the contract, so the table
// never migrates when a field lands. Best-effort semantics: a lifter with
// no profile row gets the neutral defaults, which reproduce the
// pre-profile generator exactly.
enum TrainingProfileRepository {
    private struct Row: Decodable {
        let payload: TrainingProfile
        let version: Int
    }

    /// The three body fields of a CLIENT's profile, for the trainer tab
    /// - served by a narrow RPC (20260821000006) so the body_weight
    /// scope never exposes goals or injury history. Empty when the
    /// scope is off, the relationship inactive, or nothing is stated.
    struct ClientBodyContext: Decodable {
        let bodyweightLbs: Double?
        let heightInches: Double?
        let bodyFatPercent: Double?
        enum CodingKeys: String, CodingKey {
            case bodyweightLbs = "bodyweight_lbs"
            case heightInches = "height_inches"
            case bodyFatPercent = "body_fat_percent"
        }
        var bmi: Double? {
            guard let w = bodyweightLbs, let h = heightInches, w > 0, h > 0 else { return nil }
            return w / (h * h) * 703
        }
    }

    static func clientBodyContext(clientID: UUID) async -> ClientBodyContext? {
        let rows: [ClientBodyContext]? = try? await SupabaseService.shared.client
            .rpc("client_body_context", params: ["p_client_id": clientID.uuidString])
            .execute()
            .value
        return rows?.first
    }

    static func load() async throws -> TrainingProfile? {
        do {
            let rows: [Row] = try await SupabaseService.shared.client
                .from("training_profiles")
                .select("payload, version")
                .execute().value
            return rows.first?.payload    // RLS scopes to the caller
        } catch { throw ErrorMapping.map(error) }
    }

    static func save(_ profile: TrainingProfile, userID: UUID) async throws {
        struct Upsert: Encodable {
            let user_id: UUID
            let payload: TrainingProfile
            let version: Int
        }
        do {
            try await SupabaseService.shared.client
                .from("training_profiles")
                .upsert(Upsert(user_id: userID, payload: profile, version: 1))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}

enum TrainingGoal: String, Codable, CaseIterable, Sendable {
    case hypertrophy
    case maxStrength = "max_strength"
    case powerRFD = "power_rfd"
    case conditioning
    case fatLoss = "fat_loss"
    case boneDensity = "bone_density"
    case mobility
    case sportPrep = "sport_prep"
    case generalHealth = "general_health"
}

/// Where a profile field's value came from — this gates how freely Coach
/// may later challenge it. Persona defaults are challengeable any time;
/// stated goals only with accumulated drift evidence; hard constraints
/// never (injuries heal on the athlete's say-so, not ours).
enum FieldProvenance: String, Codable, Sendable {
    case personaDefault = "persona_default"
    case stated
    case inferred
    case confirmed
}

struct TrainingProfile: Codable, Equatable, Sendable {

    // MARK: Identity
    enum TrainingAge: String, Codable, CaseIterable, Sendable {
        case novice, intermediate, advanced
        var experience: GeneratorScience.Experience {
            switch self {
            case .novice: return .new
            case .intermediate: return .intermediate
            case .advanced: return .advanced
            }
        }
    }
    var trainingAge: TrainingAge = .intermediate
    /// Derived experience (spec 2026-08-22): the comfort-probe answers
    /// (slug -> comfortable) and the cap they derive. When present, the
    /// cap feeds the selection gate DIRECTLY (finer than three buckets)
    /// and trainingAge is derived, never picked. Legacy profiles keep
    /// their stored trainingAge until they answer.
    var comfortAnswers: [String: Bool]? = nil
    var derivedComplexityCap: Int? = nil
    /// Sex, for the evidence-scaled adjustments the generator already
    /// carries (female rep-top bonus, accessory rest delta, volume
    /// ceiling nudge). Stored as the raw string so the profile's Codable
    /// schema never depends on another type's conformances.
    var sexRaw: String = GeneratorScience.Sex.unspecified.rawValue
    var sex: GeneratorScience.Sex {
        get { GeneratorScience.Sex(rawValue: sexRaw) ?? .unspecified }
        set { sexRaw = newValue.rawValue }
    }
    /// under18 | adult | middle | senior — age shapes defaults (a senior
    /// prior weights bone_density and cardio_health), never gates.
    var ageBand: String? = nil
    // MARK: Body context (field report #22 — "body scan input")
    // Athlete-reported measurements, all optional: an absent field
    // changes nothing. Canonical units are pounds/inches (display
    // converts) so the stored payload never depends on a settings row.
    var bodyweightLbs: Double? = nil
    var heightInches: Double? = nil
    var bodyFatPercent: Double? = nil
    var bmi: Double? {
        guard let w = bodyweightLbs, let h = heightInches, w > 0, h > 0 else { return nil }
        return w / (h * h) * 703
    }
    /// High-impact work (jumps, bounding) sits out while landings — not
    /// effort — are the joint hazard: 30%+ bodyfat or BMI 30+, the
    /// field-standard lines. Soft like every gate, and it reads as an
    /// advisory note so the athlete hears WHY, never a silent edit.
    var impactCaution: Bool {
        if let bf = bodyFatPercent, bf >= 30 { return true }
        if let bmi, bmi >= 30 { return true }
        return false
    }
    /// The persona whose defaults seeded this profile, if any.
    var persona: String? = nil
    /// football | baseball | wrestling — set when sport_prep is ranked;
    /// drives the generator's sport lens and prophylaxis dose.
    var sportPrepSport: String? = nil

    // MARK: Goals (RANKED — order IS the data)
    var rankedGoals: [TrainingGoal] = [.hypertrophy]

    // MARK: Preferences (persona-seeded, athlete-overridable)
    var split: GeneratorScience.SplitPreference = .auto
    var daysPerWeek: Int = 3
    var sessionMinutes: Int? = nil
    /// heavy_low | moderate | high_rep_pump
    var repAppetite: String? = nil
    /// conservative | standard | aggressive — feeds progression.
    var intensityAppetite: String = "standard"
    /// SESSION STRUCTURE — a separate axis from the split (corpus census
    /// 2026-08-20: the split says which muscles which day; the structure
    /// says how the session runs). Supersets/antagonist pairing is the
    /// single most-discussed style in the corpus (173 videos, 12
    /// channels); minimalist (30/9) and circuit (22/10) follow.
    enum SessionStructure: String, Codable, CaseIterable, Sendable {
        case straight, supersets, circuit, minimalist
    }
    var sessionStructure: SessionStructure = .straight
    /// intervals (zone-4 HIIT) | steady (zone-2 LISS) | auto — rides the
    /// existing cardio zone machinery; a preference, not new science.
    enum CardioStyle: String, Codable, CaseIterable, Sendable {
        case auto, intervals, steady
    }
    var cardioStyle: CardioStyle = .auto

    // MARK: Hard constraints (nothing overrides these)
    struct Exclusion: Codable, Equatable, Sendable {
        let exerciseID: UUID
        /// injury_pain | dislike | skill | equipment — the reason class
        /// sets the blast radius: an injury excludes the movement FAMILY
        /// and cautions the joint; a dislike excludes one lift, and the
        /// substitution graph fills the hole.
        var reasonClass: String = "dislike"
        /// Set for injury_pain exclusions — propagates to `cautionJoints`.
        var joint: String? = nil
    }
    var exclusions: [Exclusion] = []
    /// Movement patterns excluded wholesale (e.g. "push_vertical" for a
    /// shoulder that tolerates no overhead work).
    var excludedPatterns: [String] = []
    /// Joints to deprioritize: exercises labeled joint_stress:<joint>
    /// sort last in selection (soft, like the complexity gate — never
    /// leaves a hole).
    var cautionJoints: [String] = []
    var equipment: Set<String>? = nil

    // MARK: Provenance (field name -> where its value came from)
    var provenance: [String: FieldProvenance] = [:]

    // MARK: Carryover — the relationship's memory (Phase 4 lifecycle)
    //
    // Block N's outcomes, folded here by CoachLifecycle when a block
    // ends, seed block N+1: the goal history drives the block planner's
    // alternation, abandoned lifts sort last next time, and attendance
    // informs the day-count conversation. History informing the future,
    // as data on the same profile everything else reads.
    struct Carryover: Codable, Equatable, Sendable {
        /// Every block's goal, in order — BlockPlanner's ledger.
        var blockGoalHistory: [TrainingGoal] = []
        /// Lifts the athlete kept skipping last block.
        var deprioritizedExerciseIDs: [UUID] = []
        /// What last block's attendance actually supported.
        var suggestedDaysPerWeek: Int? = nil
        var strugglingLiftIDs: [UUID] = []
        var lastAdherence: Double? = nil
        /// Novice finished a block at 75%+ — the graduation offer stands
        /// until answered.
        var pendingGraduation: Bool = false
    }
    var carryover: Carryover? = nil
    /// Drift-probe cooldown ledger (DriftDetector's ~2-week cadence).
    var lastProbeAt: Date? = nil

    // MARK: - Derivations (deterministic; the generator reads these)

    /// Ranking -> weights by linear decay, normalized to sum 1. First of
    /// n goals gets n shares, last gets 1 — explainable to the athlete in
    /// one sentence, stable under appending a new last-place goal.
    var goalWeights: [TrainingGoal: Double] {
        let goals = rankedGoals.isEmpty ? [.hypertrophy] : rankedGoals
        let n = goals.count
        let total = Double(n * (n + 1)) / 2
        var out: [TrainingGoal: Double] = [:]
        for (index, goal) in goals.enumerated() {
            out[goal, default: 0] += Double(n - index) / total
        }
        return out
    }

    var dominantGoal: TrainingGoal { rankedGoals.first ?? .hypertrophy }

    /// THIS block's goal: the planner's proportional alternation over the
    /// goal history (a 70/30 profile runs hyp, str, hyp, hyp…). With no
    /// history it reduces to the dominant goal, so every pre-carryover
    /// behavior is unchanged.
    var blockGoal: TrainingGoal {
        BlockPlanner.nextBlockGoal(profile: self,
                                   history: carryover?.blockGoalHistory ?? [])
    }

    /// The block goal's focus for split/slots/scoring tables. Tiered
    /// support: the three weight-only goals ride the closest full band —
    /// bone density's active ingredient is heavy axial loading (strength
    /// tables + spinal-load selection weight), mobility and general
    /// health ride hypertrophy's balanced template.
    var generatorFocus: GeneratorScience.Focus {
        switch blockGoal {
        case .maxStrength, .powerRFD, .boneDensity: return .strength
        case .hypertrophy, .mobility, .generalHealth, .sportPrep: return .hypertrophy
        case .conditioning: return .conditioning
        case .fatLoss: return .weightLoss
        }
    }

    /// Band override for goals whose prescription SHAPE differs from
    /// their focus table — power wants submaximal speed work, not
    /// grinding triples.
    var bandOverride: GeneratorScience.FocusBand? {
        blockGoal == .powerRFD ? GeneratorScience.powerBand : nil
    }

    /// Selection tilt over the label taxonomy's focus-score keys
    /// (strength | hypertrophy | weight_loss | conditioning), from the
    /// FULL weight vector — this is where the 0.3-weighted secondary goal
    /// actually shows up in what gets picked.
    var selectionWeights: [String: Double] {
        var out: [String: Double] = [:]
        for (goal, weight) in goalWeights {
            let keys: [(String, Double)]
            switch goal {
            case .maxStrength: keys = [("strength", 1)]
            case .powerRFD: keys = [("strength", 1)]
            case .hypertrophy: keys = [("hypertrophy", 1)]
            case .fatLoss: keys = [("weight_loss", 1)]
            case .conditioning: keys = [("conditioning", 1)]
            case .boneDensity: keys = [("strength", 0.6)]
            case .mobility: keys = []          // category-level, not score-level
            case .sportPrep: keys = [("strength", 0.5), ("conditioning", 0.5)]
            case .generalHealth:
                keys = [("strength", 0.25), ("hypertrophy", 0.25),
                        ("weight_loss", 0.25), ("conditioning", 0.25)]
            }
            for (key, share) in keys { out[key, default: 0] += weight * share }
        }
        return out
    }

    /// Bone density in the ranking (any position) boosts axially-loading
    /// exercises in selection — spinalLoad is the label that carries it.
    var wantsAxialLoading: Bool { rankedGoals.contains(.boneDensity) }

    /// In-season sport prep caps intensity and volume: practice and games
    /// are recovery debits training must respect. Set by the wizard when
    /// sport_prep is ranked and the athlete says they're in season.
    var inSeason: Bool = false

    // MARK: - The generator handoff

    /// Every profile field lands in an `Inputs` field the generator
    /// provably reads — the no-dead-knobs law. Injury propagation happens
    /// HERE (owner 2026-08-20: lift out + joint cautioned): an injury_pain
    /// exclusion's joint joins the caution set; pattern-wide exclusion
    /// stays an explicit athlete choice, never a silent escalation.
    func generatorInputs(durationWeeks: Int,
                         cardioDays: Int = 0,
                         cardioMinutes: Int = 20,
                         fillWeekWithRecovery: Bool = false,
                         focusMuscles: Set<String>? = nil,
                         seed: Int = 0) -> ProgramGenerator.Inputs {
        var inputs = ProgramGenerator.Inputs(
            focus: generatorFocus,
            daysPerWeek: daysPerWeek,
            durationWeeks: durationWeeks,
            experience: trainingAge.experience)
        inputs.focusMuscles = focusMuscles
        inputs.equipment = equipment
        inputs.cardioDays = cardioDays
        inputs.cardioMinutes = cardioMinutes
        inputs.fillWeekWithRecovery = fillWeekWithRecovery
        inputs.sessionMinutes = sessionMinutes
        inputs.seed = seed
        inputs.splitPreference = split
        inputs.sessionStructure = sessionStructure
        inputs.cardioStyle = cardioStyle
        inputs.bandOverride = bandOverride
        inputs.selectionTilt = selectionWeights
        inputs.excludedExerciseIDs = Set(exclusions.map(\.exerciseID))
        // Carryover (Phase 4): last block's skipped lifts sort last; a
        // multi-goal profile past block one names its alternation.
        if let carryover {
            inputs.deprioritizedExerciseIDs = Set(carryover.deprioritizedExerciseIDs)
            if !carryover.blockGoalHistory.isEmpty, goalWeights.count > 1 {
                inputs.advisoryNotes.append("Block \(carryover.blockGoalHistory.count + 1): \(blockGoal.rawValue.replacingOccurrences(of: "_", with: " ")) leads — multi-goal training runs as alternating specialization blocks (the corpus's answer to stalling both goals at once).")
            }
        }
        inputs.excludedPatterns = Set(excludedPatterns)
        inputs.cautionJoints = Set(cautionJoints.map { $0.lowercased() })
            .union(exclusions.compactMap { exclusion in
                exclusion.reasonClass == "injury_pain" ? exclusion.joint?.lowercased() : nil
            })
        inputs.axialBoost = wantsAxialLoading
        inputs.inSeason = inSeason
        inputs.impactCaution = impactCaution
        inputs.complexityCapOverride = derivedComplexityCap
        // Sport lens rides only when the sport_prep goal is actually
        // ranked — a stale sport choice never haunts a changed goal set.
        if rankedGoals.contains(.sportPrep), let sport = sportPrepSport {
            inputs.sportPrepSport = sport
            switch sport {
            case "football":
                inputs.advisoryNotes.append("Football lens: unilateral lower-body work ranks up and explosive work gets a daily slot — in-season, sessions shorten and volume, not intensity, is the release valve.")
            case "baseball":
                inputs.advisoryNotes.append("Baseball lens: arm care is a standing dose — cuff work rides your pressing days, because velocity without cuff strength is how elbows and shoulders break.")
            case "wrestling":
                inputs.advisoryNotes.append("Wrestling lens: unilateral work leads (stance and shots are one-sided) and grip gets its own slot on pulling days.")
            default:
                break
            }
        }
        if impactCaution {
            inputs.advisoryNotes.append("High-impact work (jumps, bounding) sits out for now — landings are the one place current bodyweight raises joint risk. It comes back as the number moves; nothing else changes.")
        }
        inputs.sex = sex
        inputs.intensityAppetite = intensityAppetite
        // The chosen coach's selection stances ride along — the persona
        // reaches the generator ONLY through profile fields and this lens;
        // there is no persona code path. A power_rfd DOMINANT goal grants
        // the (bounded) explosive emphasis itself — the footballer gets
        // jumps without needing the Hybrid coach (audit 2026-08-20).
        var lens = CoachPersona.bySlug(persona)?.lens ?? CoachPersona.Lens()
        if blockGoal == .powerRFD { lens.explosiveEmphasis = true }
        // Football's corpus position: explosive work is a first-class
        // citizen — same bounded grant the power_rfd goal carries
        // (one main slot per day, never accessories).
        if rankedGoals.contains(.sportPrep), sportPrepSport == "football" {
            lens.explosiveEmphasis = true
        }
        inputs.personaLens = lens
        // Honesty lines (audit round 2): say what can't be honored.
        if split == .bro, daysPerWeek < 4 {
            inputs.advisoryNotes.append("A bodypart split needs 4+ days — full-body carries the work until more days free up, and the pump pieces ride along where they fit.")
        }
        if split == .hybrid, daysPerWeek < 5 {
            inputs.advisoryNotes.append("The hybrid split needs 5+ days — below that, the science ladder already gives every muscle its second weekly touch.")
        }
        // Field #43: mobility as standing counsel, not just a goal -
        // one line, once, injury-avoidance framing. Owner refinement
        // 2026-08-22: when the session cap leaves no room for it, never
        // pretend it fits - route it OUTSIDE the gym (named at-home
        // stretches) or offer the extra day Coach can book.
        if !rankedGoals.contains(.mobility) {
            if sessionMinutes != nil {
                inputs.advisoryNotes.append("Your sessions are time-capped, so mobility lives outside the gym: 10–15 minutes at home once a week — couch stretch and 90/90 for hips, doorway pec stretch and wall slides for shoulders. Or add a recovery day and Coach will put it on the schedule. Cheap insurance against the injuries that end programs.")
            } else {
                inputs.advisoryNotes.append("Once a week, give 10–15 minutes to mobility — stretching after a session counts. Your deload week doubles as a mobility week; it's cheap insurance against the injuries that end programs.")
            }
        }
        if blockGoal == .mobility {
            inputs.advisoryNotes.append("Mobility leads your goals: today it shapes the picks and the recovery prescriptions — a dedicated mobility modality is still being built, and this lifting meanwhile moves you better than stretching alone would.")
        }
        return inputs
    }
}
