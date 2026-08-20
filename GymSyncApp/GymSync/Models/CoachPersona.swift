import Foundation

// MARK: - CoachPersona
//
// The chess.com-bots idea made mechanical (owner 2026-08-20): the athlete
// keeps their GOAL; the coach they pick shapes the METHOD. A persona is
// nothing but a preset — profile method fields plus selection-lens
// weights — that passes through the SAME generator as everyone else
// (owner: "no matter what, everyone always passes through the generator;
// the presets just make onboarding easier"). No persona ever gets its own
// code path, and no persona ever overrides something the athlete has
// STATED — provenance gates every field it touches.
//
// Each archetype is derived from a real philosophy cluster in the
// educational-fitness corpus, and each takes a SIDE where the corpus
// itself splits (the 9 contested exercise-goal pairs, the captured
// disagreements). Stances are expressed through LABEL-SPACE lenses
// (fatigue aversion, stretch emphasis, barbell-first) — deterministic and
// testable, never per-exercise opinion lists. Archetypes only; never a
// real person's name (publicity rights).

struct CoachPersona: Identifiable, Equatable, Sendable {

    /// Selection stance weights — consumed by `ProgramGenerator.select`.
    /// Every flag maps to labels the catalog already carries.
    struct Lens: Equatable, Sendable {
        /// Subtract fatigueCost from the score — the corpus's
        /// squat-hypertrophy skeptic side ("stimulus per unit fatigue").
        var fatigueAverse = false
        /// Lengthened-position work scores up for ALL accessories, not
        /// just hypertrophy's default stretch tiebreak.
        var stretchEmphasis = false
        /// Accessories prefer the bar (flips the machine-first accessory
        /// ladder) — the strength-purist tradition.
        var barbellFirst = false
        /// Explosive-labeled lifts score up — the hybrid/field-athlete
        /// coach.
        var explosiveEmphasis = false
    }

    var id: String { slug }

    let slug: String
    let name: String
    /// One-line pitch for the picker card.
    let tagline: String
    /// The coaching philosophy in the coach's voice — the debrief and
    /// note-rendering layers read this later; the generator never does.
    let philosophy: String
    /// Personalities are a PRO feature (owner); the house coach is free.
    var isPro = true

    // The method preset — only fields whose provenance allows it apply.
    var split: GeneratorScience.SplitPreference = .auto
    var sessionStructure: TrainingProfile.SessionStructure = .straight
    var cardioStyle: TrainingProfile.CardioStyle = .auto
    /// heavy_low | moderate | high_rep_pump (nil = no opinion).
    var repAppetite: String? = nil
    /// conservative | standard | aggressive.
    var intensityAppetite: String = "standard"
    var lens = Lens()

    // MARK: Application

    /// Seed a profile with this coach's method. A field is written ONLY
    /// when the athlete hasn't stated it (no provenance, or an earlier
    /// persona's default) — switching coaches re-seeds coach opinions and
    /// never touches athlete facts. Goals and hard constraints are the
    /// athlete's alone; a persona cannot reach them by construction.
    func apply(to profile: TrainingProfile) -> TrainingProfile {
        var profile = profile
        func seedable(_ field: String) -> Bool {
            switch profile.provenance[field] {
            case .none, .personaDefault: return true
            case .stated, .confirmed, .inferred: return false
            }
        }
        if seedable("split") {
            profile.split = split
            profile.provenance["split"] = .personaDefault
        }
        if seedable("sessionStructure") {
            profile.sessionStructure = sessionStructure
            profile.provenance["sessionStructure"] = .personaDefault
        }
        if seedable("cardioStyle") {
            profile.cardioStyle = cardioStyle
            profile.provenance["cardioStyle"] = .personaDefault
        }
        if seedable("repAppetite") {
            profile.repAppetite = repAppetite
            profile.provenance["repAppetite"] = .personaDefault
        }
        if seedable("intensityAppetite") {
            profile.intensityAppetite = intensityAppetite
            profile.provenance["intensityAppetite"] = .personaDefault
        }
        profile.persona = slug
        return profile
    }

    static func bySlug(_ slug: String?) -> CoachPersona? {
        guard let slug else { return nil }
        return all.first { $0.slug == slug }
    }

    // MARK: The roster (six, owner 2026-08-20)

    static let all: [CoachPersona] = [
        CoachPersona(
            slug: "the-scientist",
            name: "The Scientist",
            tagline: "Stimulus per unit fatigue. Nothing you can't recover from.",
            philosophy: "Effort is the active ingredient — the last two reps before failure do the building, wherever they happen. Machines are tools, not compromises: stability lets a muscle work to its limit without the fatigue tax. Train the stretch, log everything, and when progress stalls, audit recovery before you touch the program.",
            sessionStructure: .straight,
            repAppetite: "moderate",
            lens: Lens(fatigueAverse: true, stretchEmphasis: true)),
        CoachPersona(
            slug: "the-volume-architect",
            name: "The Volume Architect",
            tagline: "Sets are the currency. Spend them on a schedule.",
            philosophy: "Growth is a dose-response to hard sets, planned in waves: start at your minimum effective volume, add on schedule, deload when the wave crests. A stall usually means the dose is wrong, not the exercise. The plan is the coach — your job is to show up and log honestly.",
            sessionStructure: .straight,
            repAppetite: "moderate",
            lens: Lens(stretchEmphasis: true)),
        CoachPersona(
            slug: "the-golden-era",
            name: "The Golden Era Classic",
            tagline: "One muscle a day. Chase the pump. Leave full.",
            philosophy: "Bodypart days, supersets, and volume you can feel — the classic physique tradition. Each muscle gets its own day and its whole week of work in one focused session. The pump is feedback, the mirror is the judge, and consistency beats cleverness.",
            split: .bro,
            sessionStructure: .supersets,
            cardioStyle: .steady,
            repAppetite: "high_rep_pump"),
        CoachPersona(
            slug: "the-strength-purist",
            name: "The Strength Purist",
            tagline: "The bar doesn't lie. Add weight to it.",
            philosophy: "Strength is a skill practiced with a barbell. A handful of big lifts, heavy, done well, progressed relentlessly — accessories exist only to fix what limits the main lifts. If a session doesn't move the bar forward, it had better be a deload you planned.",
            sessionStructure: .straight,
            repAppetite: "heavy_low",
            intensityAppetite: "aggressive",
            lens: Lens(barbellFirst: true)),
        CoachPersona(
            slug: "the-minimalist",
            name: "The Minimalist",
            tagline: "Three lifts. Full effort. Go live your life.",
            philosophy: "The abbreviated-training tradition: most of the results come from the first hard sets, so do those and leave. Two or three lifts a session, pushed honestly, beat six done tired. Progress lives in the log, not the exercise count — the gym serves your life, never the reverse.",
            sessionStructure: .minimalist,
            repAppetite: "moderate"),
        CoachPersona(
            slug: "the-hybrid-athlete",
            name: "The Hybrid Athlete",
            tagline: "Strong is the floor. Capacity is the ceiling.",
            philosophy: "Be dangerous in every energy system: lift explosively, breathe hard on purpose, and treat work capacity as a skill you train. Circuits and intervals aren't punishment — they're the bridge between gym strength and field speed. The engine matters as much as the chassis.",
            sessionStructure: .circuit,
            cardioStyle: .intervals,
            repAppetite: "moderate",
            lens: Lens(explosiveEmphasis: true)),
    ]
}
