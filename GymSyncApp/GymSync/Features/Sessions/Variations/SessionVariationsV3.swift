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
// Two ids, frames 127-128. Every v1 and v2 id is frozen and still renders.

// MARK: - 127 · the arrival widget is the button

/// `lobby-crew-ready-v3` — **the thing that changed is the thing you press.**
///
/// v2 answered "everyone's here" with a neutral card and put the accent on a
/// Start at the foot. The owner's move: the ARRIVAL WIDGET ITSELF becomes the
/// state change — it fills with the accent, says *"Everyone's here. Let's
/// work."*, keeps the four avatars and their energy under the headline, and
/// is tappable.
///
/// **Why the accent moved, and why that is not a rule break.** Design rule 4
/// gives a screen one primary; rule 2 says accent is spent on the one primary
/// action. It does not say the primary has to be a button-shaped thing at the
/// bottom of the page. On this screen the widget that has been tracking
/// arrival all through the lobby is the object whose state Start depends on,
/// so when it completes, the object and the act are the same object — and the
/// crew's faces are what the leader is actually pressing. A neutral card
/// beside an accent button asks the leader to look at one thing and press
/// another.
///
/// **So the foot's Start goes neutral, and stays.** It is a raised secondary
/// reading "Start" with the same action, still in the thumb zone — because
/// the widget sits at the top of the page and a 6'2" leader holding a phone
/// one-handed at a squat rack should not have to reach for it. Two controls,
/// one act, one accent; the caption under the secondary says so, which is
/// also the honest answer to "why are there two".
///
/// **The caption on the widget is role-dependent** and this frame renders the
/// LEADER's branch, because the leader's is the one where the tap does
/// something and where the foot control is live. The other branch is one
/// string: a crewmate sees *"Waiting for Alex — or it starts on its own"* in
/// the same slot, with the same widget, not tappable.
///
/// Everything else is v2's, unchanged: the FIRST UP card and the talk dock.
///
/// ACCENT: the arrival widget, and only it. The avatars invert on the accent
/// face — `theme.bg` tiles with accent initials, energy pips in `theme.bg` —
/// the way `GSPrimaryButtonStyle` puts `theme.bg` ink on an accent fill. No
/// green tick: on an accent slab a second colour is a second idea, and the
/// whole widget turning is the celebration.
struct LobbyCrewReadyV3View: View {
    var body: some View {
        SVScrollScreen(kicker: "\(SVFixtures.crewName.uppercased()) · \(SVFixtures.crewSessionWhen.uppercased())",
                       title: SVFixtures.crewSessionTitle) {
            SVLockedInAccentCard(lifters: SVFixturesV2.lobbyReady,
                                 caption: SVFixturesV3.readyLeaderCaption)

            SVFirstUpCard()
        } foot: {
            PTTDockRow(otherParticipantNames: ["Dana Kord", "Sam Obi", "Lee Vance"])
            SVSecondaryStart(title: "Start",
                             note: SVFixturesV3.readySecondaryNote)
        }
    }
}

/// The arrival widget in its locked-in state: an accent face you press.
///
/// A `gs3DCardStyle` with an explicit accent face, so it sinks onto its lip
/// like every other pressable object in the app — the card-class sibling of
/// the primary button, which is precisely what this is. The column geometry
/// is v2's `SVLockedInCard`, slot for slot (44 pt avatar, 13 pt name row,
/// 12 pt meter, 80 pt column), so the two frames can be laid side by side and
/// only the ink will have moved.
struct SVLockedInAccentCard: View {
    @Environment(\.gsTheme) private var theme

    let lifters: [SVLifter]
    let caption: String

    var body: some View {
        Button(action: {}) {
            VStack(alignment: .leading, spacing: 12) {
                headline
                HStack(spacing: 0) {
                    ForEach(lifters) { lifter in
                        column(lifter)
                    }
                }
                captionRow
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd,
                                    lipHeight: 6,
                                    face: theme.accent))
    }

    private var headline: some View {
        Text(SVFixturesV3.readyHeadline)
            .font(GSFont.bold(21, relativeTo: .title2))
            .foregroundStyle(theme.bg)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Same slots as `SVLockedInCard`, inverted ink.
    private func column(_ lifter: SVLifter) -> some View {
        VStack(spacing: 6) {
            GSInitialsAvatar(name: lifter.name,
                             size: 44,
                             fill: theme.bg,
                             ink: theme.accent)
            Text(lifter.isYou ? "You" : SVName.first(lifter.name))
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                .foregroundStyle(theme.bg.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 13)
            SVEnergyMeter(value: lifter.energy, onAccent: true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80, alignment: .top)
    }

    private var captionRow: some View {
        HStack(spacing: 8) {
            Text(caption)
                .font(GSFont.bodyMedium(12.5, relativeTo: .caption))
                .foregroundStyle(theme.bg.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.bg.opacity(0.85))
        }
    }
}

/// The foot's Start, once the accent has gone up the page: a full-width
/// raised neutral face with the caption under it.
///
/// Not `SVGatedControl` — that object exists to look INERT (an hourglass and
/// `neutral700` ink, for a control the crew holds). This one is live and its
/// ink is `text`, because a secondary that reads as disabled would tell the
/// leader the only reachable control does nothing.
struct SVSecondaryStart: View {
    @Environment(\.gsTheme) private var theme

    let title: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(action: {}) {
                Text(title)
                    .font(GSFont.bold(16, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, lipHeight: 5))

            Text(note)
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

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

// MARK: - The third pass's copy

/// Three strings. Everything else these two frames render comes from
/// `SVFixtures` and `SVFixturesV2`, unchanged — the cast, the crew, the
/// block and the readings are the same session they have been all round.
enum SVFixturesV3 {

    static let readyHeadline = "Everyone's here. Let's work."

    /// The LEADER's branch, which is what frame 127 renders. A crewmate sees
    /// `readyCrewmateCaption` in the same slot on the same widget, and the
    /// widget is not tappable for them.
    static let readyLeaderCaption = "Yours to start — or it starts on its own."

    /// Named here rather than left in prose so the plan has the exact string
    /// to build, even though no frame in this round renders it.
    static let readyCrewmateCaption = "Waiting for Alex — or it starts on its own"

    static let readySecondaryNote = "Same action, in the thumb zone"
}
#endif
