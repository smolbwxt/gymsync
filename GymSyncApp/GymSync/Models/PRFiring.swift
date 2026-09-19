import Foundation

// MARK: - PRFiring
//
// WHEN the app celebrates a record — a different question from whether the set
// IS one, which is `PersonalRecordMath.isPR`'s and only its business.
//
// Docket row 7 (`2026-09-03-field-report-docket.md`, P1) and the logic half of
// the owner's "not what we designed". Two rules, neither of which was
// implemented anywhere before this type:
//
//   (a) THE FIRST-EVER LOG OF A LIFT IS A BASELINE, NOT A RECORD. With no
//       prior qualifying history the comparison basis is empty, every
//       `bestWeight` answers 0, and "heavier than nothing" is true of any
//       weight — so the very first set of a lift you have never logged
//       celebrated, every time. The set is still STORED and still wears its
//       `PR` tag on the recap: the docket asks for no CELEBRATION, not for
//       the fact to be erased.
//
//   (b) THE CELEBRATION WAITS FOR THE LAST SET — IT DEFERS, IT IS NEVER LOST.
//       The overlay fired from inside the log path on EVERY set, so a record
//       on set 1 of 4 took the screen over and the lifter dismissed it three
//       more times on the way down. It now waits until every prescribed set
//       of that exercise is logged. Waiting is not suppressing (ruling
//       R-OD-1): the record is HELD as a `Pending` payload and celebrated at
//       completion. The first shape of this rule answered a plain `Bool` per
//       set, which lost the moment outright on the commonest pattern of all —
//       straight sets. 3 × 5, prior best 200, 205 on all three: set 1 is the
//       record, sets 2 and 3 are judged against a basis that now contains
//       205, so nothing was ever a record again and nothing ever fired.
//
// THE HOLD, IN ONE PLACE. `step(record:context:held:)` is the whole rule: it
// folds this set's record (if it is one) into whatever is already held for
// that exercise, and answers with what remains held and what to celebrate
// right now. A later record in the same exercise keeps the EARLIEST `prior` —
// the best this lifter had BEFORE the exercise began, so "N OVER YOUR BEST"
// reads against that and not against their own set two minutes ago — and the
// BEST new value. One celebration per exercise, at its end.
//
// LEAVING THE EXERCISE FLUSHES (ruling R-OD-2). If the lifter moves on with a
// payload still held — sets skipped, the exercise swapped, a superset handing
// the bar to its partner — the celebration fires at that moment, once, and
// the store clears. IF THE SESSION ENDS OR THE APP DIES WITH ONE HELD,
// NOTHING FIRES: the record row was written when the set was logged, so the
// recap's `PR` tag is the record of it. A resurrected party three days later
// is worse than a quiet one, and there is no store to resurrect it from —
// the held payload is session-local memory by design.
//
// Pure, value-in, and deliberately unaware of both view bodies: the group
// (`SessionLiveView.logSetAndAdvance`) and solo (`WorkoutSessionView.log`)
// paths each build a `Context` from what they already hold and ask the same
// question, so the two can never drift into two different answers again.
enum PRFiring {

    /// What the caller knows about the set it has just written.
    struct Context: Equatable {
        /// No prior qualifying history for this exercise, this lifter — the
        /// basis the record was judged against is empty, so there was nothing
        /// to beat. Rule (a).
        let basisIsEmpty: Bool
        /// SETS OF THIS EXERCISE LOGGED BY THIS LIFTER IN THIS SESSION,
        /// COUNTING THE SET JUST LOGGED (ruling R-OD-3). One meaning, and
        /// both bodies pass it: the group from `mySetCount(for:) + 1`, solo
        /// from its own count of this session's logs for this exercise.
        /// Solo's `currentSetIndex` is NOT this number — it is per routine
        /// SLOT and restarts when a routine names the same lift twice — and
        /// it is deliberately not what solo passes.
        let setsLogged: Int
        /// The prescription's set count, from the EFFECTIVE routine row — an
        /// accepted scale-down of 4 × 5 → 3 × 5 means the third set is the
        /// last one, and the celebration must agree with the number the
        /// screen printed. `nil` means unprescribed.
        let targetSets: Int?
    }

    /// A record waiting for its exercise to finish — exactly the four values
    /// the celebration overlay draws, so a held moment can be fired later
    /// without re-reading anything.
    ///
    /// THE REP-PR FORM rides here too, unchanged from every other display
    /// site: `weight == 0` means the REPS are the record and `priorBest`
    /// carries the prior REP count.
    struct Pending: Equatable {
        let exerciseName: String
        let weight: Decimal
        let reps: Int
        let priorBest: Decimal

        /// The bodyweight form (owner item 6) — reps are the record.
        var isRepRecord: Bool { weight == 0 }
    }

    /// What one logged set does to the held payload.
    struct Step: Equatable {
        /// What remains held for this exercise afterwards — `nil` clears it.
        let held: Pending?
        /// The one moment to celebrate right now, if any.
        let celebrate: Pending?
    }

    /// Is the prescription for this exercise satisfied as of this set?
    ///
    /// An unprescribed exercise (`targetSets == nil` — freestyle, a lift
    /// picked mid-session, a Together/ad-hoc session with no routine row) has
    /// no "all sets" to wait for, and withholding the moment forever would
    /// delete it, so every set of one is "complete" and celebrates at once.
    /// `>=`, never `==`: a lifter who adds a fifth set to a four-set
    /// prescription is past the end of it, not short of it.
    static func isComplete(_ context: Context) -> Bool {
        guard let targetSets = context.targetSets else { return true }
        return context.setsLogged >= targetSets
    }

    /// The rule, whole and pure.
    ///
    /// - Parameters:
    ///   - record: this set's record, or `nil` when the set is not one.
    ///   - context: what the caller knows about the set just written.
    ///   - held: the payload already held for THIS exercise, if any.
    ///
    /// Rule (a) is applied here rather than at either call site: a record
    /// against an empty basis is a baseline and is dropped, never held.
    static func step(record: Pending?, context: Context, held: Pending?) -> Step {
        // Rule (a): nothing to beat is not a moment to keep.
        let accepted = context.basisIsEmpty ? nil : record
        let carried = accepted.map { merged($0, into: held) } ?? held
        guard isComplete(context) else { return Step(held: carried, celebrate: nil) }
        // Rule (b)'s other half: at completion the held payload fires ONCE
        // and the store clears. `carried` is `nil` when nothing was ever a
        // record, which is the ordinary set and celebrates nothing.
        return Step(held: nil, celebrate: carried)
    }

    /// Fold a new record into the one already held for the same exercise.
    ///
    /// THE EARLIEST `priorBest` WINS and the BEST new value wins. The prior
    /// must stay the best this lifter had before the exercise began, or the
    /// second record of an exercise would read "5 OVER YOUR BEST" against
    /// their own first set of the same session — technically true, and not
    /// the sentence the screen is making.
    ///
    /// "Best" is the heavier set, and the longer set when the weight ties —
    /// which is also what decides between two bodyweight rep records, since
    /// those both carry `weight == 0`.
    ///
    /// A WEIGHTED RECORD AND A REP RECORD IN ONE EXERCISE are two different
    /// sentences with two different `priorBest` meanings (a weight and a rep
    /// count), so they are never merged: the later form replaces the earlier
    /// one and travels with its own prior. A lifter who adds a dumbbell to a
    /// lift mid-exercise is rare enough that the honest answer is the newer
    /// one, and a merged pair would print a rep count as a weight.
    static func merged(_ new: Pending, into held: Pending?) -> Pending {
        guard let held else { return new }
        guard held.isRepRecord == new.isRepRecord else { return new }
        let best = (new.weight, new.reps) > (held.weight, held.reps) ? new : held
        return Pending(exerciseName: best.exerciseName,
                       weight: best.weight,
                       reps: best.reps,
                       priorBest: held.priorBest)
    }
}
