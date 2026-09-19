import Foundation

// MARK: - SessionEndAffordance
//
// EVERY STYLE PAGE THE ROUTER CAN SHOW HAS A WAY TO END THE SESSION
// (ruling R-C-7, fix round 1 / B1).
//
// THE BUG THIS EXISTS TO MAKE UNREPEATABLE. `showEndConfirmation` had exactly
// two setters — `turnHeaderRail`'s ✕, which only `myTurnFixedPage` mounts,
// and `togetherPage`'s `onEnd`. `freestylePage` mounted neither, so a
// Freestyle session could not be finished at all: `complete()` was never
// called, the recap never ran, no streak or week credit was written, and the
// row sat `in_progress` until it aged out. That has been true for CREW
// Freestyle since Phase B1; Phase C1 is what made every ad-hoc solo workout
// a `.freestyle` session and therefore made it everybody's bug.
//
// LEAVING AND ENDING BELONG TO THE BODY, NOT TO A STYLE PAGE. A style decides
// how a session MOVES — a rotation, a shared clock, a self-paced rail — and
// none of those is a reason to be able or unable to stop. So the question
// "where does this style's end control live" is answered here, once,
// exhaustively, instead of by whichever page happened to be written with a
// foot.
//
// WHY AN EXHAUSTIVE SWITCH IS THE STRUCTURE. `SessionStyle` is a closed enum
// backed by the column's own CHECK constraint. A fourth style cannot be added
// without the compiler failing this switch, and the author's only way past it
// is to name a mount — and if they name `.none`, `SessionEndAffordanceTests`
// fails. A comment could not do that; a test over `allCases` alone could not
// either, because it would pass for a style whose page silently never mounts
// what it was assigned.
enum SessionEndAffordance {

    /// WHERE the control that raises the end confirmation lives, for one
    /// style's page.
    enum Mount: Equatable {
        /// `turnHeaderRail`'s ✕ — the my-turn page carries its own header.
        case headerRail
        /// A `RoundDoor` at the end of the page's own content or foot. The
        /// page takes an `onEnd` closure and mounts it itself, because these
        /// pages draw no header rail.
        case pageFoot
        /// NOTHING — which is what Freestyle had, and what this type exists
        /// to make a test failure rather than a shipped dead end.
        case none
    }

    /// Exhaustive over `SessionStyle`. Adding a case to that enum breaks
    /// this switch at compile time.
    static func mount(for style: SessionStyle) -> Mount {
        switch style {
        case .rounds:
            // `myTurnFixedPage`, `roundWaitPage` and `spotterPage` all carry
            // `turnHeaderRail`'s ✕ — and the two crew pages are only ever
            // reachable while somebody else holds the turn, so the lifter is
            // never further than one turn from the rail.
            return .headerRail
        case .freestyle:
            // `FreestyleRailView(onEnd:)` — added in fix round 1.
            return .pageFoot
        case .together:
            // `TogetherClockView(onEnd:)` — shipped.
            return .pageFoot
        }
    }

    /// True when this style's page must mount its own `RoundDoor`. Read by
    /// `SessionLiveView` at both page call sites, so the law has a caller and
    /// deleting an arm changes what renders.
    static func pageMountsItsOwnEnd(_ style: SessionStyle) -> Bool {
        mount(for: style) == .pageFoot
    }
}

// MARK: - The end confirmation's words

/// WHAT THE DIALOG SAYS, BY WHO IS IN THE SESSION (ruling R-C-7).
///
/// A lifter alone in a gym is not "leaving a session" and is not "ending it
/// for everyone" — both sentences describe other people, and there are none.
/// They are finishing their workout. The ACT is identical either way
/// (`endSession()` → `complete()` → the recap, the streak, the week, the pump
/// post); only the words change, which is design rule 9's whole point: a
/// button says exactly what happens.
///
/// Pure and here rather than inline in the dialog so the copy is asserted
/// rather than eyeballed, and so the solo and crew branches cannot drift.
///
/// DISCARD / ABANDON IS NOT HERE, ON PURPOSE. There is no "throw this workout
/// away" anywhere in the app today — `sessions.state` admits `abandoned` but
/// no repository function writes it — and inventing one behind a confirmation
/// dialog is a product decision, not a bug fix. It is C2's.
enum SessionEndCopy {

    struct Dialog: Equatable {
        let title: String
        let message: String
        /// The one action, for a lifter on their own. Nil for a crew, whose
        /// two actions mean different things and keep their shipped words.
        let soloPrimary: String?
    }

    static func dialog(isSolo: Bool, isLastPresent: Bool) -> Dialog {
        if isSolo {
            return Dialog(
                title: "Finish this workout?",
                message: "Everything you logged is saved. You'll see your recap, and the session closes.",
                soloPrimary: "Finish workout")
        }
        return Dialog(
            title: "Leave the session?",
            message: isLastPresent
                ? "You're the last one lifting — leaving completes the session."
                : "Leaving removes you from the rotation; the crew keeps lifting.",
            soloPrimary: nil)
    }
}
