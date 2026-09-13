#if DEBUG
import SwiftUI

// MARK: - The session design round, third and last pass
//
// The owner approved every v2 addition with ONE REVERSAL: heart-rate zone
// colours stay, as an explicit exception to the colour rules — which is what
// design language rule 2's own heart-rate clause already said ("like plate
// colours, this is data colour, not accent, and is exempt"). So
// `together-clock` (v1, frame 117) stands, `together-clock-v2` (126) is
// dropped conceptually with its id and capture left in place, and the one
// frame that needs rebuilding for it is spotter mode.
//
// Frame 127 (`lobby-crew-ready-v3`, `LobbyCrewReadyV3View`) was this pass's
// other id: the owner picked it, and the group-session Phase A plan
// (task S11) built it to production as `session-lobby-ready` and retired
// the design-round frame in the same commit — `LobbyCrewReadyV3View`,
// `SVLockedInAccentCard`, `SVSecondaryStart` and `SVFixturesV3` (all four of
// its strings were this frame's own) left with it. What remains below is
// frame 128 alone.

// MARK: - 128 · spotter mode with the colours put back

/// `round-spotter-v3` — `round-spotter-v2`, with the crew's heart rates
/// wearing their zone colours again.
///
/// The owner's reversal, and the only difference between the two frames. The
/// second pass took the ramp off on the reading that the language reserves
/// red and gold; rule 2's heart-rate clause always exempted it, and the owner
/// has now said so explicitly. The tint uses `SVZoneColor.of(bpm)` — the same
/// mapping, tokens and values `together-clock` (v1, frame 117) paints its
/// bars and its `GSHeartRatePill`s with — so no two frames in this round can
/// disagree about what 158 looks like.
///
/// **The zone word stays beside the number.** It was introduced as the
/// colour's replacement and it survives the reversal on its own merits: a
/// reader who cannot separate orange from red still gets Z3 from Z4, and the
/// word costs 22 points. `BPM` stays `neutral500` and the word stays
/// `neutral700` — the number alone carries the tint, which is exactly how
/// `GSHeartRatePill` treats its own caption.
///
/// Everything else is `-v2`, element for element and in the same order: the
/// no-set strip, the turn strip with its neutral ring, the crew's readings,
/// the Coach thread row, the dock, CHEER and Film.
///
/// ACCENT: CHEER, unchanged. The zone ramp is data colour and is not accent
/// (rule 2), which is the whole basis of the exception.
struct RoundSpotterV3View: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        SVScrollScreen(kicker: "\(SVFixtures.crewName.uppercased()) · \(SVFixtures.spotterRound)",
                       title: "You're spotting") {
            VStack(alignment: .leading, spacing: 5) {
                Text(SVFixtures.spotterLine)
                    .font(GSFont.bold(14.5, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                Text("You're with the crew until round 5 — not in a recap on your own.")
                    .font(GSFont.body(12.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .svStrip()

            SVWhoIsToGo(lifting: SVFixtures.rackA[2],
                        queued: [SVFixtures.rackB[0]],
                        count: "2 STILL TO GO",
                        accentsCurrent: false)

            // THE ONE DIFFERENCE from `round-spotter-v2`.
            SVCrewHeartRatesCard(zoneTinted: true)

            SVCoachEntryRow(title: SVFixturesV2.coachThreadTitle,
                            detail: SVFixturesV2.coachThreadDetail,
                            note: SVFixturesV2.coachThreadNote)
        } foot: {
            PTTDockRow(otherParticipantNames: ["Sam Obi", "Dana Kord", "Lee Vance"])
            HStack(spacing: 10) {
                SVDoor(glyph: "hands.clap.fill", title: "Cheer", isPrimary: true)
                SVDoor(glyph: "video.fill", title: "Film")
            }
        }
    }
}
#endif
