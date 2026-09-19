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
// called, the recap never ran, the week never counted the day, and the row
// sat `in_progress` until it aged out. That has been true for CREW Freestyle
// since Phase B1; Phase C1 is what made every ad-hoc solo workout a
// `.freestyle` session and therefore made it everybody's bug.
//
// NOT THE STREAK, and this was claimed wrongly once (fix round 2). An ad-hoc
// workout has never moved anyone's streak and still does not:
// `streak_on_session_state_change` returns at
// `IF NEW.scheduled_for IS NULL` (`20260719000006_streaks.sql:316-319`), by
// design, and the old `WorkoutSessionView.endSession()` called the SAME
// `SessionRepository.complete()`, so Phase C changes nothing about it. What
// finishing now buys that it did not: the recap, the pump post, the
// HealthKit export, a `completed` row — and the WEEK, which is a client-side
// count of distinct training days over completed history
// (`WeeklyGoalProgressMath.distinctTrainingDays`), not a trigger.
//
// LEAVING AND ENDING BELONG TO THE BODY, NOT TO A STYLE PAGE. A style decides
// how a session MOVES — a rotation, a shared clock, a self-paced rail — and
// none of those is a reason to be able or unable to stop. So the question
// "where does this style's end control live" is answered here, once,
// exhaustively, instead of by whichever page happened to be written with a
// foot.
//
// IT IS KEYED ON THE PAGE, NOT ON THE STYLE (fix round 2 / N10). The first
// version of this type asked `mount(for: SessionStyle)`, and its `.rounds`
// arm claimed "`myTurnFixedPage`, `roundWaitPage` and `spotterPage` all carry
// `turnHeaderRail`'s dismiss glyph". They do not. `roundWaitPage` builds
// `RoundWaitView` and `spotterPage` builds `SpotterView`, neither of which
// draws a header rail, and `bottomChrome` renders `turnChrome` only when
// `!showsCrewPage` — so the crew pages carry no chrome either. A crew lifter
// whose turn-holder walked out sat on the round wait with no leave and no
// end. The router shows PAGES; the law has to be about the thing the router
// shows, or it is true of a category and false of what is on screen.
//
// WHY TWO EXHAUSTIVE SWITCHES ARE THE STRUCTURE. `pages(for:)` is exhaustive
// over `SessionStyle`, so a fourth style cannot be added without naming the
// pages it can show; `mount(for:)` is exhaustive over `Page`, so a sixth page
// cannot be added without naming where its end control lives. Either way the
// author's only way past the compiler is to name something, and if what they
// name is `.none`, `SessionEndAffordanceTests` fails. A comment could not do
// that, and neither could a test over styles alone — which is exactly the
// hole the first version left.
enum SessionEndAffordance {

    /// EVERY PAGE `SessionLiveView.arenaBase`'s switch can show. Five arms
    /// there, five cases here, and the test asserts the two agree.
    enum Page: String, CaseIterable {
        /// `myTurnFixedPage` — `.rounds`, my turn (and the fallback).
        case roundsMyTurn
        /// `roundWaitPage` — `.rounds`, somebody else's turn, I still owe a
        /// set this round.
        case roundsRoundWait
        /// `spotterPage` — `.rounds`, somebody else's turn, my prescription
        /// for this round is done.
        case roundsSpotter
        /// `freestylePage`.
        case freestyleRail
        /// `togetherPage`.
        case togetherClock
    }

    /// WHERE the control that raises the end confirmation lives, for one
    /// page.
    enum Mount: Equatable {
        /// `turnHeaderRail`'s dismiss glyph — the my-turn page carries its
        /// own header rail.
        case headerRail
        /// A `RoundDoor` at the end of the page's own content or foot. The
        /// page takes an `onEnd` closure and mounts it itself, because these
        /// pages draw no header rail and `bottomChrome` does not reach them.
        case pageFoot
        /// NOTHING — which is what Freestyle, the round wait and spotter mode
        /// all had, and what this type exists to make a test failure rather
        /// than a shipped dead end.
        case none
    }

    /// Exhaustive over `Page`.
    static func mount(for page: Page) -> Mount {
        switch page {
        case .roundsMyTurn:
            // `turnHeaderRail:1035` — the one shipped setter of
            // `showEndConfirmation` that is not a page's own door.
            return .headerRail
        case .roundsRoundWait:
            // `RoundWaitView(onEnd:)` — added in fix round 2.
            return .pageFoot
        case .roundsSpotter:
            // `SpotterView(onEnd:)` — added in fix round 2, beside CHEER and
            // deliberately not instead of it.
            return .pageFoot
        case .freestyleRail:
            // `FreestyleRailView(onEnd:)` — added in fix round 1.
            return .pageFoot
        case .togetherClock:
            // `TogetherClockView(onEnd:)` — shipped before either round.
            return .pageFoot
        }
    }

    /// Exhaustive over `SessionStyle`: which pages a session of this style
    /// can put on screen. Adding a style breaks this switch at compile time.
    static func pages(for style: SessionStyle) -> [Page] {
        switch style {
        case .rounds:    return [.roundsMyTurn, .roundsRoundWait, .roundsSpotter]
        case .freestyle: return [.freestyleRail]
        case .together:  return [.togetherClock]
        }
    }

    /// True when this page must mount its own `RoundDoor`.
    ///
    /// ITS READERS, NAMED HONESTLY (fix round 2 / N9 — the first version
    /// claimed "both page call sites" while one of them read nothing).
    /// THREE production call sites read it, each turning it into an OPTIONAL
    /// `onEnd`, so deleting an arm makes that page's door vanish:
    /// `SessionLiveView.freestyleScreen`, `.roundWaitPage` and
    /// `.spotterPage`, all through `endAction(for:)`.
    ///
    /// `togetherPage` is the ONE that does not, and that is deliberate rather
    /// than an oversight: `TogetherClockView.onEnd` is a non-optional
    /// `() -> Void = {}` and its door renders unconditionally, so it is
    /// already in the catalog's Together frames. Making it conditional would
    /// change what those frames render (constraint 14). Its arm is therefore
    /// asserted by the test and by nothing else, and this comment is the
    /// place that says so.
    static func pageMountsItsOwnEnd(_ page: Page) -> Bool {
        mount(for: page) == .pageFoot
    }
}

// MARK: - The end confirmation's words

/// WHAT THE DIALOG SAYS, BY WHO IS IN THE SESSION (ruling R-C-7).
///
/// A lifter alone in a gym is not "leaving a session" and is not "ending it
/// for everyone" — both sentences describe other people, and there are none.
/// They are finishing their workout. The ACT is identical either way
/// (`endSession()` → `complete()` → the recap, the week, the pump post — not
/// the streak, which no ad-hoc session has ever moved; see the header); only
/// the words change, which is design rule 9's whole point: a button says
/// exactly what happens.
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
