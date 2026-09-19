import SwiftUI

// MARK: - SoloSessionLayer
//
// THE SOLO SHAPE OF THE ONE BODY (Phase C1 S4, decision 6 and brief item 7).
//
// Two things live here and they are deliberately not the same law:
//
//   * `SoloSessionShape.hidesCrewFurniture(participantCount:)` — the gate the
//     one body reads in four places so that a lifter alone in a gym never
//     sees a talk dock, a presence count or a rotation. It asks about the
//     ROSTER and nothing else, which is why a SCHEDULED solo session gets the
//     same treatment: a party of one has nobody to talk to whether or not a
//     calendar said so.
//   * `SoloSessionShape.isSoloByConstruction(groupID:roomCode:scheduledFor:)`
//     — the discriminator every PRESENTATION route reads, decided from the
//     session row alone because that is all those call sites hold. It is what
//     says a session is presented in a cover with MINIMISE rather than
//     pushed, and it is the seed of the furniture law below when no roster
//     has arrived yet.
//
// WHY A SEPARATE FILE AND NOT FOUR INLINE CONDITIONS. Constraint 22: the one
// body's `body` is at its type-checker budget, so every modifier this task
// adds is an extracted layer. And four inline `participants.count <= 1`
// tests are four places for the law to drift — the review of a later phase
// would have to find them all to know what a solo lifter sees.

enum SoloSessionShape {

    /// HIDE THE CREW'S FURNITURE. True for a roster of one.
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
    static func hidesCrewFurniture(participantCount: Int) -> Bool {
        participantCount <= 1
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
