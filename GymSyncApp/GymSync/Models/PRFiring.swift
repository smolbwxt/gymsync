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
//   (b) THE CELEBRATION WAITS FOR THE LAST SET. The overlay fired from inside
//       the log path on EVERY set, so a record on set 1 of 4 took the screen
//       over and the lifter dismissed it three more times on the way down.
//       It now waits until every prescribed set of that exercise is logged.
//
// Pure, value-in, and deliberately unaware of both view bodies: the group
// (`SessionLiveView.logSetAndAdvance`) and solo (`WorkoutSessionView.log`)
// paths each build a `Context` from what they already hold and ask the same
// question, so the two can never drift into two different answers again.
enum PRFiring {

    /// What the caller knows about the set it has just written.
    struct Context {
        /// No prior qualifying history for this exercise, this lifter — the
        /// basis the record was judged against is empty, so there was nothing
        /// to beat. Rule (a).
        let basisIsEmpty: Bool
        /// Sets of this exercise this lifter has logged, INCLUDING the one
        /// just written. Both call sites already hold it as the new row's
        /// `setIndex`.
        let setsLogged: Int
        /// The prescription's set count, from the EFFECTIVE routine row — an
        /// accepted scale-down of 4 × 5 → 3 × 5 means the third set is the
        /// last one, and the celebration must agree with the number the
        /// screen printed. `nil` means unprescribed.
        let targetSets: Int?
    }

    /// Docket row 7: (a) the first-ever log of an exercise is a baseline, not
    /// a record; (b) the celebration waits until every set of that exercise
    /// is done.
    ///
    /// An unprescribed exercise (`targetSets == nil` — freestyle, or a lift
    /// picked mid-session) has no "all sets" to wait for, and withholding the
    /// moment forever would delete it, so it celebrates on the record itself.
    static func shouldCelebrate(isRecord: Bool, context: Context) -> Bool {
        guard isRecord else { return false }
        guard !context.basisIsEmpty else { return false }
        guard let targetSets = context.targetSets else { return true }
        return context.setsLogged >= targetSets
    }
}
