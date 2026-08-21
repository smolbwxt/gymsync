import Foundation

// MARK: - Entitlements
//
// The single flip point for the paywall (small-things pass 2026-08-21).
// TRUE until StoreKit lands: personas wear their PRO badge but stay
// usable, so early users build the habit the subscription later
// protects. Every gate in the app asks HERE and nowhere else — flipping
// this to a real entitlement check is the entire paywall wiring on the
// feature side.
enum Entitlements {
    static var hasPro: Bool { true }
}

// MARK: - CoachObservations
//
// The first-contact handshake (concept 2026-08-20: "demonstrate before
// you interrogate"): one computed observation from the athlete's
// EXISTING log, shown the first time they open Coach. A personal trainer
// doesn't hand you a clipboard — they watch you move and say one smart
// thing. Pure and tested; nil for true blank slates.
enum CoachObservations {

    private static let pushMuscles: Set<String> = ["chest", "shoulders", "triceps"]
    private static let pullMuscles: Set<String> = ["back", "lats", "biceps"]

    /// - Parameters:
    ///   - logs: recent set logs, all exercises (e.g. 28 days).
    ///   - muscleByExerciseID: exercise ID -> lowercased primary muscle.
    static func firstContact(logs: [SetLog],
                             muscleByExerciseID: [UUID: String]) -> String? {
        let working = logs.filter { !$0.isPenalty && $0.completedReps != nil }
        let sessions = Set(working.map(\.sessionID)).count
        guard sessions >= 3 else { return nil }

        var push = 0, pull = 0
        for log in working {
            guard let muscle = muscleByExerciseID[log.exerciseID] else { continue }
            if pushMuscles.contains(muscle) { push += 1 }
            if pullMuscles.contains(muscle) { pull += 1 }
        }
        if push >= 8 || pull >= 8 {
            let ratio = Double(max(push, 1)) / Double(max(pull, 1))
            if ratio >= 1.6 {
                return "I've been reading your log — \(sessions) sessions this month, and your pressing volume runs well ahead of your pulling (\(push) sets to \(pull)). Want me to build you something balanced?"
            }
            if ratio <= 0.625 {
                return "I've been reading your log — \(sessions) sessions this month, and your pulling volume runs well ahead of your pressing (\(pull) sets to \(push)). Want me to build you something balanced?"
            }
        }
        return "I've been reading your log — \(sessions) sessions this month and a balanced push/pull ledger. The consistency is there; let's aim it at something."
    }
}
