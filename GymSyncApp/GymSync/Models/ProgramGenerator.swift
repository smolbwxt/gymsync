import Foundation

// MARK: - ProgramGenerator
//
// The COACH pipeline, pure and deterministic: same inputs + same catalog
// = the same program, byte for byte (ties break on stable catalog rank,
// never randomness — what makes the golden tests meaningful and a
// regenerated preview trustworthy). Every exercise in the output can
// answer "which slot, which rule, which budget line put you here."
//
// Science lives in GeneratorScience (evidence-cited constants); this
// file is the machinery: split → budget → slots → selection → wave.
enum ProgramGenerator {

    // MARK: Inputs

    struct Inputs {
        var focus: GeneratorScience.Focus
        var daysPerWeek: Int
        var durationWeeks: Int
        var experience: GeneratorScience.Experience
        var sex: GeneratorScience.Sex = .unspecified
        /// nil = ALL muscle groups (the owner's "hit all and don't think
        /// about it again"); otherwise the focus muscles.
        var focusMuscles: Set<String>? = nil
        /// Equipment classes available; nil = everything.
        var equipment: Set<String>? = nil
        /// Split preference (TrainingProfile): an explicit choice WINS over
        /// the focus table; `.auto` keeps the science ladder.
        var splitPreference: GeneratorScience.SplitPreference = .auto
        // TrainingProfile consumption (2026-08-20) — every field below
        // changes output when flipped, provably (the no-dead-knobs law).
        /// Session structure: supersets pair antagonists; circuit chains
        /// the day; minimalist caps it at three lifts.
        var sessionStructure: TrainingProfile.SessionStructure = .straight
        /// intervals -> zone 4, steady -> zone 2 for dedicated cardio.
        var cardioStyle: TrainingProfile.CardioStyle = .auto
        /// Prescription-shape override (power_rfd: submaximal speed work).
        var bandOverride: GeneratorScience.FocusBand? = nil
        /// Weighted goal vector over the label score keys — replaces the
        /// single-focus score in selection when present.
        var selectionTilt: [String: Double]? = nil
        /// Hard exclusions — these lifts do not exist for this athlete.
        var excludedExerciseIDs: Set<UUID> = []
        var excludedPatterns: Set<String> = []
        /// Injury propagation (soft): joint_stress matches sort last.
        var cautionJoints: Set<String> = []
        /// bone_density ranked: spinal-loading lifts score up.
        var axialBoost: Bool = false
        /// The chosen coach's selection stances (CoachPersona.Lens).
        var personaLens: CoachPersona.Lens? = nil
        /// Block-to-block carryover (BlockReview): lifts the athlete kept
        /// skipping last block sort LAST — deprioritized, never silently
        /// re-prescribed, never a hole (adherence beats optimality).
        var deprioritizedExerciseIDs: Set<UUID> = []
        /// sport_prep in season: practice and games are recovery debits —
        /// intensity capped, nothing near max.
        var inSeason: Bool = false
        /// Body context (profile BMI 30+ / bodyfat 30%+): high-impact
        /// rows sort behind — landings, not effort, are the risk being
        /// managed. Gives the `impact` label its first consumer.
        var impactCaution: Bool = false
        /// Derived experience (spec 2026-08-22): the comfort-probe cap,
        /// finer than the three experience buckets - a lifter easy under
        /// a heavy squat but never cleaned gets cap 3-4, not a label.
        var complexityCapOverride: Int? = nil
        /// Lifts appearing in routines the athlete STARRED (field report
        /// #18): aspiration as data. The weakest tiebreak above the
        /// equipment ladder — it never beats a score, a bucket, or any
        /// gate; it just answers "when nothing else separates them, pick
        /// the one they've been eyeing."
        var starredExerciseIDs: Set<UUID> = []
        /// football | baseball | wrestling — the sport_prep goal's sport
        /// (corpus parameters, docs/science/sport-prep-parameters.md):
        /// wrestling ranks unilateral work up (stance and shots are
        /// one-sided), football prefers unilateral lower-body patterns,
        /// baseball turns every accessory shoulder slot cuff-first and
        /// adds the arm-care standing dose.
        var sportPrepSport: String? = nil
        /// conservative | standard | aggressive — shifts the %1RM anchor
        /// (audit 2026-08-20: previously a dead knob; the experience
        /// ceiling still has the last word).
        var intensityAppetite: String = "standard"
        /// Honesty lines from the profile mapping (audit round 2): when a
        /// wish can't be fully honored — a bodypart split without the
        /// days, a goal whose modality is still thin — Coach SAYS so
        /// instead of silently substituting.
        var advisoryNotes: [String] = []
        /// Dedicated cardio days appended after the lifting split
        /// (owner 2026-08-14) — prescribed as zone + MINUTES. When
        /// lifting + cardio exceed 7 calendar days, the overflow PAIRS
        /// onto lifting days as PM sessions (two-a-days).
        var cardioDays: Int = 0
        var cardioMinutes: Int = 30
        /// "Train every day": remaining calendar days fill with ACTIVE
        /// RECOVERY — mobility work + a zone-1 walk. In the gym daily,
        /// but recovery days prescribe recovery.
        var fillWeekWithRecovery: Bool = false
        /// Session length cap in minutes (owner 2026-08-15: "there's no
        /// option for workout duration"); nil = uncapped. Days trim
        /// accessories (never mains) until they fit.
        var sessionMinutes: Int? = nil
        /// Deterministic variety (owner 2026-08-15: "there should be some
        /// variation"): rotates picks among SCIENTIFICALLY-EQUIVALENT
        /// candidates (same penalty class, focus standing, and equipment
        /// tier). Same seed = same program, byte for byte — variety
        /// without giving up the testable pure function.
        var seed: Int = 0
    }

    struct CatalogExercise {
        let id: UUID
        let name: String
        let primaryMuscle: String
        let secondaryMuscles: [String]
        let category: String        // compound | isolation | ...
        let equipment: String
        let movementPattern: String // squat|hinge|lunge|push_horizontal|push_vertical|pull_horizontal|pull_vertical|isolation|other
        /// Stable order (catalog fetch order) — the deterministic tiebreak.
        let rank: Int
        // Catalog labels (20260816000002, swarm-authored) — trailing
        // defaults keep every construction site compiling; unlabeled
        // rows behave like the pre-label generator.
        /// 0-10 effectiveness per goal, keys strength|hypertrophy|
        /// weight_loss|conditioning. Empty = unscored.
        var focusScores: [String: Int] = [:]
        /// 1-5 technical demand; GATES by experience, never penalizes.
        var complexity: Int = 3
        /// 1-5 systemic drain per hard set.
        var fatigueCost: Int = 3
        /// 0-2 axial loading (2 = heavy: squats, deadlifts, standing OHP).
        var spinalLoad: Int = 0
        /// Sensible prescription window; nil = unclamped.
        var repMin: Int? = nil
        var repMax: Int? = nil
        var lengthenedBias: Bool = false
        var unilateral: Bool = false
        /// high | low | none (cardio modality attribute).
        var impact: String = "none"
        var legInterference: Bool = false
        /// Power/velocity intent — the conditioning focus's consumer.
        var explosive: Bool = false
        /// Joints this lift stresses (labels) — the caution-joint soft
        /// sort's fuel (TrainingProfile injury propagation 2026-08-20).
        var jointStress: [String] = []
    }

    // MARK: Output

    struct Exercise: Equatable {
        let exerciseID: UUID
        let name: String
        var sets: Int
        var repsLow: Int
        var repsHigh: Int
        var restSeconds: Int
        var percentOfMax: Double?
        var isMain: Bool
        /// The slot that placed this exercise — carried so a reroll can
        /// re-run the SAME selection with the current pick excluded
        /// (deterministic next-best, never a shuffle).
        var slot: Slot? = nil
        /// Cardio prescriptions: zone + MINUTES instead of sets × reps.
        var cardioZone: Int? = nil
        var cardioMinutes: Int? = nil
        /// Antagonist-superset pairing (session structure, corpus census
        /// 2026-08-20): exercises sharing a group number alternate sets.
        /// nil = straight sets.
        var supersetGroup: Int? = nil
    }

    struct Day: Equatable {
        var name: String
        var exercises: [Exercise]
    }

    struct Week: Equatable {
        let number: Int
        var volumeMultiplier: Double
        var intensityMultiplier: Double
        var isDeload: Bool
        var note: String?
    }

    struct Program: Equatable {
        var days: [Day]
        var weeks: [Week]
        var notes: [String]
    }

    // MARK: Pipeline

    static func generate(inputs: Inputs, catalog: [CatalogExercise]) -> Program {
        // Band override (power_rfd) beats the focus table for prescription
        // SHAPE only — split, slots, and scoring still ride the focus.
        let band = inputs.bandOverride ?? GeneratorScience.band(for: inputs.focus)
        let split = GeneratorScience.split(daysPerWeek: inputs.daysPerWeek,
                                           focus: inputs.focus,
                                           preference: inputs.splitPreference)
        let usable = usableCatalog(catalog, inputs: inputs)

        var notes: [String] = inputs.advisoryNotes
        if inputs.daysPerWeek == 1 {
            notes.append("One day a week means one LONG session (~75-90 minutes) - everything has to fit. A session cap trims it, and two shorter days beat one marathon when life allows.")
        }

        // Weekly per-muscle set budget: focus band (beginner override),
        // sex ceiling nudge (soft, top only).
        var weekly: (low: Int, high: Int)
        if inputs.experience == .new {
            weekly = GeneratorScience.beginnerWeeklySets
        } else {
            let ceiling = Double(band.weeklySetsHigh)
                * GeneratorScience.weeklyVolumeCeilingMultiplier(sex: inputs.sex)
            weekly = (band.weeklySetsLow, Int(ceiling.rounded()))
            // Advanced lifters tolerate (and need) more: +2 on the weekly
            // ceiling (audit: advanced was indistinguishable from
            // intermediate at equal inputs).
            if inputs.experience == .advanced { weekly.high += 2 }
        }
        let targetWeeklySets = (weekly.low + weekly.high) / 2

        // Days: fill each day's slot template, spending the weekly budget
        // across the split (rule 7: never all of a muscle's volume in one
        // session).
        let perDayBudget = max(2, targetWeeklySets / max(1, muscleFrequency(split: split)))

        var days: [Day] = []
        // Cross-day variety (owner 2026-08-15: "the same exact one every
        // single time"): accessories exclude other days' accessory picks,
        // so Full Body 2 accessorizes differently than Full Body 1. MAINS
        // repeat on purpose — the frequency law wants the same big lifts
        // practiced across the week.
        var usedAccessories = Set<UUID>()
        var trimmedForTime = false
        for (index, kind) in split.enumerated() {
            let name = dayName(kind: kind, index: index, split: split)
            var chosen: [Exercise] = []
            var alreadyChosen = Set<UUID>()
            // Bounded explosive emphasis (audit 2026-08-20: the firefighter
            // got ALL-plyometric mains and zero strength): the lens may
            // claim at most ONE main slot per day — the explosive-first
            // slot the session sort already honors. Accessories never
            // take the boost.
            var explosiveBudget = inputs.personaLens?.explosiveEmphasis == true ? 1 : 0
            // Sport prophylaxis standing dose (corpus 2026-08-21): like
            // the core slot, a small always-there insurance policy —
            // baseball's arm care on pressing days, wrestling's grip on
            // pulling days. One slot, accessory volume, trimmed first by
            // the session cap like any accessory.
            var daySlots = slots(for: kind, focus: inputs.focus)
            switch inputs.sportPrepSport {
            case "baseball":
                if [.upper, .push, .fullBody].contains(kind) {
                    daySlots.append(.isolation("shoulders"))
                }
            case "wrestling":
                if [.upper, .pull, .fullBody].contains(kind) {
                    daySlots.append(.isolation("forearms"))
                }
            default:
                break
            }
            for slot in daySlots {
                let isMainSlot: Bool
                if case .pattern(_, let main) = slot { isMainSlot = main } else { isMainSlot = false }
                var slotLens = inputs.personaLens
                if slotLens?.explosiveEmphasis == true, !isMainSlot || explosiveBudget == 0 {
                    slotLens?.explosiveEmphasis = false
                }
                let exclusions = isMainSlot ? alreadyChosen : alreadyChosen.union(usedAccessories)
                var pick = select(slot: slot, from: usable,
                                  excluding: exclusions,
                                  focus: inputs.focus,
                                  focusMuscles: inputs.focusMuscles,
                                  experience: inputs.experience,
                                  seed: inputs.seed,
                                  tilt: inputs.selectionTilt,
                                  cautionJoints: inputs.cautionJoints,
                                  axialBoost: inputs.axialBoost,
                                  impactCaution: inputs.impactCaution,
                                  complexityCapOverride: inputs.complexityCapOverride,
                                  starred: inputs.starredExerciseIDs,
                                  sportLens: inputs.sportPrepSport,
                                  lens: slotLens,
                                  deprioritized: inputs.deprioritizedExerciseIDs)
                if pick == nil, !isMainSlot {
                    // Accessory pool exhausted — repeats beat holes.
                    pick = select(slot: slot, from: usable,
                                  excluding: alreadyChosen,
                                  focus: inputs.focus,
                                  focusMuscles: inputs.focusMuscles,
                                  experience: inputs.experience,
                                  seed: inputs.seed,
                                  tilt: inputs.selectionTilt,
                                  cautionJoints: inputs.cautionJoints,
                                  axialBoost: inputs.axialBoost,
                                  impactCaution: inputs.impactCaution,
                                  complexityCapOverride: inputs.complexityCapOverride,
                                  starred: inputs.starredExerciseIDs,
                                  sportLens: inputs.sportPrepSport,
                                  lens: slotLens,
                                  deprioritized: inputs.deprioritizedExerciseIDs)
                }
                guard let pick else { continue }
                if pick.explosive, isMainSlot { explosiveBudget = 0 }
                alreadyChosen.insert(pick.id)
                if !isMainSlot { usedAccessories.insert(pick.id) }
                var sets = setsPerSlot(slot: slot, perDayBudget: perDayBudget)
                // Low-frequency density (trainer audit: 1-2 day weeks
                // undershoot the weekly volume floor): mains carry an
                // extra set; intensity trades down below.
                if inputs.daysPerWeek <= 2, isMainSlot { sets = min(6, sets + 1) }
                chosen.append(prescription(for: pick, slot: slot, band: band,
                                           inputs: inputs, setsPerExercise: sets))
            }
            // Session post-pass (trainer audit 2026-08-16):
            // 1. Explosive work FIRST — power output needs a fresh CNS;
            //    ballistic movements after near-max compounds are a
            //    technical-breakdown risk. Stable within groups.
            let labelByID = Dictionary(uniqueKeysWithValues: usable.map { ($0.id, $0) })
            chosen = chosen.enumerated().sorted { a, b in
                func group(_ e: Exercise) -> Int {
                    if labelByID[e.exerciseID]?.explosive == true { return 0 }
                    return e.isMain ? 1 : 2
                }
                let ga = group(a.element), gb = group(b.element)
                if ga != gb { return ga < gb }
                return a.offset < b.offset
            }.map(\.element)
            // 2. Axial stagger: only ONE heavy-spinal-load main keeps the
            //    session's top anchor; later ones drop ~10% (squat +
            //    deadlift both maxed back-to-back was a repeated CRITICAL).
            var axialSeen = false
            chosen = chosen.map { e in
                var e = e
                if e.isMain, labelByID[e.exerciseID]?.spinalLoad == 2 {
                    if axialSeen, let p = e.percentOfMax {
                        e.percentOfMax = max(60, p - 10)
                    }
                    axialSeen = true
                }
                // 3. Low-frequency density trade: at 1-2 days the extra
                //    sets come with a capped anchor.
                if inputs.daysPerWeek <= 2, e.isMain, let p = e.percentOfMax {
                    e.percentOfMax = min(p, 82.5)
                }
                return e
            }
            // Session-length cap (owner 2026-08-15: "no option for workout
            // duration"): trim accessories — never mains — until the day
            // fits.
            //
            // The estimate now mirrors `StatMath.estimatedMinutes` exactly
            // (audit 2026-08-25). The old inline formula charged a full
            // rest after the LAST set of every exercise and a transition
            // after the last exercise, inflating a 5x120s main from 15 to
            // 22 minutes — roughly 45% over. The generator was therefore
            // trimming against a budget the routine card then displayed as
            // comfortably shorter, which is what surfaced as "our routines
            // are pretty short. 4 exercises?": a 60-minute cap deleted
            // accessories until only three lifts survived. One formula,
            // one source of truth, so the two can never disagree again.
            if let cap = inputs.sessionMinutes {
                func estimatedMinutes(_ list: [Exercise]) -> Int {
                    guard !list.isEmpty else { return 0 }
                    var seconds = list.reduce(0) { acc, ex in
                        acc + ex.sets * StatMath.secondsPerSet
                            + max(0, ex.sets - 1) * ex.restSeconds
                    }
                    seconds += (list.count - 1) * TransitWindow.seconds
                    return max(1, Int((Double(seconds) / 60).rounded()))
                }
                while estimatedMinutes(chosen) > cap, chosen.count > 1,
                      let lastAccessory = chosen.lastIndex(where: { !$0.isMain }) {
                    chosen.remove(at: lastAccessory)
                    trimmedForTime = true
                }
                // Accessories exhausted and STILL over: reduce main sets
                // (floor 3) before surrendering. Audit 2026-08-20: the
                // 40-minute parent got 75-minute sessions because three
                // individually-correct rules composed — cap trims only
                // accessories, minimalist had already removed them, and
                // low-frequency added a set to every main.
                while estimatedMinutes(chosen) > cap,
                      let heaviest = chosen.indices
                          .filter({ chosen[$0].isMain && chosen[$0].sets > 3 })
                          .max(by: { chosen[$0].sets < chosen[$1].sets }) {
                    chosen[heaviest].sets -= 1
                    trimmedForTime = true
                }
                // Final lever (audit round 2: the 70-something's 30-minute
                // cap met four 180s-rest mains — set floors alone left
                // 68-minute sessions): drop whole mains from the END,
                // never below two. Two lifts done beat four abandoned.
                while estimatedMinutes(chosen) > cap,
                      chosen.filter(\.isMain).count > 2,
                      let lastMain = chosen.lastIndex(where: \.isMain) {
                    chosen.remove(at: lastMain)
                    trimmedForTime = true
                }
            }
            // Exhaustion stagger (owner 2026-08-22): exercises that use
            // more muscle groups tire athletes more - never stack the
            // heavy-drain accessories back to back. Mains keep their
            // block and order (mains-first is the law); the accessory
            // tail interleaves high- and low-fatigue picks.
            days.append(Day(name: name,
                            exercises: staggerFatigue(chosen, catalog: catalog)))
        }
        if trimmedForTime, let cap = inputs.sessionMinutes {
            notes.append("Accessories trimmed to fit \(cap)-minute sessions — the main lifts keep their place. More time brings them back.")
        }
        if inputs.daysPerWeek <= 2 {
            notes.append("Low-frequency week: mains carry an extra set at a capped intensity — density over ceiling when sessions are scarce.")
        }

        // Weekly heavy/light wave (trainer audit: the same lift repeated
        // at its top anchor every session, no undulation — the precedent
        // for high-frequency lifting is daily load WAVING, not daily
        // maxing): a lift keeps its top anchor at most twice a week;
        // further exposures drop ~10%.
        var topExposures: [UUID: Int] = [:]
        for dayIndex in days.indices {
            for exIndex in days[dayIndex].exercises.indices {
                let e = days[dayIndex].exercises[exIndex]
                guard e.isMain, let p = e.percentOfMax, p >= 80 else { continue }
                let seen = topExposures[e.exerciseID, default: 0]
                if seen >= 2 {
                    days[dayIndex].exercises[exIndex].percentOfMax = max(60, p - 10)
                } else {
                    topExposures[e.exerciseID] = seen + 1
                }
            }
        }

        // Per-muscle weekly volume accounting (corpus audit 2026-08: the
        // generator budgeted volume per SLOT and never counted what a week
        // actually delivers to each muscle — `secondaryMuscles` was
        // declared and never read, so a hypertrophy upper/lower handed
        // triceps ~17 effective sets against the 12-20 band while chest
        // got ~10). Runs before cardio/recovery days join, so only real
        // lifting volume is counted.
        let emphasisDays: Set<String> = inputs.splitPreference == .hybrid
            ? ["Chest", "Back", "Shoulders", "Arms", "Legs"] : []
        let balanced = balanceWeeklyVolume(days: days, catalog: catalog,
                                           low: weekly.low, high: weekly.high,
                                           protectedDayNames: emphasisDays)
        days = balanced.days
        if balanced.trimmed > 0 || balanced.added > 0 {
            var parts: [String] = []
            if balanced.trimmed > 0 {
                parts.append("trimmed \(balanced.trimmed) accessory set\(balanced.trimmed == 1 ? "" : "s") from over-covered muscles (indirect volume from compounds counts — half a set per secondary muscle)")
            }
            if balanced.added > 0 {
                parts.append("added \(balanced.added) set\(balanced.added == 1 ? "" : "s") where a trained muscle fell under the weekly floor")
            }
            notes.append("Weekly volume balanced per muscle: " + parts.joined(separator: "; ") + ".")
        }

        // Orphaned-muscle coverage (owner 2026-08-21: "not everyone gets a
        // workout that hits every muscle every week — make sure those
        // muscles are taken care of at some point; something is better
        // than nothing"). A major muscle at ZERO effective weekly sets
        // that the athlete's constraints can still train gets a small
        // isolation dose on the lightest day (audit A29: excluding both
        // push patterns silently zeroed the chest). Time-capped weeks
        // skip the dose and SAY so — rotation across weeks arrives with
        // week-at-read-time resolution.
        let majors = ["chest", "back", "lats", "shoulders", "quads",
                      "hamstrings", "glutes", "biceps", "triceps", "calves"]
        let tally = weeklyMuscleSets(days: days, catalog: catalog)
        let orphans = majors.filter { (tally[$0] ?? 0) == 0 }
        if !orphans.isEmpty {
            var covered: [String] = []
            var uncoverable: [String] = []
            for muscle in orphans.prefix(3) {
                guard inputs.sessionMinutes == nil else { uncoverable.append(muscle); continue }
                let pick = select(slot: .isolation(muscle), from: usable,
                                  excluding: Set(days.flatMap(\.exercises).map(\.exerciseID)),
                                  focus: inputs.focus,
                                  focusMuscles: inputs.focusMuscles,
                                  experience: inputs.experience,
                                  seed: inputs.seed,
                                  tilt: inputs.selectionTilt,
                                  cautionJoints: inputs.cautionJoints,
                                  impactCaution: inputs.impactCaution,
                                  complexityCapOverride: inputs.complexityCapOverride,
                                  starred: inputs.starredExerciseIDs,
                                  sportLens: inputs.sportPrepSport,
                                  lens: inputs.personaLens)
                guard let pick,
                      let lightest = days.indices.min(by: {
                          days[$0].exercises.count < days[$1].exercises.count
                      }) else { uncoverable.append(muscle); continue }
                days[lightest].exercises.append(
                    prescription(for: pick, slot: .isolation(muscle),
                                 band: band, inputs: inputs, setsPerExercise: 2))
                covered.append(muscle)
            }
            if !covered.isEmpty {
                notes.append("Coverage dose: \(covered.joined(separator: ", ")) had no direct work this week, so a small dose rides the lightest day — something beats nothing.")
            }
            if !uncoverable.isEmpty {
                notes.append("Tight week: no room for direct \(uncoverable.joined(separator: ", ")) — Coach rotates these in as sessions allow; the program covers them over time, not every single week.")
            }
        }

        // A main-less lifting day (both its patterns excluded - A30)
        // promotes its first lift to anchor the session: a day needs
        // something to organize around, and the promoted lift keeps its
        // accessory prescription (no invented percent).
        for d in days.indices {
            let lifting = days[d].exercises.filter { $0.cardioZone == nil }
            if !lifting.isEmpty, !lifting.contains(where: \.isMain),
               let first = days[d].exercises.firstIndex(where: { $0.cardioZone == nil }) {
                days[d].exercises[first].isMain = true
            }
        }

        // Session structure (corpus census 2026-08-20 — a separate axis
        // from the split). Runs after the volume balance so structure
        // reflects final set counts.
        switch inputs.sessionStructure {
        case .straight:
            break
        case .supersets:
            days = days.map { assignSupersets(day: $0, catalog: catalog) }
            notes.append("Antagonist supersets: paired lifts alternate sets — one side rests while the other works, cutting session time at near-zero performance cost.")
        case .circuit:
            // One big round: every lift shares a group, rests compress —
            // the density structure (22 corpus videos / 10 channels).
            for d in days.indices {
                for x in days[d].exercises.indices where days[d].exercises[x].cardioZone == nil {
                    days[d].exercises[x].supersetGroup = 1
                    days[d].exercises[x].restSeconds = min(days[d].exercises[x].restSeconds, 45)
                }
            }
            notes.append("Circuit structure: run the day's lifts as rounds with short transitions — density is the point; loads sit lighter than straight sets would carry.")
        case .minimalist:
            // Abbreviated training (30 videos / 9 channels): two or three
            // hard lifts, nothing else. Mains keep priority.
            for d in days.indices {
                let exercises = days[d].exercises
                let mains = exercises.filter { $0.isMain && $0.cardioZone == nil }
                let accessories = exercises.filter { !$0.isMain && $0.cardioZone == nil }
                let cardio = exercises.filter { $0.cardioZone != nil }
                let keep = Array(mains.prefix(3))
                    + Array(accessories.prefix(max(0, 3 - mains.count)))
                days[d].exercises = keep + cardio
            }
            notes.append("Minimalist structure: three hard lifts a session — the abbreviated-training tradition. Progress lives in the log, not the exercise count.")
        }

        // In-season cap (sport_prep context): practice and games are
        // recovery debits training must respect — nothing near max.
        if inputs.inSeason {
            for d in days.indices {
                for x in days[d].exercises.indices {
                    if let p = days[d].exercises[x].percentOfMax {
                        days[d].exercises[x].percentOfMax = min(p, 80)
                    }
                }
            }
            notes.append("In-season: intensity capped at 80% — the field is the priority; the gym maintains what practice spends.")
        }

        // Conditioning zone floor (trainer audit, GOAL FAILURE class: a
        // conditioning focus with cardioDays=0 shipped zero zone work —
        // the thing the session is FOR). Every conditioning lifting day
        // ends in a zone-4 interval finisher unless dedicated cardio days
        // already carry the load.
        if inputs.focus == .conditioning, inputs.cardioDays == 0 {
            let modality = usable.first { $0.category == "cardio" }
                ?? catalog.first { $0.category == "cardio" }
            if let modality {
                for index in days.indices where days[index].exercises.contains(where: { $0.isMain }) {
                    days[index].exercises.append(Exercise(
                        exerciseID: modality.id, name: modality.name,
                        sets: 1, repsLow: 0, repsHigh: 0,
                        restSeconds: 0, percentOfMax: nil, isMain: false,
                        slot: nil, cardioZone: 4, cardioMinutes: 12))
                }
                notes.append("Every conditioning session ends in a zone-4 interval finisher — the zone work IS the goal; the lifting holds muscle underneath it.")
            }
        }

        // Secondary-goal purchase (concept 2026-08-20: "a 0.3
        // conditioning weight buys a zone finisher, not mushy rep
        // ranges"): a meaningful conditioning weight on a non-conditioning
        // program with no dedicated cardio ends two sessions in intervals.
        if inputs.focus != .conditioning, inputs.cardioDays == 0,
           (inputs.selectionTilt?["conditioning"] ?? 0) >= 0.2,
           let engine = usable.first(where: { $0.category == "cardio" }) {
            var added = 0
            for index in days.indices where added < 2
                && days[index].exercises.contains(where: \.isMain) {
                days[index].exercises.append(Exercise(
                    exerciseID: engine.id, name: engine.name,
                    sets: 1, repsLow: 0, repsHigh: 0, restSeconds: 0,
                    percentOfMax: nil, isMain: false, slot: nil,
                    cardioZone: 4, cardioMinutes: 10))
                added += 1
            }
            if added > 0 {
                notes.append("Your conditioning goal buys finishers: \(added) session\(added == 1 ? "" : "s") end with 10 zone-4 minutes - the engine work rides the lifting days.")
            }
        }

        // Recovery ceiling (research pass): six hard days max — a 7-day
        // request gets six lifting days and day 7 converts to ACTIVE
        // RECOVERY (the evidence-backed way to train daily).
        var hardDayCount = days.count
        if days.count > GeneratorScience.maxConsecutiveHardDays {
            days[days.count - 1] = recoveryDay(name: "Active Recovery", usable: usable)
            hardDayCount = GeneratorScience.maxConsecutiveHardDays
            notes.append("Six hard days is the ceiling — day 7 is active recovery. No trial shows a full rest day is required for muscle under rotation, but connective tissue, sleep, and burnout say otherwise (Meeusen 2013 consensus).")
        }
        // Threshold ≥2 (trainer audit: the off-by-one left 2-day full-body
        // weeks without the spacing reminder they need just as much) and
        // arithmetically honest wording — five same-muscle days cannot all
        // sit 48h apart, so the note asks for the possible, not the ideal.
        if split.filter({ $0 == GeneratorScience.DayKind.fullBody }).count >= 2 {
            notes.append("Space full-body days as evenly as the week allows — muscles want ~48 hours between sessions that hit them (muscle protein synthesis runs its course by ~48h in trained lifters).")
        }

        // Dedicated cardio (owner 2026-08-14): zone + MINUTES. When
        // lifting + cardio exceed 7 calendar days, the overflow PAIRS
        // onto lifting days as PM sessions (two-a-days) — same-day
        // strength + cardio wants ≥6h separation (Wilson et al.
        // concurrent-training interference), which the note says.
        // Modality = first catalog cardio entry by rank (deterministic),
        // equipment-filtered like everything else.
        if inputs.cardioDays > 0 {
            let modality = usable.first { $0.category == "cardio" }
                ?? catalog.first { $0.category == "cardio" }
            if let modality {
                // Cardio style (TrainingProfile): explicit preference wins;
                // auto keeps the focus default.
                let zone: Int
                switch inputs.cardioStyle {
                case .intervals: zone = 4
                case .steady: zone = 2
                case .auto: zone = inputs.focus == .conditioning ? 4 : 2
                }
                let cardioEntry = Exercise(
                    exerciseID: modality.id, name: modality.name,
                    sets: 1, repsLow: 0, repsHigh: 0,
                    restSeconds: 0, percentOfMax: nil, isMain: false,
                    slot: nil, cardioZone: zone,
                    cardioMinutes: inputs.cardioMinutes)

                let overflow = max(0, days.count + inputs.cardioDays - 7)
                // Pair onto HARD days only — never stack cardio onto the
                // converted recovery day.
                let paired = min(overflow, hardDayCount)
                for index in 0..<paired {
                    days[index].name += " · PM Cardio"
                    days[index].exercises.append(cardioEntry)
                }
                if paired > 0 {
                    notes.append("Cardio rides \(paired) lifting day\(paired == 1 ? "" : "s") as a PM session — keep 6+ hours between the lift and the cardio where you can (Wilson et al.: same-day interference shrinks with separation).")
                }
                let standalone = inputs.cardioDays - paired
                if standalone > 0 {
                    for n in 1...standalone {
                        let label = standalone > 1 ? "Cardio \(n)" : "Cardio"
                        days.append(Day(name: label, exercises: [cardioEntry]))
                    }
                }
                // Cardio periodizes too (trainer audit: flat zone work for
                // 8 straight weeks has no recovery undulation while the
                // lifting side waves and deloads).
                notes.append("Progress the cardio like the lifting: add ~5 minutes or one interval every two weeks, and halve it on the deload week.")
            }
        }

        // "Train every day" (owner 2026-08-14): remaining calendar days
        // become ACTIVE RECOVERY — get in the gym, but the prescription
        // IS recovery: mobility work + a zone-1 walk. Never replaces a
        // hard rest the wave already scheduled (the deload week stands).
        if inputs.fillWeekWithRecovery, days.count < 7 {
            let recoveryCount = 7 - days.count
            for n in 1...recoveryCount {
                let label = recoveryCount > 1 ? "Active Recovery \(n)" : "Active Recovery"
                days.append(recoveryDay(name: label, usable: usable))
            }
            notes.append("Recovery days are prescriptions too: easy mobility and a zone-1 walk aid blood flow without costing adaptation — showing up daily is fine when the easy days stay easy.")
        }

        // Wave: flat for 4 weeks (double progression carries it), ramp
        // with a ¾-mark deload for 8/12 (offered, never forced), and a
        // final-week taper look on strength (volume −50%, intensity held —
        // the peaking research).
        var weeks: [Week] = []
        let deloadWeek = inputs.durationWeeks >= 8
            ? Int((Double(inputs.durationWeeks) * 0.75).rounded()) : nil
        for n in 1...max(1, inputs.durationWeeks) {
            if n == deloadWeek {
                weeks.append(Week(number: n,
                                  volumeMultiplier: GeneratorScience.deloadVolumeMultiplier,
                                  intensityMultiplier: GeneratorScience.deloadIntensityMultiplier,
                                  isDeload: true,
                                  // Field #43: the deload week is where
                                  // mobility lives - half the lifting
                                  // volume frees exactly the time and
                                  // freshness stretching needs.
                                  note: "Deload — move fast, leave fresh. Spend the saved time on mobility: 10–15 minutes of stretching after each session this week, hips and shoulders first."))
            } else {
                let progress = Double(n - 1) / Double(max(1, inputs.durationWeeks - 1))
                weeks.append(Week(number: n,
                                  volumeMultiplier: 1.0,
                                  intensityMultiplier: 1.0 + progress * 0.05,
                                  isDeload: false,
                                  note: nil))
            }
        }
        if inputs.focus == .strength, inputs.durationWeeks >= 8, var last = weeks.last {
            last.volumeMultiplier = GeneratorScience.taperVolumeMultiplier
            last.note = "Peak week — half the volume, keep the bar heavy."
            weeks[weeks.count - 1] = last
        }

        if inputs.sex == .female {
            notes.append("Rep tops on accessory work sit one higher and accessory rests 15s shorter — women are measurably more fatigue-resistant at submaximal loads (Hunter 2014; Hoeger 1990). Zones, movements, and progression are identical by design (Roberts et al. 2020).")
        }
        if inputs.experience == .new {
            notes.append("Beginner volume (6–10 weekly sets per muscle) grows you just as fast — extra sets are cost without benefit in year one (Schoenfeld 2018).")
        }

        return Program(days: days, weeks: weeks, notes: notes)
    }

    // MARK: Slots (day templates — methodology doc)

    enum Slot: Equatable {
        case pattern(String, main: Bool)
        case isolation(String)      // primary muscle
    }

    /// Slot templates by day kind AND FOCUS (owner 2026-08-15:
    /// "hypertrophy and strength always generate the same exact
    /// workouts") — the structures now differ, not just the bands:
    ///   strength     — main-lift emphasis: the compounds, minimal
    ///                  isolation (specificity; volume goes to the bar).
    ///   hypertrophy  — the baseline templates + fuller isolation menu.
    ///   weightLoss   — compound density circuits + core; small-muscle
    ///                  isolation is poor calorie-per-minute work.
    ///   conditioning — a maintenance lifting floor (3 compounds + core);
    ///                  the cardio prescription is the session's point.
    static func slots(for kind: GeneratorScience.DayKind,
                      focus: GeneratorScience.Focus) -> [Slot] {
        let base: [Slot]
        switch kind {
        case .fullBody:
            base = [.pattern("squat", main: true), .pattern("hinge", main: true),
                    .pattern("push_horizontal", main: true), .pattern("pull_horizontal", main: true),
                    .isolation("shoulders"), .isolation("core")]
        case .upper:
            base = [.pattern("push_horizontal", main: true), .pattern("pull_horizontal", main: true),
                    .pattern("push_vertical", main: false), .pattern("pull_vertical", main: false),
                    .isolation("biceps"), .isolation("triceps")]
        case .lower:
            // Core rides lower days (field report 2026-08-21: "no core
            // routines are ever suggested" — only full-body and bro
            // templates carried a core slot).
            base = [.pattern("squat", main: true), .pattern("hinge", main: true),
                    .pattern("lunge", main: false),
                    .isolation("hamstrings"), .isolation("calves"),
                    .isolation("core")]
        case .push:
            base = [.pattern("push_horizontal", main: true), .pattern("push_vertical", main: false),
                    .isolation("shoulders"), .isolation("triceps"), .isolation("chest")]
        case .pull:
            base = [.pattern("pull_horizontal", main: true), .pattern("pull_vertical", main: false),
                    .isolation("shoulders"), .isolation("biceps"), .isolation("back")]
        case .legs:
            base = [.pattern("squat", main: true), .pattern("hinge", main: true),
                    .pattern("lunge", main: false),
                    .isolation("hamstrings"), .isolation("quads"), .isolation("calves"),
                    .isolation("core")]
        // Bodypart days (bro/hybrid splits, TrainingProfile 2026-08-20).
        // Duplicate isolation slots pick DIFFERENT exercises — the
        // already-chosen exclusion guarantees it.
        case .chest:
            base = [.pattern("push_horizontal", main: true),
                    .pattern("push_horizontal", main: false),
                    .isolation("chest"), .isolation("chest")]
        case .back:
            base = [.pattern("pull_horizontal", main: true),
                    .pattern("pull_vertical", main: false),
                    .isolation("back"), .isolation("lats")]
        case .shoulders:
            base = [.pattern("push_vertical", main: true),
                    .isolation("shoulders"), .isolation("shoulders"),
                    .isolation("core")]
        case .arms:
            // No main on purpose — the classic arms day is isolation
            // through and through; every downstream pass tolerates a
            // main-less day (finishers and axial staggers just skip it).
            base = [.isolation("biceps"), .isolation("triceps"),
                    .isolation("biceps"), .isolation("triceps"),
                    .isolation("core")]
        }
        // Bodypart days keep their slot templates under EVERY focus —
        // isolation is the nature of a bro/hybrid day, and stripping it
        // (the strength filter below) would empty an arms day entirely.
        // The athlete chose this split knowingly; the pushback card
        // already made the science case once.
        let bodypartKinds: Set<GeneratorScience.DayKind> = [.chest, .back, .shoulders, .arms]
        if bodypartKinds.contains(kind) { return base }
        switch focus {
        case .hypertrophy:
            return base
        case .strength:
            // Corpus reversal (accessory pass 2026-08-21, 70 findings,
            // strength-authoritative channels): compounds-only was a
            // caricature. Assistance work strengthens the core lifts -
            // better stimulus-to-fatigue than more heavy compound sets,
            // weak-point coverage compounds anatomically CANNOT provide
            // (hamstrings' biarticular cancellation in squats, triceps
            // long head shortchanged by pressing, anterior core), and
            // fatigue relief. The discipline is dose and selection, not
            // exclusion: up to TWO supportive isolations per day from
            // the assistance canon, after the mains - and the session-
            // cap ladder still trims them first when time is short.
            let supportive: Set<String>
            switch kind {
            case .upper: supportive = ["triceps", "back"]
            case .push: supportive = ["triceps", "shoulders"]
            case .pull: supportive = ["back", "shoulders"]
            case .lower, .legs: supportive = ["hamstrings", "core"]
            case .fullBody: supportive = ["core"]
            default: supportive = []
            }
            var kept = 0
            return base.filter { slot in
                if case .pattern = slot { return true }
                if case .isolation(let muscle) = slot,
                   supportive.contains(muscle), kept < 2 {
                    kept += 1
                    return true
                }
                return false
            }
        case .weightLoss:
            // Compounds + core: big-muscle density work. Small-muscle
            // isolation is poor calorie-per-minute training.
            return base.filter { slot in
                if case .pattern = slot { return true }
                if case .isolation("core") = slot { return true }
                return false
            } + (kind == .fullBody ? [] : [.isolation("core")])
        case .conditioning:
            // The maintenance floor: three compounds + core. Lifting
            // holds muscle; the zone work is the training.
            //
            // Selected by COVERAGE, not template order (audit 2026-08-25).
            // Taking the first three patterns off a `.fullBody` base
            // yielded squat + hinge + horizontal push and silently deleted
            // horizontal pulling from every day of the block — a
            // conditioning program with no rowing in it at all. A push and
            // a pull are now reserved before anything else fills a seat.
            var trimmed: [Slot] = []
            func take(_ matches: (String) -> Bool) {
                guard trimmed.count < 3,
                      let slot = base.first(where: { candidate in
                          if case .pattern(let name, _) = candidate {
                              return matches(name) && !trimmed.contains(candidate)
                          }
                          return false
                      }) else { return }
                trimmed.append(slot)
            }
            take { $0.hasPrefix("push") }
            take { $0.hasPrefix("pull") }
            for slot in base {
                guard trimmed.count < 3 else { break }
                if case .pattern = slot, !trimmed.contains(slot) { trimmed.append(slot) }
            }
            trimmed.append(.isolation("core"))
            return trimmed
        }
    }

    // MARK: Selection (the 8 rules, deterministic)

    /// The label-key spelling for a focus (weightLoss → weight_loss).
    static func focusScoreKey(_ focus: GeneratorScience.Focus) -> String {
        focus == .weightLoss ? "weight_loss" : focus.rawValue
    }

    static func select(slot: Slot, from catalog: [CatalogExercise],
                       excluding: Set<UUID>,
                       focus: GeneratorScience.Focus,
                       focusMuscles: Set<String>?,
                       experience: GeneratorScience.Experience = .intermediate,
                       seed: Int = 0,
                       // TrainingProfile tilts (2026-08-20); defaults
                       // reproduce pre-profile behavior exactly.
                       tilt: [String: Double]? = nil,
                       cautionJoints: Set<String> = [],
                       axialBoost: Bool = false,
                       impactCaution: Bool = false,
                       complexityCapOverride: Int? = nil,
                       starred: Set<UUID> = [],
                       sportLens: String? = nil,
                       lens: CoachPersona.Lens? = nil,
                       deprioritized: Set<UUID> = []) -> CatalogExercise? {
        let candidates: [CatalogExercise]
        switch slot {
        case .pattern(let pattern, _):
            candidates = catalog.filter { $0.movementPattern == pattern && !excluding.contains($0.id) }
        case .isolation(let muscle):
            candidates = catalog.filter {
                $0.primaryMuscle == muscle && $0.category == "isolation" && !excluding.contains($0.id)
            }
        }
        guard !candidates.isEmpty else { return nil }
        // SCORE-FIRST selection (labels rewire, 2026-08-16): the swarm-
        // authored focus_scores lead; the equipment ladder — formerly the
        // primary rule — is now a tiebreak among equally-scored lifts.
        // Order: penalty (unlabeled-catalog safety net) → complexity gate
        // (soft: violators sort last, never leave a hole; owner law —
        // gates by experience, never penalizes) → focus muscles →
        // effectiveness score DESC → lengthened bias (hypertrophy
        // accessories) → ladder → rank.
        let ladder = GeneratorScience.mainEquipmentLadder(focus: focus)
        let isMain: Bool
        if case .pattern(_, let main) = slot { isMain = main } else { isMain = false }
        let cap = complexityCapOverride ?? GeneratorScience.complexityCap(experience: experience)
        let scoreKey = focusScoreKey(focus)
        func tier(_ c: CatalogExercise) -> (Int, Int, Int, Int, Int, Int) {
            let pen = GeneratorScience.selectionPenalty(name: c.name)
            // Unstable-surface safeguard (trainer audit: Bosu work
            // auto-prescribed to a first-week trainee) — treated as
            // complexity ≥4 regardless of label.
            let lower = c.name.lowercased()
            var effComplexity = (lower.contains("bosu") || lower.contains("stability ball"))
                ? max(c.complexity, 4) : c.complexity
            // Smith corpus pass (2026-08-22): the rail loads positions a
            // free bar would refuse, and foot placement IS the skill -
            // "keep it away from true beginners." Complexity floor 3
            // gates NEW lifters softly; everyone else is untouched.
            if lower.contains("smith") { effComplexity = max(effComplexity, 3) }
            let gateViolation = effComplexity > cap ? 1 : 0
            // Caution joints (TrainingProfile injury propagation, owner
            // 2026-08-20): a lift stressing a cautioned joint sorts LAST —
            // soft like the complexity gate, never leaves a hole. Merged
            // with the gate into one component (Swift compares tuples only
            // to arity 6); gate dominates by weight.
            let cautionViolation = cautionJoints.isEmpty ? 0
                : (c.jointStress.contains { cautionJoints.contains($0.lowercased()) } ? 1 : 0)
            // Weakest soft gate: the athlete kept skipping this lift last
            // block (BlockReview) — it competes only when nothing better
            // exists. Weights keep the three gates strictly ordered.
            let skippedLastBlock = deprioritized.contains(c.id) ? 1 : 0
            // Core-slot fit (corpus pass 2026-08-21, 8 channels): for
            // physique-flavored focuses, LOADED FLEXION (crunches, leg
            // raises, rollouts) beats twists/side bends (oblique growth
            // thickens the waist - Menno) and unloaded planks (no
            // eccentric, no growth - RP). Conditioning keeps stability
            // work un-demoted; the accessory machine-first ladder already
            // buries bodyweight planks further.
            var coreFit = 0
            if case .isolation("core") = slot, focus != .conditioning {
                if lower.contains("twist") || lower.contains("rotation")
                    || lower.contains("side bend") || lower.contains("oblique")
                    || lower.contains("plank") {
                    coreFit = 1
                }
            }
            // Impact caution (body context 2026-08-21): landings are a
            // joint hazard at the profile's bodyweight, so high-impact
            // rows sort behind — below the injury caution (a named joint
            // beats a general risk), above the skipped-lift memory.
            let impactViolation = (impactCaution && c.impact == "high") ? 1 : 0
            let gates = gateViolation * 16 + cautionViolation * 8
                + impactViolation * 4 + skippedLastBlock * 2 + coreFit
            let focusStanding = (focusMuscles?.contains(c.primaryMuscle) == true) ? 0 : 1
            // Unscored rows sit at a neutral 5 — between cornerstone and
            // filler — so a half-labeled catalog stays sane.
            // With a profile tilt, the score is the WEIGHTED sum over the
            // full goal vector (x10 for integer ordering) — this is where
            // a 0.3-weighted secondary goal shows up in what gets picked.
            // Axial boost (bone_density ranked): spinalLoad 0-2 joins the
            // score at matching scale.
            // Persona lens (CoachPersona stances, label-space only): the
            // fatigue-averse coach docks systemic drain, the hybrid coach
            // boosts explosive intent. Same scale as the axial boost.
            var lensAdjust = 0
            if let lens, lens.fatigueAverse { lensAdjust -= c.fatigueCost }
            // Explosive fit as a TIER, not a score bump (audit round 2):
            // a score bump lost narrowly for the power athlete (A01) and
            // conditioning's own scores made cone hops the desk worker's
            // squat main (A25). Explosive work is a SPECIALIST tool: the
            // granted slot prefers it outright; every other main slot
            // demotes it. Accessories never favor plyo over equals.
            let explosiveFit: Int
            if isMain, lens?.explosiveEmphasis == true {
                explosiveFit = c.explosive ? 0 : 1
            } else {
                explosiveFit = c.explosive ? 1 : 0
            }
            let score: Int
            if let tilt, !tilt.isEmpty {
                var s = 0.0
                for (key, weight) in tilt { s += weight * Double(c.focusScores[key] ?? 5) }
                score = Int((s * 10).rounded())
                    + (axialBoost ? c.spinalLoad * 10 : 0) + lensAdjust * 10
            } else {
                score = (c.focusScores[scoreKey] ?? 5)
                    + (axialBoost ? c.spinalLoad * 2 : 0) + lensAdjust * 2
            }
            // Stretch emphasis: hypertrophy's default accessory tiebreak,
            // extended to every focus for the stretch-emphasis coaches.
            let wantsStretch = focus == .hypertrophy || lens?.stretchEmphasis == true
            let stretch = (!isMain && wantsStretch && c.lengthenedBias) ? 0 : 1
            let lad: Int
            if isMain {
                lad = ladder[c.equipment] ?? 5
            } else if lens?.barbellFirst == true {
                // The strength-purist stance: accessories prefer the bar.
                let barFirst = ["barbell": 0, "ez-bar": 0, "dumbbell": 1, "machine": 2, "cable": 2, "bodyweight": 3]
                lad = barFirst[c.equipment] ?? 4
            } else {
                // Rule 5: accessories favor machine/cable (low systemic
                // fatigue, safe near failure).
                let inverse = ["machine": 0, "cable": 0, "dumbbell": 1, "bodyweight": 2, "barbell": 3, "ez-bar": 3]
                lad = inverse[c.equipment] ?? 4
            }
            // Corpus attestation prior (mentions export 2026-08-20): a
            // lift NO research channel teaches never outranks one the
            // field teaches, whatever its swarm-authored score claims —
            // score dominance only holds where the corpus vouches for the
            // row. Soft like every gate: silent rows still fill a slot
            // when nothing attested fits. The 2-channel consensus bar
            // (strong vs weak) is title-mined and under-counts, so it
            // only splits ties below the score, never the ranking.
            let attestedChannels = CorpusAttestation.channels(name: c.name)
            let attestSilent = attestedChannels == 0 ? 1 : 0
            let attestWeak = attestedChannels >= 2 ? 0 : 1
            // Novice simplicity preference (audit 2026-08-20, the Pendlay
            // finding): for a NEW lifter, simpler wins among viable
            // candidates BEFORE the score — no boost may promote a
            // technical lift over a simple one on day one. The axial
            // boost still works, but only among equally simple choices.
            // Zero for everyone else, so ordering is unchanged past novice.
            let simplicity = experience == .new ? effComplexity : 0
            // simplicity*4 + explosiveFit in one component (tuple arity):
            // for a novice, SIMPLE beats explosive-preferred — the coach
            // doesn't open a beginner with depth jumps; past novice,
            // simplicity is 0 and the explosive tier decides alone.
            // stretch*8+lad merges two tiebreaks the same way; stretch
            // dominates since lad <= 5.
            // Sport lens (sport-prep corpus 2026-08-21): wrestling's
            // unilateral-first law; football's unilateral lower-body
            // preference; baseball's cuff-first accessory shoulders
            // (arm care outranks delt aesthetics for throwers). A TIER
            // below novice simplicity, above the explosive preference.
            var sportFit = 0
            if let sportLens {
                switch sportLens {
                case "wrestling":
                    sportFit = c.unilateral ? 0 : 1
                    if lower.contains("smith") { sportFit = 1 }
                case "football":
                    let lowerBody = c.movementPattern == "squat" || c.movementPattern == "lunge"
                        || ["quads", "hamstrings", "glutes"].contains(c.primaryMuscle)
                    // Smith corpus pass: athletes need the instability
                    // the rail removes - S&C consensus demotes it.
                    sportFit = (c.unilateral && lowerBody && !lower.contains("smith")) ? 0 : 1
                case "baseball":
                    if case .isolation("shoulders") = slot, !isMain {
                        let cuff = lower.contains("external rotation") || lower.contains("face pull")
                            || lower.contains("band pull") || lower.contains("cuff")
                        sportFit = cuff ? 0 : 1
                    }
                default:
                    break
                }
            }
            // Starred-routine preference: the athlete's own aspiration,
            // dead last among the soft signals — above only the ladder.
            let starPref = starred.contains(c.id) ? 0 : 1
            // attestSilent*10_000 - score in one component (tuple arity):
            // scores are bounded well under 10_000 (tilt path peaks near
            // ~500), so silence dominates score without a new slot.
            // Final component, ordered by weight bounds: attestWeak*32
            // dominates stretch*16 + starPref*8 + lad (max 29); stretch
            // dominates starPref*8 + lad (max 13); starPref dominates
            // lad (max 5).
            // simplicity*8 + sportFit*2 + explosiveFit: the novice
            // simple-first law still dominates (8 > 2+1); the sport lens
            // outranks the explosive preference (a wrestler's split
            // squat beats a bilateral jump at equal score).
            return (pen, gates, focusStanding,
                    simplicity * 8 + sportFit * 2 + explosiveFit,
                    attestSilent * 10_000 - score,
                    attestWeak * 32 + stretch * 16 + starPref * 8 + lad)
        }
        let sorted = candidates.sorted { a, b in
            let ta = tier(a), tb = tier(b)
            if ta != tb { return ta < tb }
            return a.rank < b.rank
        }
        guard let first = sorted.first else { return nil }
        guard seed > 0 else { return first }
        // Deterministic variety (owner 2026-08-15): rotate within the top
        // equivalence tier only — the seed never promotes a worse-tier
        // pick, so every science rule still holds at any seed.
        let top = sorted.prefix { tier($0) == tier(first) }
        return top[top.startIndex + seed % top.count]
    }

    // MARK: Prescription

    static func prescription(for ex: CatalogExercise, slot: Slot,
                             band: GeneratorScience.FocusBand,
                             inputs: Inputs, setsPerExercise: Int) -> Exercise {
        let isMain: Bool
        if case .pattern(_, let main) = slot { isMain = main } else { isMain = false }
        var repsLow = isMain ? band.mainRepsLow : band.accessoryRepsLow
        var repsHigh = isMain ? band.mainRepsHigh : band.accessoryRepsHigh
        // Novice on-ramp rep floor (audit 2026-08-20): triples are a
        // SKILL — a new lifter under a strength-flavored band opens at
        // 5-8, not 3-6. Fives teach the pattern; heavier waits for the
        // graduation probe.
        if inputs.experience == .new, isMain, repsLow < 5 {
            repsLow = 5
            repsHigh = max(repsHigh, 8)
        }
        // Rep-window clamp (labels): outside its sensible window a lift is
        // unsafe or pointless (20-rep deadlifts, 3-rep lateral raises —
        // trainer audit). Clamp the band into the exercise's window.
        if let lo = ex.repMin, let hi = ex.repMax, lo > 0, hi >= lo {
            repsLow = max(repsLow, lo)
            repsHigh = min(repsHigh, hi)
            if repsLow > repsHigh { repsLow = repsHigh }
        }
        // The %1RM anchor derives from the SEX-NEUTRAL range top: the
        // female rep-top bonus widens the range (fatigue-resistance
        // physiology), and must never lighten the load zone — zones are
        // identical by sex, the parity law (Roberts et al. 2020). CI
        // caught exactly this drift when the anchor briefly followed the
        // bonused top.
        let anchorReps = repsHigh
        repsHigh += GeneratorScience.repRangeTopBonus(sex: inputs.sex, repsHigh: repsHigh)
        var rest = isMain ? band.mainRestSeconds : band.accessoryRestSeconds
        if !isMain { rest = max(30, rest + GeneratorScience.accessoryRestDelta(sex: inputs.sex)) }
        // %1RM anchored to the RANGE TOP (trainer audit: the midpoint
        // anchor printed 90% beside a 6-rep target the table itself says
        // 90% cannot support) — the weight must carry the whole range.
        // Then the EXPERIENCE CEILING (the audit's most-repeated critical:
        // novices at 90% with no established max) and the unilateral
        // derate (a balance-demanding substitute must not inherit a
        // bilateral near-max prescription).
        var percent: Double? = nil
        if isMain {
            if ex.equipment == "bodyweight" || (ex.explosive && ex.equipment != "barbell") {
                // No meaningful %1RM exists for bodyweight mains (audit
                // round 2: "Chest Dip @70%") or explosive implement drills
                // ("@80%" cone hops) — the anchor stays silent rather
                // than fictional.
                percent = nil
            } else {
                var p = GeneratorScience.percentFor(reps: anchorReps)
                // Power work lives at 30-60% 1RM — bar speed IS the
                // stimulus; a heavy explosive lift is just a slow lift.
                if ex.explosive { p = min(p, 60) }
                // intensityAppetite finally consumed (audit: the dead
                // knob): conservative eases the anchor, aggressive nudges
                // it — the experience ceiling still has the last word.
                switch inputs.intensityAppetite {
                case "conservative": p -= 5
                case "aggressive": p += 2.5
                default: break
                }
                p = min(p, GeneratorScience.mainIntensityCeiling(experience: inputs.experience))
                if ex.unilateral { p = min(p, 80) }
                percent = max(50, p)
            }
        }
        return Exercise(exerciseID: ex.id, name: ex.name,
                        sets: setsPerExercise,
                        repsLow: repsLow, repsHigh: repsHigh,
                        restSeconds: rest,
                        percentOfMax: percent,
                        isMain: isMain,
                        slot: slot)
    }

    /// One active-recovery day (recovery research: 20-40 min zone 1-2 +
    /// easy mobility aids blood flow without costing adaptation): 2-3
    /// mobility movements at 2×8-12 easy + a 25-minute zone-1 walk.
    static func recoveryDay(name: String, usable: [CatalogExercise]) -> Day {
        let mobility = Array(usable.filter { $0.category == "mobility" }.prefix(3))
        let walk = usable.first {
            $0.category == "cardio" && $0.name.localizedCaseInsensitiveContains("walk")
        } ?? usable.first { $0.category == "cardio" }
        var entries: [Exercise] = mobility.map { m in
            Exercise(exerciseID: m.id, name: m.name,
                     sets: 2, repsLow: 8, repsHigh: 12,
                     restSeconds: 30, percentOfMax: nil, isMain: false,
                     slot: nil, cardioZone: nil, cardioMinutes: nil)
        }
        if let walk {
            entries.append(Exercise(
                exerciseID: walk.id, name: walk.name,
                sets: 1, repsLow: 0, repsHigh: 0,
                restSeconds: 0, percentOfMax: nil, isMain: false,
                slot: nil, cardioZone: 1, cardioMinutes: 25))
        }
        return Day(name: name, exercises: entries)
    }

    // MARK: Reroll (owner 2026-08-14: "allow people to reroll accessories
    // if they have an objection")
    //
    // Deterministic next-best, never a shuffle: the SAME slot selection
    // re-runs with everything already in the day PLUS the rejected pick
    // excluded — reroll twice and you walk the ranked candidate list.
    /// `alsoExcluding` (field 2026-08-25: "each exercise only has 1
    /// alternate"): selection is deterministic, and excluding only the
    /// day's CURRENT lifts made roll #2 hand the original straight back —
    /// a two-exercise ping-pong. The caller passes every id this slot has
    /// already shown so consecutive rolls walk DOWN the ranked pool; when
    /// the pool runs dry the caller clears its history and the cycle
    /// restarts.
    /// The candidate pool for an athlete: equipment they have, minus the
    /// lifts that do not exist for them. Factored out (audit 2026-08-25)
    /// because `reroll` had its own equipment-only copy and therefore
    /// handed back exercises the athlete had explicitly excluded — the
    /// roll button silently outranked an injury exclusion.
    static func usableCatalog(_ catalog: [CatalogExercise],
                              inputs: Inputs) -> [CatalogExercise] {
        catalog.filter { ex in
            guard inputs.equipment.map({ allowed in
                allowed.contains(ex.equipment)
                    || (ex.equipment == "ez-bar" && allowed.contains("barbell"))
            }) ?? true else { return false }
            // Hard exclusions (TrainingProfile): these lifts do not exist
            // for this athlete. The selector's next-best (and ultimately
            // the substitution graph) fills every hole.
            if inputs.excludedExerciseIDs.contains(ex.id) { return false }
            if inputs.excludedPatterns.contains(ex.movementPattern) { return false }
            return true
        }
    }

    static func reroll(_ exercise: Exercise, in day: Day,
                       inputs: Inputs, catalog: [CatalogExercise],
                       alsoExcluding: Set<UUID> = []) -> Exercise? {
        guard let slot = exercise.slot else { return nil }
        let usable = usableCatalog(catalog, inputs: inputs)
        var excluded = Set(day.exercises.map(\.exerciseID))
        excluded.formUnion(alsoExcluding)
        excluded.insert(exercise.exerciseID)
        // Audit 2026-08-25: reroll passed only focus + focusMuscles, so the
        // shipped variation control discarded every gate the generated
        // program had honored — the derived complexity cap, injury joint
        // cautions, impact caution, the sport and persona lenses, the
        // starred tiebreak and the block-carryover deprioritization. A roll
        // could therefore hand a novice a lift above their comfort ceiling.
        // `seed: 0` on purpose: reroll is a ranked walk down the pool
        // (`alsoExcluding` carries the history), never a shuffle.
        guard let next = select(slot: slot, from: usable, excluding: excluded,
                                focus: inputs.focus,
                                focusMuscles: inputs.focusMuscles,
                                experience: inputs.experience,
                                seed: 0,
                                tilt: inputs.selectionTilt,
                                cautionJoints: inputs.cautionJoints,
                                axialBoost: inputs.axialBoost,
                                impactCaution: inputs.impactCaution,
                                complexityCapOverride: inputs.complexityCapOverride,
                                starred: inputs.starredExerciseIDs,
                                sportLens: inputs.sportPrepSport,
                                lens: inputs.personaLens,
                                deprioritized: inputs.deprioritizedExerciseIDs) else { return nil }
        var replacement = prescription(for: next, slot: slot,
                                       band: GeneratorScience.band(for: inputs.focus),
                                       inputs: inputs,
                                       setsPerExercise: exercise.sets)
        replacement.sets = exercise.sets
        return replacement
    }

    // MARK: Helpers

    /// Antagonist-superset pairing (session structure `supersets` — the
    /// corpus's single most-discussed style, 173 videos / 12 channels):
    /// opposing patterns alternate sets, halving session time with
    /// near-zero performance cost BECAUSE the pairs are antagonists — one
    /// side rests while the other works. Pairs are assigned greedily in
    /// program order; anything unpaired stays straight sets. Cardio and
    /// core never pair.
    /// The accessory tail reordered so systemic drain alternates: sort
    /// accessories by fatigue_cost descending, then weave
    /// highest/lowest/2nd-highest/2nd-lowest. A day with fewer than
    /// three accessories has nothing to stagger. Runs BEFORE superset
    /// assignment, which pairs by muscle over the staggered order.
    static func staggerFatigue(_ exercises: [Exercise],
                               catalog: [CatalogExercise]) -> [Exercise] {
        let mains = exercises.filter(\.isMain)
        let accessories = exercises.filter { !$0.isMain }
        guard accessories.count >= 3 else { return exercises }
        let fatigueByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0.fatigueCost) })
        let sorted = accessories.sorted {
            let fa = fatigueByID[$0.exerciseID] ?? 3
            let fb = fatigueByID[$1.exerciseID] ?? 3
            if fa != fb { return fa > fb }
            // Stable within a fatigue tier: keep selection order.
            return accessories.firstIndex(of: $0)! < accessories.firstIndex(of: $1)!
        }
        var woven: [Exercise] = []
        var lo = 0, hi = sorted.count - 1
        var takeHigh = true
        while lo <= hi {
            if takeHigh {
                woven.append(sorted[lo]); lo += 1
            } else {
                woven.append(sorted[hi]); hi -= 1
            }
            takeHigh.toggle()
        }
        return mains + woven
    }

    static func assignSupersets(day: Day, catalog: [CatalogExercise]) -> Day {
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        // Opposing-pattern table; isolation pairs oppose by primary muscle.
        let opposing: [String: String] = [
            "push_horizontal": "pull_horizontal", "pull_horizontal": "push_horizontal",
            "push_vertical": "pull_vertical", "pull_vertical": "push_vertical",
        ]
        let opposingMuscle: [String: String] = [
            "biceps": "triceps", "triceps": "biceps",
            "quads": "hamstrings", "hamstrings": "quads",
            "chest": "back", "back": "chest",
        ]
        func pairKey(_ e: Exercise) -> (want: String, offer: String)? {
            guard e.cardioZone == nil, let cat = byID[e.exerciseID] else { return nil }
            if let opposite = opposing[cat.movementPattern] {
                return (opposite, cat.movementPattern)
            }
            if cat.category == "isolation" {
                let muscle = cat.primaryMuscle.lowercased()
                if let opposite = opposingMuscle[muscle] { return ("iso:" + opposite, "iso:" + muscle) }
            }
            return nil
        }
        var day = day
        var group = 0
        var openOffers: [String: Int] = [:]   // offered key -> exercise index
        for index in day.exercises.indices {
            guard day.exercises[index].supersetGroup == nil,
                  let key = pairKey(day.exercises[index]) else { continue }
            if let partner = openOffers[key.want],
               day.exercises[partner].supersetGroup == nil {
                group += 1
                day.exercises[partner].supersetGroup = group
                day.exercises[index].supersetGroup = group
                openOffers[key.want] = nil
            } else {
                openOffers[key.offer] = index
            }
        }
        return day
    }

    /// Effective weekly sets per muscle across lifting days. Fractional
    /// counting — a set counts 1.0 for the primary muscle and 0.5 per
    /// secondary — the convention the volume literature's set counts use.
    /// Keys are lowercased muscle names; cardio entries contribute nothing.
    static func weeklyMuscleSets(days: [Day],
                                 catalog: [CatalogExercise]) -> [String: Double] {
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var tally: [String: Double] = [:]
        for day in days {
            for e in day.exercises where e.cardioZone == nil {
                guard let cat = byID[e.exerciseID] else { continue }
                tally[cat.primaryMuscle.lowercased(), default: 0] += Double(e.sets)
                for muscle in cat.secondaryMuscles {
                    tally[muscle.lowercased(), default: 0] += Double(e.sets) * 0.5
                }
            }
        }
        return tally
    }

    /// Week-level volume post-pass. FLOOR first: a muscle the plan trains
    /// as a PRIMARY somewhere but leaves under the weekly band's low end
    /// gains accessory sets (cap 5/exercise). CEILING second — and last,
    /// so the floor pass can never re-break it, because the ceiling is
    /// the hard promise (the confirmed defect was overshoot): over-covered
    /// muscles lose accessory sets (floor 2/exercise). Mains are NEVER
    /// touched in either direction — slot logic owns them. Muscles that
    /// appear only as secondaries get no floor: incidental volume is not
    /// a training commitment. Deterministic: muscles alphabetical, adds to
    /// the first qualifying accessory, trims from the last.
    static func balanceWeeklyVolume(
        days: [Day], catalog: [CatalogExercise], low: Int, high: Int,
        protectedDayNames: Set<String> = []
    ) -> (days: [Day], trimmed: Int, added: Int) {
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var days = days
        var trimmed = 0, added = 0

        func primaryOf(_ e: Exercise) -> String? {
            guard e.cardioZone == nil else { return nil }
            return byID[e.exerciseID]?.primaryMuscle.lowercased()
        }
        // (dayIndex, exIndex) of accessories whose primary is `muscle`,
        // in program order.
        func accessorySites(for muscle: String) -> [(Int, Int)] {
            var sites: [(Int, Int)] = []
            for d in days.indices {
                for x in days[d].exercises.indices {
                    let e = days[d].exercises[x]
                    if !e.isMain, primaryOf(e) == muscle { sites.append((d, x)) }
                }
            }
            return sites
        }
        let primaryTrained = Set(days.flatMap(\.exercises).compactMap(primaryOf))

        // FLOOR
        for muscle in primaryTrained.sorted() {
            var guardRail = 32
            while weeklyMuscleSets(days: days, catalog: catalog)[muscle, default: 0]
                    < Double(low), guardRail > 0 {
                guardRail -= 1
                guard let (d, x) = accessorySites(for: muscle)
                        .first(where: { days[$0.0].exercises[$0.1].sets < 5 })
                else { break }
                days[d].exercises[x].sets += 1
                added += 1
            }
        }
        // CEILING
        let allMuscles = weeklyMuscleSets(days: days, catalog: catalog).keys.sorted()
        for muscle in allMuscles {
            var guardRail = 32
            while weeklyMuscleSets(days: days, catalog: catalog)[muscle, default: 0]
                    > Double(high), guardRail > 0 {
                guardRail -= 1
                // Emphasis days (hybrid split, A18) yield their sets
                // LAST — the athlete chose this split FOR those days.
                let sites = accessorySites(for: muscle)
                    .filter { days[$0.0].exercises[$0.1].sets > 2 }
                guard let (d, x) = sites.last(where: { !protectedDayNames.contains(days[$0.0].name) })
                        ?? sites.last
                else { break }
                days[d].exercises[x].sets -= 1
                trimmed += 1
            }
        }
        return (days, trimmed, added)
    }

    private static func setsPerSlot(slot: Slot, perDayBudget: Int) -> Int {
        if case .pattern(_, true) = slot { return max(3, min(5, perDayBudget)) }
        return max(2, min(4, perDayBudget - 1))
    }

    private static func muscleFrequency(split: [GeneratorScience.DayKind]) -> Int {
        // How many times per week the split touches a typical muscle —
        // full-body = every day; UL/PPL = half the days.
        let fullBody = split.filter { $0 == .fullBody }.count
        if fullBody > 0 { return fullBody }
        // Bodypart days: a bro muscle's one day carries its whole week
        // (frequency 1); a hybrid's upper/lower base gives the second
        // touch (frequency 2).
        let bodypart: Set<GeneratorScience.DayKind> = [.chest, .back, .shoulders, .arms]
        if split.contains(where: { bodypart.contains($0) }) {
            return split.contains(.upper) || split.contains(.lower) ? 2 : 1
        }
        return max(1, split.count / 2)
    }

    private static func dayName(kind: GeneratorScience.DayKind, index: Int,
                                split: [GeneratorScience.DayKind]) -> String {
        let sameKind = split.enumerated().filter { $0.element == kind }
        let ordinal = (sameKind.firstIndex { $0.offset == index } ?? 0) + 1
        let base: String
        switch kind {
        case .fullBody: base = "Full Body"
        case .upper: base = "Upper"
        case .lower: base = "Lower"
        case .push: base = "Push"
        case .pull: base = "Pull"
        case .legs: base = "Legs"
        case .chest: base = "Chest"
        case .back: base = "Back"
        case .shoulders: base = "Shoulders"
        case .arms: base = "Arms"
        }
        return sameKind.count > 1 ? "\(base) \(ordinal)" : base
    }

    // MARK: Data bridge (program_template_weeks contract)

    /// The generated wave as `[ProgramWeek]` rows — the SUMMARY a template
    /// row carries (store card, Plan queue), never the executable program
    /// (the day routines carry that). One line per week: the lead main
    /// lift's prescription with the wave's multipliers applied. Percent
    /// stays nil when the generator prescribed by rep range alone.
    static func weekSummaries(_ program: Program) -> [ProgramWeek] {
        let lifts = program.days.flatMap(\.exercises).filter { $0.cardioZone == nil }
        guard let main = lifts.first(where: { $0.isMain }) ?? lifts.first else { return [] }
        return program.weeks.map { week in
            ProgramWeek(
                percentOfBaseline: main.percentOfMax.map {
                    ($0 * week.intensityMultiplier).rounded()
                },
                sets: max(1, Int((Double(main.sets) * week.volumeMultiplier).rounded())),
                reps: main.repsLow,
                isDeload: week.isDeload,
                note: week.note)
        }
    }
}
