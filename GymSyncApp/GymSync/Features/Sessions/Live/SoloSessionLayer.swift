import SwiftUI

// MARK: - SoloSessionLayer
//
// THE SOLO SHAPE OF THE ONE BODY (Phase C1 S4, decision 6 and brief item 7).
//
// Three things live here and they are deliberately not the same law:
//
//   * `SoloSessionShape.crew(…)` and `hidesCrewFurniture(…)` — the gate the
//     one body reads in five places so that a lifter alone in a gym never
//     sees a talk dock, a presence count or a rotation. It reads the SESSION
//     first and the roster second (fix round 2 corrected this note, which
//     still said "the ROSTER and nothing else" after `crew(…)` had stopped
//     being true of that): an ad-hoc row is solo before any fetch exists, a
//     LOADED roster decides everything else, and an absent roster is
//     `.unknown`, which keeps the crew's shipped behaviour. A SCHEDULED solo
//     session still gets the solo shape the moment its roster of one lands —
//     a party of one has nobody to talk to whether or not a calendar said so.
//   * `SoloSessionShape.isSoloByConstruction(groupID:roomCode:scheduledFor:)`
//     — decided from the session row alone, because the screens that ask it
//     hold no roster. It seeds the furniture law above, and it is what
//     `SessionPresentation` below turns into cover-or-push.
//   * `SoloSessionCover` and `SessionPresentation` — how a session is opened,
//     stated once so that a second screen cannot quietly open one another way
//     (which is exactly what the calendar page did).
//
// WHY A SEPARATE FILE AND NOT FOUR INLINE CONDITIONS. Constraint 22: the one
// body's `body` is at its type-checker budget, so every modifier this task
// adds is an extracted layer. And four inline `participants.count <= 1`
// tests are four places for the law to drift — the review of a later phase
// would have to find them all to know what a solo lifter sees.

enum SoloSessionShape {

    /// WHO IS IN THIS SESSION, as far as anything can currently tell.
    ///
    /// THREE VALUES, BECAUSE THERE ARE THREE ANSWERS (fix round 1 / N1). The
    /// two-valued law read `participants.count <= 1`, and `participants` is
    /// `@State … = []` filled only by `reload()` — so it answered SOLO for
    /// every session, crew included, on the render pass before the fetch
    /// landed, and went on answering solo for as long as a reload kept
    /// failing. A crew's chat door, presence count, mic rail, voice notices
    /// and reaction strip popped in rather than being there; worse, on a bad
    /// connection `joinVoiceIfEligible` declined to open the room for the
    /// WHOLE CREW until a reload finally succeeded. An absent roster is not
    /// evidence of an empty one.
    enum Crew: Equatable {
        /// Proved: solo by construction, or a roster that has loaded and
        /// holds one.
        case solo
        /// Proved: a roster that has loaded and holds more than one.
        case crew
        /// NOT KNOWN YET — and the crew's behaviour is what an unknown gets,
        /// because that is the shipped behaviour and the honest default: a
        /// crew shown one frame of solo chrome is a flicker, while a crew
        /// silently denied its voice dock is a broken session.
        case unknown
    }

    /// The one derivation. `loadedParticipantCount` is nil while no roster
    /// has arrived — an EMPTY array is exactly that, since a real session
    /// always holds at least the viewer's own row.
    static func crew(groupID: UUID?,
                     roomCode: String?,
                     scheduledFor: Date?,
                     loadedParticipantCount: Int?) -> Crew {
        // Construction beats the roster, and it is available first: the
        // cover is raised the instant `startSolo` returns, long before any
        // participants fetch, and this is the answer for every session that
        // fetch could ever produce.
        if isSoloByConstruction(groupID: groupID, roomCode: roomCode,
                                scheduledFor: scheduledFor) {
            return .solo
        }
        guard let count = loadedParticipantCount else { return .unknown }
        return count <= 1 ? .solo : .crew
    }

    /// HIDE THE CREW'S FURNITURE. Only for a PROVED party of one.
    ///
    /// What the one body ALREADY hides for a party of one, verified by
    /// reading rather than assumed, so this gate covers only the remainder:
    ///   * the burpee-debt strip — `burpeesRemaining > 0`, and
    ///     `evaluate_lateness` writes a debt only against a scheduled start;
    ///   * the held-lifter screen and the crew-swap consent card — each
    ///     needs a second participant in its own predicate;
    ///   * `roundWaitPage` / `spotterPage`, and with them the whole
    ///     `TurnStrip` — `showsCrewPage` requires `style == .rounds`, a
    ///     `currentTurnUserID` AND `!isMyTurn`, and a roster of one is
    ///     always its own turn. `TurnStrip` has exactly one production call
    ///     site (`SpotterView.swift:71`), which is behind that gate, so a
    ///     strip of one cannot render and needed no gate of its own;
    ///   * `logControlIsMine` — unconditional for `.freestyle`, so the log
    ///     card is always the solo lifter's.
    ///
    /// What it DOES gate, all of it on the freestyle rail's shared foot and
    /// the my-turn header: the mic rail, the voice notices, the reaction
    /// strip, the chat and mixer doors, the roster count — and
    /// `joinVoiceIfEligible`, which is not furniture at all but a live
    /// connection to a voice room with nobody in it.
    ///
    /// `.unknown` KEEPS THE CREW'S BEHAVIOUR (fix round 1 / N1) — see `Crew`.
    static func hidesCrewFurniture(_ crew: Crew) -> Bool {
        crew == .solo
    }

    /// The whole derivation in one call, which is what the view reads — so
    /// the tests exercise the same function the gates do rather than a
    /// predicate nothing calls (fix round 1 / N7).
    static func hidesCrewFurniture(groupID: UUID?,
                                   roomCode: String?,
                                   scheduledFor: Date?,
                                   loadedParticipantCount: Int?) -> Bool {
        hidesCrewFurniture(crew(groupID: groupID, roomCode: roomCode,
                                scheduledFor: scheduledFor,
                                loadedParticipantCount: loadedParticipantCount))
    }

    /// SOLO BY CONSTRUCTION — decided from the SESSION ROW ALONE, with no
    /// roster at all.
    ///
    /// THE ROSTER IS NOT AVAILABLE WHERE THIS IS ASKED. Home holds
    /// `WorkoutSession` rows and no participants; a cover is raised the
    /// instant `startSolo` returns; the live body's `participants` is empty
    /// until `reload()` lands. A law that needs a count cannot answer at any
    /// of those moments, and `isAdHocSolo(participantCount:…)` — which this
    /// replaces — was being handed a literal `1` at all four covers, so its
    /// roster argument was inert and the honest question was always this one.
    ///
    /// THE TRIPLE NIL IS EXACTLY `startSolo`'s SHAPE and nothing else's:
    /// `ScheduleSessionView` sets `scheduled_for` on every mode including
    /// `.solo` (`:864-871`), `.code` carries a room code, `.group` carries a
    /// group, and the trainer booking is scheduled. So a row with no group,
    /// no code and no time is an ad-hoc workout somebody tapped START on.
    ///
    /// WHAT IT DELIBERATELY DOES NOT CLAIM: that every solo session answers
    /// true. A SCHEDULED solo session is `false` here, because at the session
    /// row a scheduled solo session and a scheduled `.friends` session are
    /// byte-identical (`ScheduleSessionView:781-784`: both leave `group_id`
    /// and `room_code` nil). Only the roster separates them, and where the
    /// roster is known, `crew(…)` below is what asks.
    static func isSoloByConstruction(groupID: UUID?,
                                     roomCode: String?,
                                     scheduledFor: Date?) -> Bool {
        groupID == nil && roomCode == nil && scheduledFor == nil
    }
}

// MARK: - The one way a solo session is presented

/// A SOLO SESSION IS ALWAYS THE COVER, FROM EVERY ROUTE (fix round 1 / B2).
///
/// THE DEAD END THIS CLOSES. Removing Home's solo exclusion (R-C-1) made a
/// live ad-hoc row reachable from the one button — which PUSHES
/// `SessionEntryView`. `soloMinimiseOverlay` was mounted at the covers only,
/// `arenaBase` sets `.navigationBarBackButtonHidden(true)` and the body sets
/// `.gsHidesDock()`, so that push had no MINIMISE, no back button and no tab
/// bar. Combined with B1 there was no control on the screen that left it: the
/// lifter who minimised during the warm-up and came back through Home's
/// button was stranded until they force-quit. That is the exact failure mode
/// decision 6 exists to end, reintroduced through a different door.
///
/// So the presentation is a property of the SESSION, not of the route that
/// found it. Every route that can land on an ad-hoc session — the four entry
/// points, Home's one button, the live pill's deep link, a relaunch — builds
/// this one view, and the MINIMISE decision is made in exactly one place.
struct SoloSessionCover: View {
    let session: WorkoutSession

    var body: some View {
        SessionEntryView(session: session)
            .soloMinimiseOverlay(SoloSessionShape.isSoloByConstruction(
                groupID: session.groupID,
                roomCode: session.roomCode,
                scheduledFor: session.scheduledFor))
    }
}

/// HOW A SESSION IS OPENED — one rule, one place (fix round 2 / N11).
///
/// B2 put this rule in `HomeView.present(_:)`, which was right for every
/// route on that screen and wrong as a claim about the app: the calendar page
/// fills its agenda from `liveForCurrentUser()`, which returns solo rows, and
/// pushed them. So a live ad-hoc session tapped on the calendar was a push
/// with no MINIMISE, a hidden back button and a hidden dock — the one
/// counter-example to "a solo session is always the cover, from every route".
///
/// A rule stated at one call site is a rule until somebody writes a second
/// call site, which is what happened. This is the rule itself; the two
/// screens that open sessions both ask it.
enum SessionPresentation: Equatable {
    /// `SoloSessionCover` — full screen, not swipe-dismissible, MINIMISE the
    /// deliberate way out.
    case soloCover
    /// The navigation push every session has always had. It carries its own
    /// way out: the end control every page now mounts (`SessionEndAffordance`).
    case push

    /// Decided from the session row alone, because that is all a list screen
    /// holds. See `SoloSessionShape.isSoloByConstruction` for why a SCHEDULED
    /// solo session is not in this set and keeps the push.
    static func of(_ session: WorkoutSession) -> SessionPresentation {
        SoloSessionShape.isSoloByConstruction(groupID: session.groupID,
                                              roomCode: session.roomCode,
                                              scheduledFor: session.scheduledFor)
            ? .soloCover : .push
    }
}

// MARK: - MINIMISE

/// THE DELIBERATE WAY OUT OF THE COVER (decision 6).
///
/// An ad-hoc session is presented in a `.fullScreenCover`, which cannot be
/// swipe-dismissed — that gesture destroyed the view and every `@State` in
/// it, and it is the single mechanism behind both halves of the owner's
/// field report. So leaving is something the lifter CHOOSES, and this is the
/// choice.
///
/// IT CALLS `dismiss()` AND NOTHING ELSE. Mounted as an overlay on the
/// cover's own content, `@Environment(\.dismiss)` is the COVER's dismissal,
/// so this control needs no closure threaded down through
/// `SessionEntryView` → `SessionRunnerView` → `SessionInProgressView` →
/// `SessionLiveView` — which is also why `SessionRunnerView` needed no edit.
/// Nothing is torn down: the session row stays `in_progress`, and the swap
/// layer, the cursor and the rest window are all where re-entry will find
/// them.
///
/// IT SPENDS NOTHING (design rule 2). The live body's one accent is the LOG
/// card; this is a bare glyph and a muted kicker in `neutral700`, the same
/// shape as `turnHeaderRail`'s own plain buttons. No background, so it adds
/// no third radius and no third raised surface (rule 1), and the glyph is an
/// SF Symbol, never an emoji (rule 9).
///
/// TOP-TRAILING, ON PURPOSE. The my-turn header's leading corner already
/// holds ✕ (leave the session), and the owner has named the logging screen's
/// top-LEFT slot as the future home of swap / talk-to-Coach. This sits in
/// neither.
struct SoloMinimiseControl: View {
    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Text("MINIMISE")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(theme.neutral700)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Minimise session")
        .accessibilityHint("Keeps the workout running and goes back")
    }
}

extension View {

    /// Mount MINIMISE over an ad-hoc solo session's cover.
    ///
    /// AT THE COVER, NOT INSIDE THE LIVE BODY, and that placement is the
    /// whole of the decision. An ad-hoc session opens on the WARM-UP screen
    /// (`state == "in_progress"` with `lifting_started_at` still NULL is
    /// exactly `WarmUpGate.isWarmingUp`), and `SessionLiveView` has not
    /// mounted yet — so a control carried by the live body alone would leave
    /// the warm-up inside a cover with no exit at all. Decision 6's promise
    /// is that minimising is available as a choice, and a promise that only
    /// starts once START LIFTING is tapped is not that.
    ///
    /// One control, both phases, and no second one anywhere: the live body
    /// mounts `SoloSessionShape`'s furniture gates, not this.
    @ViewBuilder
    func soloMinimiseOverlay(_ isActive: Bool = true) -> some View {
        if isActive {
            self.overlay(alignment: .topTrailing) {
                SoloMinimiseControl()
                    .padding(.trailing, 4)
            }
        } else {
            self
        }
    }
}
