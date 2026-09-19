import SwiftUI

// MARK: - SpotterView
//
// What a lifter does in the rounds their prescription has no set for (spec
// §1, owner decision 7; plan task S8). The production twin of
// `round-spotter-v3` (frame 128 — the v3, with the zone colours restored by
// owner decision 17), captured as `session-round-spotter` (frame 139).
//
// AN IDLE ROUND HAS A JOB. The page says plainly that you have no set, then
// shows the crew's round exactly as the round wait does, then hands you the
// one thing there is to do.
//
// VALUE-IN (constraint 11), like every other screen in this folder.
//
// ACCENT: CHEER. The turn strip's current tile is NEUTRAL here — it carries
// the accent on the round wait, and a screen spends its accent once (rule 2).
// The crew's heart rates are DATA COLOUR, which §4a exempts, and every one of
// them carries its zone word.

struct SpotterView: View {
    @Environment(\.gsTheme) private var theme

    /// `PUSH CREW · ROUND 4`.
    let kicker: String
    /// `You're spotting`.
    let title: String

    /// Who is lifting and who is behind them — neutral here.
    let turn: [TurnStrip.Tile]
    /// `2 STILL TO GO`, or empty to draw no count.
    let stillToGo: String

    let crew: [CrewHeartRatesCard.Row]

    /// The same door the lobby and the round wait carry (spec §3.6).
    let coach: CoachDoorRow.Model

    var dockNames: [String] = []
    var reactionEmojis: [String] = []
    var voice: VoiceFoot = VoiceFoot()

    var onCoachTap: () -> Void = {}
    var onReaction: (String) -> Void = { _ in }
    var onCheer: () -> Void = {}

    /// THE WAY OUT (fix round 2 / N10, ruling R-C-7). Same gap as the round
    /// wait's: no header rail here, and `bottomChrome` does not reach a crew
    /// page. CHEER below is a `RoundDoor` too, which is what made the absence
    /// easy to miss — a page with a door on it looks like a page you can
    /// leave.
    ///
    /// Optional, nil in every catalog world, so the spotter frames render
    /// exactly as they render today (constraint 14). Production passes it
    /// through `SessionEndAffordance.pageMountsItsOwnEnd(.roundsSpotter)`.
    var onEnd: (() -> Void)?

    var body: some View {
        RoundPage(kicker: kicker, title: title) {
            VStack(alignment: .leading, spacing: 5) {
                Text(RoundCopy.spotterNoSet)
                    .font(GSFont.bold(14.5, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                Text(RoundCopy.spotterWithTheCrew)
                    .font(GSFont.body(12.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .roundStrip()

            VStack(alignment: .leading, spacing: 8) {
                if !stillToGo.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        Text(stillToGo)
                            .font(GSFont.bold(11, relativeTo: .caption2))
                            .tracking(0.8)
                            .foregroundStyle(theme.neutral700)
                            .fixedSize()
                    }
                }
                TurnStrip(tiles: turn, accentsCurrent: false)
            }

            CrewHeartRatesCard(rows: crew)

            CoachDoorRow(coach, onTap: onCoachTap)
        } foot: {
            VoiceNotices(foot: voice)
            if !reactionEmojis.isEmpty {
                ReactionStrip(emojis: reactionEmojis, onTap: onReaction)
            }
            PTTDockRow(otherParticipantNames: dockNames, compact: false)
            // FILM IS OMITTED, DELIBERATELY. The reference frame puts it
            // beside Cheer, and the plan's own instruction is that it opens
            // the existing clip path or is left out rather than faked. That
            // path cannot film somebody else: `SetLogClipRepository.attach`
            // uploads under the CALLER's own storage prefix
            // (`StorageService.uploadFormClip(userID:)`) and inserts
            // `user_id` as the caller, against a `set_log_id` that would
            // belong to the lifter being filmed — so a spotter's clip needs
            // new storage RLS, an owner decision about who owns a clip of
            // someone else's set, and a retention gate for a non-Pro
            // filmer. That is plumbing, not a button. Recorded in the
            // report.
            RoundDoor(glyph: "hands.clap.fill",
                      title: RoundCopy.cheer,
                      isPrimary: true,
                      onTap: onCheer)
            // AFTER cheer, and not primary: this page's one accent act is
            // CHEER (rule 2), and ending is not what the spotter came to do.
            if let onEnd {
                RoundDoor(glyph: "xmark", title: RoundCopy.endSession, onTap: onEnd)
            }
        }
    }
}
