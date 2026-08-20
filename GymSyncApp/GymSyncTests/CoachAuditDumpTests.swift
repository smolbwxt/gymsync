import XCTest
@testable import GymSync

/// The 20-athlete audit (owner 2026-08-20: "generate 20 different test
/// cases and really inspect the results… think outside of the
/// programming: is this appropriate for the person?").
///
/// Runs the REAL profile -> generatorInputs -> generate() pipeline over
/// the LABELED production snapshot and prints each program human-readable,
/// prefixed AUDIT| — CI's log becomes the corpus a human (or agent) coach
/// reads. Never a reimplementation: what gets audited is what ships.
/// Doubles as a regression harness: all 20 must generate cleanly.
final class CoachAuditDumpTests: XCTestCase {

    private struct Row: Decodable {
        let name: String
        let primary_muscle: String
        let secondary_muscles: [String]
        let category: String
        let equipment: String
        let movement_pattern: String
        let focus_scores: [String: Int]
        let complexity: Int?
        let fatigue_cost: Int?
        let spinal_load: Int?
        let rep_min: Int?
        let rep_max: Int?
        let lengthened_bias: Bool
        let unilateral: Bool
        let explosive: Bool
        let joint_stress: [String]
    }

    private func loadCatalog() throws -> [ProgramGenerator.CatalogExercise] {
        let rows = try JSONDecoder().decode(
            [Row].self, from: LabeledCatalogSnapshot.json.data(using: .utf8)!)
        return rows.enumerated().map { index, row in
            var c = ProgramGenerator.CatalogExercise(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0002-%012d", index))!,
                name: row.name, primaryMuscle: row.primary_muscle,
                secondaryMuscles: row.secondary_muscles,
                category: row.category, equipment: row.equipment,
                movementPattern: row.movement_pattern, rank: index)
            c.focusScores = row.focus_scores
            c.complexity = row.complexity ?? 3
            c.fatigueCost = row.fatigue_cost ?? 3
            c.spinalLoad = row.spinal_load ?? 0
            c.repMin = row.rep_min
            c.repMax = row.rep_max
            c.lengthenedBias = row.lengthened_bias
            c.unilateral = row.unilateral
            c.explosive = row.explosive
            c.jointStress = row.joint_stress
            return c
        }
    }

    private func exerciseID(named name: String,
                            in catalog: [ProgramGenerator.CatalogExercise]) -> UUID? {
        catalog.first { $0.name == name }?.id
    }

    // MARK: The gallery

    private struct Athlete {
        let label: String
        let story: String
        var profile: TrainingProfile
        var persona: String? = nil
        var durationWeeks = 8
        var cardioDays = 0
        var cardioMinutes = 20
        var fillWeek = false
    }

    func testDumpTwentyAthletes() throws {
        let catalog = try loadCatalog()
        var athletes: [Athlete] = []

        func make(_ label: String, _ story: String,
                  _ build: (inout TrainingProfile) -> Void,
                  persona: String? = nil, weeks: Int = 8,
                  cardioDays: Int = 0, cardioMinutes: Int = 20,
                  fillWeek: Bool = false) {
            var profile = TrainingProfile()
            build(&profile)
            if let persona, let coach = CoachPersona.bySlug(persona) {
                profile = coach.apply(to: profile)
            }
            athletes.append(Athlete(label: label, story: story, profile: profile,
                                    persona: persona, durationWeeks: weeks,
                                    cardioDays: cardioDays,
                                    cardioMinutes: cardioMinutes,
                                    fillWeek: fillWeek))
        }

        make("A01-footballer", "16yo football player, in season, wants explosiveness for the field") {
            $0.trainingAge = .intermediate
            $0.rankedGoals = [.powerRFD, .sportPrep, .hypertrophy]
            $0.daysPerWeek = 3
            $0.inSeason = true
        }
        make("A02-senior-first-timer", "50yo, first gym membership, bone density and heart health") {
            $0.trainingAge = .novice
            $0.rankedGoals = [.boneDensity, .generalHealth, .mobility]
            $0.daysPerWeek = 3
            $0.cardioStyle = .steady
        } //, cardio below
        athletes[athletes.count - 1].cardioDays = 2
        athletes[athletes.count - 1].cardioMinutes = 30

        make("A03-golden-era-devotee", "28yo intermediate, wants the classic physique week", {
            $0.trainingAge = .intermediate
            $0.rankedGoals = [.hypertrophy]
            $0.daysPerWeek = 5
        }, persona: "the-golden-era")
        make("A04-scientist-client", "35yo engineer, hypertrophy, wants evidence-flavored training", {
            $0.trainingAge = .intermediate
            $0.rankedGoals = [.hypertrophy]
            $0.daysPerWeek = 4
        }, persona: "the-scientist")
        make("A05-strength-purist", "40yo advanced lifter, strength only, barbell romantic", {
            $0.trainingAge = .advanced
            $0.rankedGoals = [.maxStrength]
            $0.daysPerWeek = 4
        }, persona: "the-strength-purist")
        make("A06-powerbuilder", "30yo intermediate, strength AND size, ranked in that order") {
            $0.trainingAge = .intermediate
            $0.rankedGoals = [.maxStrength, .hypertrophy]
            $0.daysPerWeek = 4
        }
        make("A07-busy-parent", "two kids, 2 days a week, 40 minutes, wants the most from the least", {
            $0.trainingAge = .intermediate
            $0.rankedGoals = [.hypertrophy, .generalHealth]
            $0.daysPerWeek = 2
            $0.sessionMinutes = 40
        }, persona: "the-minimalist")
        make("A08-weight-loss", "45yo novice, weight loss primary, wants walking not sprinting", {
            $0.trainingAge = .novice
            $0.rankedGoals = [.fatLoss, .generalHealth]
            $0.daysPerWeek = 3
            $0.cardioStyle = .steady
        }, cardioDays: 3, cardioMinutes: 35)
        make("A09-hybrid-firefighter", "32yo firefighter, capacity + strength, loves circuits", {
            $0.trainingAge = .intermediate
            $0.rankedGoals = [.conditioning, .maxStrength]
            $0.daysPerWeek = 4
        }, persona: "the-hybrid-athlete")
        make("A10-shoulder-injury", "hypertrophy, but overhead pressing is off the table (shoulder)") {
            $0.trainingAge = .intermediate
            $0.rankedGoals = [.hypertrophy]
            $0.daysPerWeek = 4
            $0.excludedPatterns = ["push_vertical"]
            $0.cautionJoints = ["shoulder"]
        }
        make("A11-home-gym", "dumbbells and bodyweight only, hypertrophy, 3 days") {
            $0.trainingAge = .intermediate
            $0.rankedGoals = [.hypertrophy]
            $0.daysPerWeek = 3
            $0.equipment = ["dumbbell", "bodyweight"]
        }
        make("A12-knee-cautious-runner", "recreational runner, lifts for durability, knees complain") {
            $0.trainingAge = .novice
            $0.rankedGoals = [.generalHealth, .conditioning]
            $0.daysPerWeek = 3
            $0.cautionJoints = ["knee"]
        }
        make("A13-everyday-enthusiast", "wants to train all 7 days, hypertrophy", {
            $0.trainingAge = .intermediate
            $0.rankedGoals = [.hypertrophy]
            $0.daysPerWeek = 7
        }, fillWeek: true)
        make("A14-advanced-ppl", "advanced bodybuilder, 6-day PPL, knows exactly what they want") {
            $0.trainingAge = .advanced
            $0.rankedGoals = [.hypertrophy]
            $0.daysPerWeek = 6
            $0.split = .ppl
            $0.provenance["split"] = .stated
        }
        make("A15-teen-novice", "15yo brand new, wants muscle, needs the on-ramp") {
            $0.trainingAge = .novice
            $0.rankedGoals = [.hypertrophy]
            $0.daysPerWeek = 3
        }
        make("A16-returning-mom", "returning after a long break, general health, conservative") {
            $0.trainingAge = .novice
            $0.rankedGoals = [.generalHealth, .mobility]
            $0.daysPerWeek = 3
            $0.intensityAppetite = "conservative"
        }
        make("A17-meet-prep", "powerlifter 12 weeks out, barbell-only gym", {
            $0.trainingAge = .advanced
            $0.rankedGoals = [.maxStrength]
            $0.daysPerWeek = 4
            $0.equipment = ["barbell", "bodyweight"]
        }, persona: "the-strength-purist", weeks: 12)
        make("A18-bro-hybrid", "loves bodypart days, accepted the coach's hybrid compromise") {
            $0.trainingAge = .intermediate
            $0.rankedGoals = [.hypertrophy]
            $0.daysPerWeek = 5
            $0.split = .hybrid
            $0.provenance["split"] = .confirmed
        }
        make("A19-bad-back", "hypertrophy, but hip hinging is out (low back), cautious there") {
            $0.trainingAge = .intermediate
            $0.rankedGoals = [.hypertrophy]
            $0.daysPerWeek = 4
            $0.excludedPatterns = ["hinge"]
            $0.cautionJoints = ["lower_back"]
        }
        make("A20-wants-everything", "hypertrophy, strength, conditioning AND fat loss, 5 days", {
            $0.trainingAge = .intermediate
            $0.rankedGoals = [.hypertrophy, .maxStrength, .conditioning, .fatLoss]
            $0.daysPerWeek = 5
        }, cardioDays: 2, cardioMinutes: 25)

        XCTAssertEqual(athletes.count, 20)

        for athlete in athletes {
            let inputs = athlete.profile.generatorInputs(
                durationWeeks: athlete.durationWeeks,
                cardioDays: athlete.cardioDays,
                cardioMinutes: athlete.cardioMinutes,
                fillWeekWithRecovery: athlete.fillWeek)
            let program = ProgramGenerator.generate(inputs: inputs, catalog: catalog)
            XCTAssertFalse(program.days.isEmpty, "\(athlete.label) must generate")
            dump(athlete, inputs: inputs, program: program)
        }
    }

    private func dump(_ athlete: Athlete,
                      inputs: ProgramGenerator.Inputs,
                      program: ProgramGenerator.Program) {
        var out: [String] = []
        out.append("==== \(athlete.label) ====")
        out.append("STORY: \(athlete.story)")
        let p = athlete.profile
        out.append("PROFILE: goals=\(p.rankedGoals.map(\.rawValue).joined(separator: ">")) age=\(p.trainingAge.rawValue) days=\(p.daysPerWeek) split=\(p.split.rawValue) structure=\(p.sessionStructure.rawValue) coach=\(athlete.persona ?? "house") inSeason=\(p.inSeason)")
        out.append("INPUTS: focus=\(inputs.focus.rawValue) bandOverride=\(inputs.bandOverride != nil) caution=\(inputs.cautionJoints.sorted().joined(separator: ",")) excludedPatterns=\(inputs.excludedPatterns.sorted().joined(separator: ","))")
        for day in program.days {
            out.append("DAY \(day.name):")
            for ex in day.exercises {
                if let zone = ex.cardioZone {
                    out.append("  - \(ex.name) · zone \(zone) · \(ex.cardioMinutes ?? 0) min")
                } else {
                    var line = "  - \(ex.name) · \(ex.sets)x\(ex.repsLow)-\(ex.repsHigh)"
                    if let pct = ex.percentOfMax { line += " @\(Int(pct))%" }
                    line += " · rest \(ex.restSeconds)s"
                    if ex.isMain { line += " · MAIN" }
                    if let group = ex.supersetGroup { line += " · SS\(group)" }
                    out.append(line)
                }
            }
        }
        for note in program.notes { out.append("NOTE: \(note)") }
        for line in out { print("AUDIT|\(line)") }
    }
}
