import Foundation

// MARK: - MuscleGroup
//
// Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
// -goal-design.md §B ("The weekly goal"), owner answer 1: "major groups,
// full credit primary, partial credit secondary, capped".
//
// THE VOCABULARY THIS ROLLS UP. The exercise catalog's muscle columns
// (`exercises.primary_muscle`, `exercises.secondary_muscles`) carry 21
// distinct lowercase strings across all 1,117 seeded rows —
// `20260709000003_seed_exercises.sql` (30), `20260813000001_import_free
// _exercise_db.sql` (861), `20260814000006_machine_catalog.sql` (170),
// `20260814000007_hammer_strength_catalog.sql` (47),
// `20260822000005_brand_exercises.sql` (9):
//
//   abductors adductors back biceps calves chest core forearms front_delts
//   glutes hamstrings hip_flexors lats lower_back neck quads rear_delts
//   shoulders traps triceps upper_chest
//
// plus `obliques`, which reaches the table only through the runtime-seeded
// packs (`scripts/data/exercise_expansion_2026_08.json`, applied by
// `scripts/seed_exercise_expansion.js`). Twenty-two strings; twenty-one of
// them map, `neck` maps to nothing.
//
// NOT a replacement for `ProgramGenerator.weeklyMuscleSets`
// (`ProgramGenerator.swift:1871-1887`). That function credits 1.0 primary
// and 0.5 per secondary MUSCLE STRING and is what the generator's volume
// bands are tuned against; changing it would move every generated program.
// This type answers a different question — what does one set give the SIX
// GROUPS a person reads on Home — and the two deliberately coexist.

/// The owner's six major groups. The strip renders these names; the
/// catalog's 22 muscle strings roll up into them.
enum MuscleGroup: String, CaseIterable, Sendable {
    case chest, back, shoulders, legs, arms, core
}

extension MuscleGroup {

    /// The rollup table. `neck` is deliberately absent: it is the one
    /// catalog muscle that belongs to none of the six, and crediting it to
    /// `shoulders` would put neck curls in a shoulder target no one set.
    private static let byMuscle: [String: MuscleGroup] = [
        "chest": .chest,
        "upper_chest": .chest,

        "back": .back,
        "lats": .back,
        "lower_back": .back,
        "traps": .back,

        "shoulders": .shoulders,
        "front_delts": .shoulders,
        "rear_delts": .shoulders,

        "quads": .legs,
        "hamstrings": .legs,
        "glutes": .legs,
        "calves": .legs,
        "adductors": .legs,
        "abductors": .legs,
        "hip_flexors": .legs,

        "biceps": .arms,
        "triceps": .arms,
        "forearms": .arms,

        "core": .core,
        "obliques": .core,
    ]

    /// The group a catalog muscle string belongs to, or nil when it belongs
    /// to none. Matching is lowercased here rather than at the call site, so
    /// a row seeded with `Quads` credits the same as one seeded with
    /// `quads` — the packs are hand-authored JSON and the column has no
    /// case constraint.
    static func group(_ muscle: String) -> MuscleGroup? {
        byMuscle[muscle.lowercased()]
    }

    /// What ONE set of an exercise gives each group.
    ///
    /// Owner answer 1, in three moves:
    ///
    /// 1. the primary's group gets **1.0**;
    /// 2. the secondaries roll up to groups FIRST, then de-duplicate, then
    ///    drop the primary's own group. Back Squat's
    ///    `['glutes','hamstrings','core']` is `{legs, core}` after the
    ///    rollup and `{core}` after dropping `legs` — three strings, one
    ///    group, credited once. Doing it in the other order (credit each
    ///    string, then roll up) would pay `legs` twice for the same set;
    /// 3. every surviving secondary group gets `min(0.5, 1/|S|)`, so the
    ///    TOTAL secondary credit for one set never exceeds 1.0 — the
    ///    owner's cap, expressed as a per-group weight rather than a
    ///    post-hoc clamp so the split is deterministic and independent of
    ///    the order the secondaries happen to be stored in.
    ///    `|S|=1 → 0.5` · `|S|=2 → 0.5, 0.5` · `|S|=3 → 0.333…×3` ·
    ///    `|S|=4 → 0.25×4`.
    ///
    /// An unmapped string on either side contributes nothing and is not an
    /// error: `neck` is real data, and a pack that ships a muscle this app
    /// has never heard of must cost the lifter a credit, not a crash.
    static func credit(primary: String, secondaries: [String]) -> [MuscleGroup: Double] {
        var credit: [MuscleGroup: Double] = [:]

        let primaryGroup = group(primary)
        if let primaryGroup = primaryGroup {
            credit[primaryGroup] = 1.0
        }

        var secondaryGroups = Set(secondaries.compactMap { group($0) })
        if let primaryGroup = primaryGroup {
            secondaryGroups.remove(primaryGroup)
        }
        guard !secondaryGroups.isEmpty else { return credit }

        let weight = min(0.5, 1.0 / Double(secondaryGroups.count))
        for secondaryGroup in secondaryGroups {
            credit[secondaryGroup] = weight
        }
        return credit
    }
}
