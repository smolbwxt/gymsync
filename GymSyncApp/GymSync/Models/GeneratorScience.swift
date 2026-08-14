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

    static func band(for focus: Focus) -> FocusBand {
        switch focus {
        case .strength:
            return FocusBand(mainRepsLow: 3, mainRepsHigh: 6,
                             accessoryRepsLow: 6, accessoryRepsHigh: 10,
                             mainRestSeconds: 180, accessoryRestSeconds: 90,
                             weeklySetsLow: 10, weeklySetsHigh: 16)
        case .hypertrophy:
            return FocusBand(mainRepsLow: 6, mainRepsHigh: 12,
                             accessoryRepsLow: 8, accessoryRepsHigh: 15,
                             mainRestSeconds: 120, accessoryRestSeconds: 90,
                             weeklySetsLow: 12, weeklySetsHigh: 20)
        case .weightLoss:
            return FocusBand(mainRepsLow: 8, mainRepsHigh: 15,
                             accessoryRepsLow: 10, accessoryRepsHigh: 15,
                             mainRestSeconds: 90, accessoryRestSeconds: 60,
                             weeklySetsLow: 10, weeklySetsHigh: 14)
        case .conditioning:
            return FocusBand(mainRepsLow: 12, mainRepsHigh: 20,
                             accessoryRepsLow: 12, accessoryRepsHigh: 20,
                             mainRestSeconds: 60, accessoryRestSeconds: 45,
                             weeklySetsLow: 8, weeklySetsHigh: 12)
        }
    }

    /// Beginner override (Schoenfeld 2018: beginners grow on 5-9 weekly
    /// sets): 6-10 regardless of focus.
    static let beginnerWeeklySets = (low: 6, high: 10)

    // MARK: Progression (by experience; progression-models research)

    /// Novice linear progression per-session increments (practice-based):
    /// upper ~+2.5 lb, lower ~+5 lb — matches SetProgression's percent
    /// steps at typical novice loads. Stall = 2 sessions; response −10%.
    static let noviceStallSessions = 2
    static let noviceStallDeloadPercent = 10.0

    /// Intermediate double progression: 3-5-rep windows, +2.5-5% on
    /// topping out — already encoded in SetProgression; window widths
    /// come from the focus bands above.

    /// Advanced RIR targets (weak confidence — used for prescription COPY
    /// and RPE hints, not hard gates): accumulation 2-4, intensification
    /// 0-2.
    static let advancedAccumulationRIR = 2...4
    static let advancedIntensificationRIR = 0...2

    // MARK: Wave shape (deload + peak; taper research)

    /// Deload at the ¾ mark for 8/12-week plans (proactive 4-6-week
    /// cadence, offered not forced): volume −50%, intensity held.
    static let deloadVolumeMultiplier = 0.5
    static let deloadIntensityMultiplier = 0.95

    /// 1RM peaking taper (moderate confidence — Pritchard-line research):
    /// 10-14 days, volume −50%, intensity maintained 90-100%.
    static let taperVolumeMultiplier = 0.5

    // MARK: Split ladder (frequency law: ≥2×/muscle/week wherever days allow)

    enum DayKind: String {
        case fullBody, upper, lower, push, pull, legs
    }

    static func split(daysPerWeek: Int, focus: Focus) -> [DayKind] {
        let days = max(1, min(7, daysPerWeek))
        // Weight Loss and Conditioning are FULL-BODY programs at any day
        // count (the focus table's own prescription: density circuits and
        // maintenance-floor lifting, not bodypart splits).
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
