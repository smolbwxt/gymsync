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
//   * `SoloSessionShape.isAdHocSolo(participantCount:roomCode:scheduledFor:)`
//     — the discriminator the four ENTRY POINTS read to decide whether the
//     full-screen cover carries a MINIMISE control. A scheduled session
//     reached through Home's button is a navigation push with a back button
//     of its own; only the ad-hoc cover needs a way out built for it.
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

    /// AN AD-HOC SOLO SESSION: a party of one, no room code, and no
    /// scheduled time.
    ///
    /// It reuses `SessionShape.isSolo(participantCount:roomCode:)` verbatim
    /// rather than restating it — that function already carries the reason
    /// `group_id` is not the signal (`.friends` and `.code` sessions leave it
    /// nil too) — and adds the one discriminator that separates the lifter
    /// who just tapped START from the lifter who booked a slot: an ad-hoc
    /// session has no `scheduled_for` at all.
    static func isAdHocSolo(participantCount: Int,
                            roomCode: String?,
                            scheduledFor: Date?) -> Bool {
        SessionShape.isSolo(participantCount: participantCount, roomCode: roomCode)
            && scheduledFor == nil
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
