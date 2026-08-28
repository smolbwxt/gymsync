import Foundation

// MARK: - GeneratorScience
//
// The evidence-backed constants the COACH generator computes with. Every
// number here traces to docs/science/generator-evidence.json (the 2026-08
// research pass) or the science audit; confidence gates what gets applied:
//   strong/moderate → encoded as behavior
//   weak            → conservative half-measure, or NOT applied (documented)
//
// THE DO-NOT-CHANGE FINDINGS (strong): %1RM zone boundaries, rep-range
// bands, and exercise selection are IDENTICAL by sex — women train the
// same movements in the same zones (Roberts, Nuckols & Krieger 2020:
// relative gains parity). What sex changes is PHYSIOLOGY: fatigue
// resistance and inter-set recovery (Hunter 2014; Hoeger 1990).
// Menstrual-cycle periodization: NOT implemented (McNulty 2020 — weak,
// inconsistent evidence).
enum GeneratorScience {

    enum Sex: String { case male, female, unspecified }
    enum Experience: String, CaseIterable { case new, intermediate, advanced }
    enum Focus: String, CaseIterable { case strength, hypertrophy, weightLoss, conditioning }

    // MARK: Reps at %1RM (mixed-population baseline; moderate confidence)
    // 60%=16 · 65%=15 · 70%=12 · 75%=10 · 80%=8 · 85%=6 · 90%=4
    static let repsAtPercent: [(percent: Double, reps: Int)] = [
        (60, 16), (65, 15), (70, 12), (75, 10), (80, 8), (85, 6), (90, 4),
    ]

    /// %1RM that supports `reps` clean reps — inverse lookup, linear
    /// between anchors. The generator prescribes loads FROM rep targets.
    static func percentFor(reps: Int) -> Double {
        let table = repsAtPercent.sorted { $0.reps < $1.reps }
        if let exact = table.first(where: { $0.reps == reps }) { return exact.percent }
        guard let first = table.first, let last = table.last else { return 70 }
        if reps <= first.reps { return first.percent }   // very low reps → heaviest anchor
        if reps >= last.reps { return last.percent }
        for (a, b) in zip(table, table.dropFirst()) where reps > b.reps && reps < a.reps {
            // note: table ascending by reps means percent DESCENDS
            let t = Double(reps - b.reps) / Double(a.reps - b.reps)
            return b.percent + t * (a.percent - b.percent)
        }
        // Between anchors ascending: interpolate
        for (a, b) in zip(table, table.dropFirst()) where reps >= a.reps && reps <= b.reps {
            let t = Double(reps - a.reps) / Double(b.reps - a.reps)
            return a.percent + t * (b.percent - a.percent)
        }
        return 70
    }

    // MARK: Muscle vocabulary

    /// The major muscles the generator guarantees coverage of, and the
    /// ONLY list any surface may offer as a focus choice.
    ///
    /// This was a `let` inside balanceWeeklyVolume's coverage check. The
    /// consult needs the same vocabulary to ask "which two areas do you
    /// want to look different?", and a second hand-written copy is how
    /// two lists drift until a surface offers a focus the coverage check
    /// has never heard of. One list, two readers.
    static let majorMuscles = ["chest", "back", "lats", "shoulders", "quads",
                               "hamstrings", "glutes", "biceps", "triceps", "calves"]

    // MARK: Sex deltas (physiology only)

    /// +1 rep on rep-range tops in sub-75% zones for women (conservative
    /// end of Hoeger's +1..+3; ~0 near max — so never applied to
    /// strength-zone main work). unspecified = no delta.
    static func repRangeTopBonus(sex: Sex, repsHigh: Int) -> Int {
        guard sex == .female, repsHigh >= 10 else { return 0 }
        return 1
    }

    /// −15 s accessory rest for women (conservative end of the weak
    /// −15..−30 s finding; main-lift rest untouched — the finding is
    /// scoped ≤85% 1RM).
    static func accessoryRestDelta(sex: Sex) -> Int {
        sex == .female ? -15 : 0
    }

    /// Soft +10% on the top of the weekly focus-volume band for women
    /// (weak-confidence MRV extrapolation — a ceiling nudge, never a
    /// prescription jump).
    static func weeklyVolumeCeilingMultiplier(sex: Sex) -> Double {
        sex == .female ? 1.10 : 1.0
    }

    // MARK: Focus prescriptions (the science table, generator design doc)

    struct FocusBand {
        let mainRepsLow: Int, mainRepsHigh: Int
        let accessoryRepsLow: Int, accessoryRepsHigh: Int
        let mainRestSeconds: Int, accessoryRestSeconds: Int
        let weeklySetsLow: Int, weeklySetsHigh: Int
    }

    /// Accessory rep tops widened 2026-08-20 (corpus consensus: 5-30 reps
    /// grow muscle similarly when effort-matched — far wider than the
    /// 10-15 tops we shipped; higher-rep accessory work also trades axial/
    /// joint load for effort, and the isolation class specifically favors
    /// reps over load since one plate jump is a huge relative step, 3DMJ).
    /// MAINS deliberately keep their strength-specific ranges — heavy
    /// practice is the point of a main, and the corpus warns against
    /// changing rep ranges on lifts that are progressing (HoH). The
    /// per-exercise repMin/repMax clamp still tailors every band, so a
    /// widened top can never reach a lift whose label forbids it.
    /// How close to failure the athlete wants to work. The corpus records
    /// a real split here — Helms treats volume and proximity-to-failure as
    /// substitutable, Nippard treats near-failure effort as required
    /// regardless of set count — which is exactly why this is the
    /// ATHLETE'S call rather than a number we pick for them.
    ///
    /// Values are reps-in-reserve on the last set of a working exercise.
    /// The corpus's strongest finding on the topic (a 2021 meta of seven
    /// studies) is that 0-3 RIR and true failure grow muscle comparably,
    /// so every option here is defensible — they differ in fatigue cost,
    /// not in whether they work.
    enum EffortAppetite: String, CaseIterable, Sendable {
        /// Leave 2-3 in the tank. Lowest fatigue cost, most repeatable.
        case reserved
        /// Last set close to failure. The default.
        case standard
        /// Take the last set to failure.
        case toFailure

        var rirRange: (low: Int, high: Int) {
            switch self {
            case .reserved:  return (2, 3)
            case .standard:  return (1, 2)
            case .toFailure: return (0, 1)
            }
        }

        /// Accessories may run closer to failure than mains at any
        /// appetite: the corpus is consistent that single-joint work
        /// tolerates it, and that grinding a heavy compound costs far
        /// more recovery than grinding a curl.
        var accessoryRIR: (low: Int, high: Int) {
            switch self {
            case .reserved:  return (1, 2)
            case .standard:  return (0, 2)
            case .toFailure: return (0, 1)
            }
        }
    }

    /// Rep-range preference (`TrainingProfile.repAppetite`). Personas have
    /// been seeding this since 2026-08 and the generator never read it —
    /// a genuinely dead knob until now. It SHIFTS the focus band rather
    /// than replacing it, so a strength block stays a strength block.
    static func applyRepAppetite(_ band: FocusBand, appetite: String?) -> FocusBand {
        guard let appetite else { return band }
        switch appetite {
        case "heavy_low":
            // Heavier and fewer: pull both ends down, floor at 1 rep.
            return FocusBand(mainRepsLow: max(1, band.mainRepsLow - 2),
                             mainRepsHigh: max(3, band.mainRepsHigh - 3),
                             accessoryRepsLow: max(4, band.accessoryRepsLow - 2),
                             accessoryRepsHigh: max(6, band.accessoryRepsHigh - 4),
                             mainRestSeconds: band.mainRestSeconds + 30,
                             accessoryRestSeconds: band.accessoryRestSeconds,
                             weeklySetsLow: band.weeklySetsLow,
                             weeklySetsHigh: band.weeklySetsHigh)
        case "high_rep_pump":
            // Lighter and more. Accessory tops stay inside the corpus's
            // 5-30 effort-matched window.
            return FocusBand(mainRepsLow: band.mainRepsLow + 2,
                             mainRepsHigh: band.mainRepsHigh + 4,
                             accessoryRepsLow: band.accessoryRepsLow + 4,
                             accessoryRepsHigh: min(30, band.accessoryRepsHigh + 8),
                             mainRestSeconds: max(60, band.mainRestSeconds - 30),
                             accessoryRestSeconds: max(45, band.accessoryRestSeconds - 30),
                             weeklySetsLow: band.weeklySetsLow,
                             weeklySetsHigh: band.weeklySetsHigh)
        default:
            return band   // "moderate" and anything unrecognised
        }
    }

    static func band(for focus: Focus) -> FocusBand {
        switch focus {
        case .strength:
            return FocusBand(mainRepsLow: 3, mainRepsHigh: 6,
                             accessoryRepsLow: 6, accessoryRepsHigh: 12,
                             mainRestSeconds: 180, accessoryRestSeconds: 90,
                             weeklySetsLow: 10, weeklySetsHigh: 16)
        case .hypertrophy:
            return FocusBand(mainRepsLow: 6, mainRepsHigh: 12,
                             accessoryRepsLow: 8, accessoryRepsHigh: 20,
                             mainRestSeconds: 120, accessoryRestSeconds: 90,
                             weeklySetsLow: 12, weeklySetsHigh: 20)
        case .weightLoss:
            return FocusBand(mainRepsLow: 8, mainRepsHigh: 15,
                             accessoryRepsLow: 10, accessoryRepsHigh: 20,
                             mainRestSeconds: 90, accessoryRestSeconds: 60,
                             weeklySetsLow: 10, weeklySetsHigh: 14)
        case .conditioning:
            return FocusBand(mainRepsLow: 12, mainRepsHigh: 20,
                             accessoryRepsLow: 12, accessoryRepsHigh: 20,
                             mainRestSeconds: 60, accessoryRestSeconds: 45,
                             weeklySetsLow: 8, weeklySetsHigh: 12)
        }
    }

    /// Power / rate-of-force band (TrainingProfile goal `power_rfd` —
    /// tiered support, owner 2026-08-20): heavy enough to demand force,
    /// light enough to move FAST — submaximal work at full recovery with
    /// explosive intent, never grinding. Delivered as a band OVERRIDE
    /// rather than a fifth Focus: split, slots, and scoring ride the
    /// strength tables; only the prescription shape changes.
    static let powerBand = FocusBand(
        mainRepsLow: 2, mainRepsHigh: 5,
        accessoryRepsLow: 4, accessoryRepsHigh: 8,
        mainRestSeconds: 180, accessoryRestSeconds: 120,
        weeklySetsLow: 8, weeklySetsHigh: 14)

    /// Beginner override (Schoenfeld 2018: beginners grow on 5-9 weekly
    /// sets): 6-10 regardless of focus.
    /// Raised 6-10 -> 8-12 (audit 2026-08-28): the volume-landmarks
    /// deep-read pins the novice band at 9-12 with ~10 sets as beginner
    /// MEV - a 6-10 band put the TARGET (the midpoint, 8) at the very
    /// floor of effectiveness.
    static let beginnerWeeklySets = (low: 8, high: 12)

    // MARK: Progression (by experience; progression-models research)

    /// Novice linear progression per-session increments (practice-based):
    /// upper ~+2.5 lb, lower ~+5 lb — matches SetProgression's percent
    /// steps at typical novice loads. Stall = 2 sessions; response −10%.
    static let noviceStallSessions = 2
    static let noviceStallDeloadPercent = 10.0

    /// A lift is treated as GENUINELY stalled — needing a programming
    /// change, not just a fatigue deload — only after ~3 weeks with no
    /// e1RM personal best despite consistent training (Barbell Medicine's
    /// 3-4 week bar; corpus progression pass, 2026-08). Distinct from the
    /// 2-session fatigue signal above, which fires faster and cuts load.
    /// Consumed by `BlockProgression`.
    static let trueStallDays = 21

    /// BBM's experience scaling (plateau research, 2026-08): "shorten the
    /// no-progress window that counts as a stall for newer lifters, since
    /// they should improve often, and lengthen it for advanced lifters."
    /// BBM gives the direction, not the numbers — the 14/21/28 split
    /// anchors on `trueStallDays` and is our calibration, marked as such.
    static func trueStallDays(for experience: Experience) -> Int {
        switch experience {
        case .new: return 14
        case .intermediate: return trueStallDays
        case .advanced: return 28
        }
    }

    /// Drift probes fire at most this often (owner: "ask some probing
    /// questions about goals every so often, like once every two weeks").
    /// Consumed by `DriftDetector`.
    static let driftProbeCooldownDays = 14

    /// Intermediate double progression: 3-5-rep windows, +2.5-5% on
    /// topping out — already encoded in SetProgression; window widths
    /// come from the focus bands above.

    // MARK: Wave shape (deload + peak; taper research)

    /// Deload at the ¾ mark for 8/12-week plans (proactive 4-6-week
    /// cadence, offered not forced): volume −50%, intensity −5%.
    /// (Audit 2026-08-28: this line used to say "intensity held" while
    /// the multiplier below shipped 0.95 — the comment lied, the code
    /// was the policy. A small dip makes the deload FEEL different
    /// without detraining; the sentence now matches the number.)
    static let deloadVolumeMultiplier = 0.5
    static let deloadIntensityMultiplier = 0.95

    /// 1RM peaking taper (moderate confidence — Pritchard-line research):
    /// 10-14 days, volume −50%, intensity maintained 90-100%. Applied
    /// here to the FINAL WEEK of a strength block — the short end of the
    /// cited window, because the wave is built in whole weeks.
    static let taperVolumeMultiplier = 0.5

    /// Owner policy 2026-08-27: "Max volume: 25 sets per day" — the hard
    /// per-SESSION working-set ceiling, enforced as the generator's final
    /// pass. Not to be confused with VolumeTitration.ceilingWeeklySets
    /// (25 sets per MUSCLE per WEEK) — same number, different unit.
    static let dayCapSets = 25

    // MARK: Recovery constraints (recovery research pass, 2026-08)

    /// Six hard days PER WEEK is the ceiling: no trial shows a full
    /// rest day is required for MUSCLE recovery under proper rotation,
    /// but systemic load (connective tissue, sleep, CNS, adherence) backs
    /// a weekly floor of one non-hard day — an ACTIVE RECOVERY day
    /// satisfies it (ECSS/ACSM overreaching consensus, Meeusen 2013;
    /// practice-based S&C convention, honestly labeled).
    /// (Renamed from maxCONSECUTIVEHardDays, audit 2026-08-28: the
    /// generator has no day-of-week binding, so "consecutive" was a
    /// promise the code cannot express — the rule it enforces is a
    /// weekly count.)
    static let maxHardDaysPerWeek = 6

    /// Same-muscle session spacing: 48 h default (MPS near-baseline by
    /// 48 h in trained lifters — MacDougall 1995 / Phillips 1997
    /// time-course), 72 h after high-fatigue sessions. Rendered as
    /// program NOTES until day-of-week binding exists.
    /// (The full-body spacing NOTE interpolates this constant — audit
    /// 2026-08-28: the note used to hardcode "48", so changing this
    /// changed nothing.)
    static let sameMuscleSpacingHours = 48

    // MARK: Split ladder (frequency law: ≥2×/muscle/week wherever days allow)

    enum DayKind: String {
        case fullBody, upper, lower, push, pull, legs
        // Bodypart-split days (TrainingProfile, owner 2026-08-20: "some
        // people thrive in a bro split" — preference is a first-class
        // input, not a thing the frequency law overrides).
        case chest, back, shoulders, arms
    }

    /// The athlete's split preference (TrainingProfile). `.auto` keeps the
    /// science ladder; an explicit choice WINS over the focus table — the
    /// one-time pushback card in the wizard states the 2x/week evidence,
    /// records the decline, and never nags (owner 2026-08-20).
    enum SplitPreference: String, Codable, CaseIterable, Sendable {
        case auto, fullBody, upperLower, ppl, bro, hybrid
    }

    static func split(daysPerWeek: Int, focus: Focus,
                      preference: SplitPreference = .auto) -> [DayKind] {
        let days = max(1, min(7, daysPerWeek))
        switch preference {
        case .auto:
            break   // science ladder below
        case .fullBody:
            return Array(repeating: .fullBody, count: days)
        case .upperLower:
            return (0..<days).map { $0 % 2 == 0 ? .upper : .lower }
        case .ppl:
            let cycle: [DayKind] = [.push, .pull, .legs]
            return (0..<days).map { cycle[$0 % 3] }
        case .bro:
            // The classic bodypart week. Below 4 days a bro split stops
            // being one — fall through to the science ladder.
            switch days {
            case 4: return [.chest, .back, .legs, .shoulders]
            case 5: return [.chest, .back, .legs, .shoulders, .arms]
            case 6: return [.chest, .back, .legs, .shoulders, .arms, .fullBody]
            case 7: return [.chest, .back, .legs, .shoulders, .arms, .fullBody, .fullBody]
            default: break
            }
        case .hybrid:
            // The pushback card's compromise: an upper/lower base gives
            // every muscle its second weekly touch, bodypart emphasis days
            // keep the bro feel. Below 5 days the science ladder already
            // IS the hybrid.
            switch days {
            case 5: return [.upper, .lower, .chest, .back, .legs]
            case 6: return [.upper, .lower, .chest, .back, .legs, .arms]
            case 7: return [.upper, .lower, .chest, .back, .legs, .arms, .fullBody]
            default: break
            }
        }
        // Weight Loss and Conditioning are FULL-BODY programs at any day
        // count (the focus table's own prescription: density circuits and
        // maintenance-floor lifting, not bodypart splits) — unless an
        // explicit preference above already returned.
        if focus == .weightLoss || focus == .conditioning {
            return Array(repeating: .fullBody, count: days)
        }
        switch days {
        case 1: return [.fullBody]
        case 2: return [.fullBody, .fullBody]
        case 3: return [.fullBody, .fullBody, .fullBody]
        case 4: return [.upper, .lower, .upper, .lower]
        case 5: return [.upper, .lower, .push, .pull, .legs]
        case 6: return [.push, .pull, .legs, .push, .pull, .legs]
        default: return [.push, .pull, .legs, .push, .pull, .legs, .fullBody]
        }
    }

    /// Experience-scaled main-lift intensity ceilings (trainer audit
    /// 2026-08-16, the corpus's most-repeated CRITICAL: novices were
    /// opened at 90% 1RM with no established max — contradicting the
    /// neural-adaptation basis of novice progression the evidence file
    /// itself cites). The ceiling clamps the %1RM anchor; novices climb
    /// via linear progression instead of starting pinned near max.
    static func mainIntensityCeiling(experience: Experience,
                                     isYouth: Bool = false) -> Double {
        // YOUTH CEILINGS (NSCA Youth Resistance Training position stand,
        // Faigenbaum et al. 2009 — corpus area 'guideline'). The stand's
        // progression table tops out at 70-85% 1RM for an ADVANCED youth
        // lifter, well under our adult advanced ceiling of 92.5. Before
        // this, a 16-year-old with a year of training inherited the adult
        // number. The owner's ruling was no minimum age, which makes these
        // ceilings the thing that keeps that safe.
        // Where the two sources disagree, the STRICTER wins. Our own
        // trainer audit had already pulled the adult novice ceiling to
        // 67.5 ("a day-one 50-year-old opened at 72% triples — legal but
        // eager"), which is below the NSCA youth novice band's 70. Taking
        // the NSCA number verbatim would have prescribed a 14-year-old
        // beginner MORE than a 40-year-old beginner — caught by the
        // invariant test, not by reading. The rule is therefore a floor,
        // not a substitution: a youth ceiling can only ever be lower.
        if isYouth {
            let nsca: Double
            switch experience {
            case .new: nsca = 70            // NSCA novice band tops at 70%
            case .intermediate: nsca = 80   // NSCA intermediate tops at 80%
            case .advanced: nsca = 85       // NSCA advanced tops at 85%
            }
            return min(nsca, mainIntensityCeiling(experience: experience))
        }
        switch experience {
        // 72.5 -> 67.5 (20-athlete audit 2026-08-20: a day-one 50-year-old
        // opened at 72% triples — legal but eager; the novice on-ramp
        // teaches patterns at loads that forgive).
        case .new: return 67.5
        case .intermediate: return 87.5
        case .advanced: return 92.5
        }
    }

    /// Training age DECAYS (NSCA position stand, corpus area 'guideline':
    /// novice means up to about 2-3 months of consistent training OR an
    /// individual who has not trained for several months).
    ///
    /// This closes a live defect. `trainingAge` is a value the athlete
    /// STATES and it never decayed, so someone who lifted seriously five
    /// years ago and stopped was still handed advanced ceilings and
    /// advanced volume on their first session back — the single most
    /// named failure mode in the detraining evidence ("chasing pre-layoff
    /// numbers... the resulting injury costs far more long-term").
    ///
    /// Deliberately encodes ONLY the documented boundary. A shorter layoff
    /// is not demoted here, because the same evidence says shorter returns
    /// are governed by LOAD (return at RPE 5-6, letting current capacity
    /// rather than history pick the weight) rather than by re-labelling
    /// the lifter. Inventing an intermediate tier would be interpolation
    /// dressed as a guideline.
    static let layoffResetDays = 120

    static func decayedExperience(stated: Experience,
                                  daysSinceLastSession: Int?,
                                  daysSinceReturn: Int? = nil) -> Experience {
        // Still away.
        if let days = daysSinceLastSession, days >= layoffResetDays { return .new }
        // Back, but not yet re-acquired. Without this the safety rule
        // lasted exactly ONE SESSION: the guard above reads days since the
        // last session, so the moment a two-years-off lifter trained once,
        // that number fell to zero and they were handed advanced ceilings
        // in week one — the "sudden workload spike" the detraining corpus
        // rates a strong injury risk.
        if let back = daysSinceReturn, back < reacquisitionWeeks * 7 { return .new }
        return stated
    }

    /// How long a returning lifter keeps novice ceilings AFTER their first
    /// session back.
    ///
    /// The corpus is emphatic about the DIRECTION — "undershoot rather
    /// than overshoot volume and load on return", and return progression
    /// should be governed by objective performance criteria rather than
    /// calendar time. It does not give a number of weeks, because the
    /// honest answer is not a number. Four weeks is OUR calibration,
    /// marked as such, standing in for criteria we cannot yet check.
    ///
    /// Note what this does NOT do: it does not slow them down. Muscle
    /// memory is real (retained myonuclei; one study saw quad size exceed
    /// its prior peak within five weeks of retraining), so a returner
    /// climbs fast on their own. The window governs where they START, not
    /// how quickly they rise.
    static let reacquisitionWeeks = 4

    /// Days since the session that ended a layoff, or nil if the log shows
    /// no layoff to have returned from.
    ///
    /// Reads the LOG rather than asking, because "when did you come back"
    /// is a question the app can answer for itself — and an athlete
    /// mid-comeback is the least likely person to answer it accurately.
    static func daysSinceReturn(sessionDates: [Date],
                                now: Date = .now,
                                calendar: Calendar = .current) -> Int? {
        guard let resumed = returnDate(sessionDates: sessionDates,
                                       calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: resumed, to: now).day
    }

    /// The DAY training resumed after the most recent layoff.
    ///
    /// Extracted so there is exactly one gap-walk in the codebase: this
    /// answers "when did they come back", `daysSinceReturn` answers "how
    /// long ago", and `TrainingHorizon` answers "which sets count". Three
    /// questions, one algorithm — two copies of a rule like this drift,
    /// and the drift would be invisible because both halves would still
    /// look correct on their own.
    ///
    /// The LAST qualifying gap wins: someone who has come back twice is
    /// judged on their latest return, not their first.
    static func returnDate(sessionDates: [Date],
                           layoffDays: Int = layoffResetDays,
                           calendar: Calendar = .current) -> Date? {
        let days = Set(sessionDates.map { calendar.startOfDay(for: $0) }).sorted()
        guard days.count >= 2 else { return nil }
        var resumed: Date?
        for (previous, next) in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: previous, to: next).day ?? 0
            if gap >= layoffDays { resumed = next }
        }
        return resumed
    }

    /// Complexity gate (catalog labels; owner law: complexity GATES by
    /// experience, never penalizes). Auto-prescription cap on technical
    /// demand — a soft gate: violating candidates sort behind clean ones
    /// but can still fill a slot nothing else can. Rerolls and manual
    /// picks reach everything.
    // MARK: - Comfort probes (derived experience, spec 2026-08-22)
    //
    // Experience level is DERIVED, never picked: five probes spanning
    // the complexity ladder with recognizable lifts. The cap is the
    // highest complexity with a COHERENT PREFIX - comfortable at 4 but
    // not at 3 reads as 3-below (bravado doesn't skip rungs).
    struct ComfortProbe: Identifiable {
        let slug: String
        let name: String
        let detail: String
        let complexity: Int
        var id: String { slug }
    }

    static let comfortProbes: [ComfortProbe] = [
        ComfortProbe(slug: "goblet-squat", name: "Goblet squat",
                     detail: "A squat holding one dumbbell at your chest",
                     complexity: 1),
        ComfortProbe(slug: "back-squat-heavy", name: "Heavy barbell back squat",
                     detail: "Bar on your back, at a weight that feels genuinely heavy",
                     complexity: 3),
        ComfortProbe(slug: "deadlift", name: "Conventional deadlift",
                     detail: "A loaded barbell from the floor to standing",
                     complexity: 3),
        ComfortProbe(slug: "weighted-pullup", name: "Weighted pull-up",
                     detail: "Pull-ups with extra weight hanging from a belt",
                     complexity: 4),
        ComfortProbe(slug: "power-clean", name: "Power clean",
                     detail: "An explosive barbell pull caught at the shoulders",
                     complexity: 5),
    ]

    /// The derived complexity cap: walk the ladder's levels ascending;
    /// the cap advances only while every level so far has at least one
    /// comfortable answer. Nothing comfortable = cap 2 (the honest
    /// floor - simple movements only). Nil until any probe is answered.
    static func derivedComplexityCap(from answers: [String: Bool]) -> Int? {
        guard !answers.isEmpty else { return nil }
        let bySlug = Dictionary(uniqueKeysWithValues: comfortProbes.map { ($0.slug, $0.complexity) })
        let comfortableLevels = Set(answers.compactMap { slug, ok in ok ? bySlug[slug] : nil })
        var cap = 2
        for level in [1, 3, 4, 5] {
            guard comfortableLevels.contains(level) else { break }
            cap = max(cap, level)
        }
        return cap
    }

    /// The register tier a cap implies - the debrief voice, rep floors,
    /// and calibration anchors still key off this; no user ever sees it.
    static func experience(forCap cap: Int) -> Experience {
        switch cap {
        case ..<3: return .new
        case 3: return .intermediate
        default: return .advanced
        }
    }

    static func complexityCap(experience: Experience) -> Int {
        switch experience {
        case .new: return 3
        case .intermediate: return 4
        case .advanced: return 5
        }
    }

    /// Selection demotions (owner field report 2026-08-15: an ADVANCED
    /// lifter drew "Assisted Pull-Up Machine" on upper days). Catalog rank
    /// is alphabetical fetch order, so the machine sweep's A-named
    /// assisted variants silently won every tiebreak. Assisted machines
    /// are REGRESSIONS — never a default prescription for anyone (rerolls
    /// and the manual picker still reach them); behind-the-neck variants
    /// are a form-risk default; digit-prefixed niche machines lose their
    /// accidental alphabetical head start. The penalty compares FIRST in
    /// selection — ahead of the equipment ladder — so a penalized variant
    /// only fills a slot no clean candidate can.
    static func selectionPenalty(name: String) -> Int {
        let lower = name.lowercased()
        var penalty = 0
        if lower.contains("assisted") { penalty += 10_000 }
        if lower.contains("behind the neck") || lower.contains("behind-the-neck") {
            penalty += 2_000
        }
        if let first = lower.first, first.isNumber { penalty += 500 }
        return penalty
    }

    /// Main-lift equipment preference by focus (design-doc rule 2):
    /// Strength/Hypertrophy build mains on the bar (specificity,
    /// loadability); Weight Loss/Conditioning run machine/cable-first —
    /// safer at circuit pace and honest to how those sessions train.
    static func mainEquipmentLadder(focus: Focus) -> [String: Int] {
        switch focus {
        case .strength, .hypertrophy:
            return ["barbell": 0, "dumbbell": 1, "machine": 2, "cable": 3, "bodyweight": 4]
        case .weightLoss, .conditioning:
            return ["machine": 0, "cable": 1, "dumbbell": 2, "bodyweight": 3, "barbell": 4]
        }
    }
}
