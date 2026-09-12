#if DEBUG
import SwiftUI

// MARK: - Rounds, four frames
//
// Spec §3.3: the unit is the round. Everyone does one set of their current
// exercise; the round closes when the last lifter logs; the next set cannot
// start before that (the soft gate). The two solo screens map onto Rounds
// unchanged — "your turn" is the set screen, "the round" is the rest screen,
// where the countdown becomes "who is still to go" beside elapsed rest, the
// recovery readout, the next prescription and the achievability check.
//
// The pair below differs in ONE decision: whether the crew is rendered as a
// TURN STRIP above the rest content, or as PEOPLE ON THE STATION CARDS. The
// rest card itself — elapsed rest, recovery, next, achievability — is the
// same object in both, so the frames are a clean A/B of where the crew goes.
//
// THE SOFT GATE IS NOT AN ACCENT. On both frames the control at the foot is
// a raised neutral face reading who is still out. The next act belongs to
// the crew, not to you, and painting it accent would say otherwise.
//
// THE PERSONAL SCALE-DOWN (spec §3.4 mode 2, owner decision 9) has no id of
// its own: it is Sam's "Goblet squat" line under his avatar, in both frames,
// exactly where the crew already looks. Nothing is pushed to anyone.

// MARK: - Shared pieces

/// The rest card: spec §2's four rest-screen elements as one raised object.
/// Identical in both round variations by design.
struct SVRoundRestCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 14) {
                SVRestClock(elapsed: SVFixtures.restElapsed)
                Spacer(minLength: 0)
            }
            SVRecoveryReadout(from: SVFixtures.hrFrom, to: SVFixtures.hrTo)
            GSDivider()
            SVNextUp(prescription: SVFixtures.nextPrescription,
                     achievability: SVFixtures.achievability)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }
}

/// "Who is still to go" as a strip — variation a's whole argument.
///
/// The countdown a solo lifter watches becomes a list of people. One of them
/// is lifting right now and carries the accent ring (rule 2's "the current
/// item in a pager or turn strip"); the rest are queued behind them.
struct SVWhoIsToGo: View {
    @Environment(\.gsTheme) private var theme

    let lifting: SVLifter
    let queued: [SVLifter]
    let count: String
    /// The COPY. At the hold threshold the person at the head of this strip
    /// is not lifting, they are resting past it, and the kicker has to say
    /// which — `round-skip-offer` turns this on.
    var isHolding: Bool = false
    /// The RING'S COLOUR, independent of the copy. A frame that has spent its
    /// one accent elsewhere (the skip offer's invitation, the spotter's
    /// CHEER) marks the current lifter in a neutral tone instead.
    var accentsCurrent: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GSSectionHeader(isHolding ? "STILL RESTING" : "LIFTING NOW")
                Spacer(minLength: 8)
                Text(count)
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.neutral700)
            }
            HStack(alignment: .top, spacing: 4) {
                SVAvatarMark(lifter: lifting,
                             size: 44,
                             ring: true,
                             ringColor: accentsCurrent ? nil : theme.neutral500)
                if !queued.isEmpty {
                    Text("THEN")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(0.9)
                        .foregroundStyle(theme.neutral500)
                        .padding(.top, 16)
                        .padding(.horizontal, 4)
                    ForEach(queued) { lifter in
                        SVAvatarMark(lifter: lifter, size: 44)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .svStrip()
    }
}

/// One station as a card — variation b's whole argument. A crew larger than
/// three is split so no rotation is deeper than three (owner decision 2), so
/// two cards is what a five-person crew looks like.
struct SVStationCard: View {
    @Environment(\.gsTheme) private var theme

    let name: String
    let lifters: [SVLifter]
    /// Who is lifting on this station right now, by id — the accent ring.
    var liftingID: Int?

    /// Logged over rotation depth — the round's progress on this station,
    /// countable without a second widget.
    private var loggedLine: String {
        let logged = lifters.reduce(0) { $0 + ($1.hasLogged ? 1 : 0) }
        return "\(logged)/\(lifters.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                GSSectionHeader(name)
                Spacer(minLength: 0)
                Text(loggedLine)
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .monospacedDigit()
                    .foregroundStyle(theme.neutral700)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(lifters) { lifter in
                    SVAvatarMark(lifter: lifter,
                                 size: 36,
                                 ring: lifter.id == liftingID,
                                 showsLogged: true,
                                 columnWidth: 52)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        // `maxHeight: .infinity` so the two cards in a `fixedSize(vertical:)`
        // row read level even when one holds three people and the other two
        // — the `HomeV3TilePair` idiom, unchanged.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)
    }
}

// MARK: - 07 · the turn strip

/// `round-wait-a` — **who is still to go is a line, and the rest is a card.**
///
/// The strip above the rest card answers the one question a resting lifter
/// actually has ("can I go yet, and who am I waiting for") in a single row of
/// faces, with the person lifting right now ringed. The rest card underneath
/// keeps spec §2's four elements together and undisturbed, and the stations
/// drop to two quiet lines at the foot because on this frame they are
/// context, not the subject.
///
/// The cost the owner is being asked to price: the strip repeats people the
/// station lines also name, and a five-person crew makes it a wide row.
///
/// ACCENT: the ring on Sam, the lifter whose turn it is. Nothing else — the
/// soft gate at the foot is a raised neutral face, because the next act is
/// the crew's.
struct RoundWaitAView: View {
    var body: some View {
        SVScreen(kicker: "\(SVFixtures.crewName.uppercased()) · \(SVFixtures.roundNumber)",
                 title: "The round") {
            SVWhoIsToGo(lifting: SVFixtures.rackA[1],
                        queued: [SVFixtures.rackB[0]],
                        count: "2 STILL TO GO")

            SVRoundRestCard()

            SVStationLines()
        } foot: {
            PTTDockRow(otherParticipantNames: ["Sam Obi", "Dana Kord", "Lee Vance"])
            SVGatedControl(title: "WAITING ON SAM AND LEE")
        }
    }
}

// MARK: - 08 · the crew on the stations

/// `round-wait-b` — **the crew lives on the stations, and the rest content
/// sits under them.**
///
/// Two station cards carry the people, so a lifter reads the round the way
/// the room is actually arranged: this rack, those three, that one is up.
/// A logged set is a green tick on the avatar, so the round's progress is
/// countable without a separate count. The rest card below is the SAME
/// object variation a uses — the only thing that moved is the crew.
///
/// The cost the owner is being asked to price: two raised cards above the
/// rest card is three objects on one page, and the rest content — which is
/// what the screen is for — starts lower.
///
/// ACCENT: the ring on Sam, on Rack A. Identical job to a, different place.
struct RoundWaitBView: View {
    var body: some View {
        SVScreen(kicker: "\(SVFixtures.crewName.uppercased()) · \(SVFixtures.roundNumber)",
                 title: "The round") {
            HStack(alignment: .top, spacing: 10) {
                SVStationCard(name: "RACK A",
                              lifters: SVFixtures.rackA,
                              liftingID: SVFixtures.rackA[1].id)
                SVStationCard(name: "RACK B",
                              lifters: SVFixtures.rackB)
            }
            .fixedSize(horizontal: false, vertical: true)

            SVRoundRestCard()
        } foot: {
            PTTDockRow(otherParticipantNames: ["Sam Obi", "Dana Kord", "Lee Vance"])
            SVGatedControl(title: "WAITING ON SAM AND LEE")
        }
    }
}

// MARK: - 09 · the hold threshold

/// `round-skip-offer` — the state, on variation a's composition.
///
/// Spec §9a: the hold threshold is `max(90 s, 1.5 × the median rest of the
/// round)`, capped at 180 s, measured from the moment the second-to-last
/// lifter logged. At it, the crew's rest screens show one quiet line and any
/// crewmate can tap it; **nothing happens on its own**. Lee has logged by
/// now — the threshold is measured from his log — so Sam alone holds the
/// round, which is why the strip's kicker turns from LIFTING NOW to STILL
/// RESTING and the gate names one person.
///
/// The offer is deliberately the SMALLEST object on the page and sits above
/// the fold, not below it (rule 4: a question below a scroll gets answered by
/// nobody). Under it, two lines of consequence: what the threshold was, and
/// what happens to Sam. A skip that does not say "nothing is recorded
/// against him" is a punishment with a friendly label.
///
/// ACCENT: the offer, and only the offer. It is an invitation line (rule 2),
/// so at the threshold the accent LEAVES Sam's ring — which goes muted — and
/// lands on the one thing the crew can now do.
struct RoundSkipOfferView: View {
    var body: some View {
        SVScreen(kicker: "\(SVFixtures.crewName.uppercased()) · \(SVFixtures.roundNumber)",
                 title: "The round") {
            SVSkipOffer()

            SVWhoIsToGo(lifting: SVFixtures.rackA[1],
                        queued: [],
                        count: "1 STILL TO GO",
                        isHolding: true,
                        accentsCurrent: false)

            SVRoundRestCard()
        } foot: {
            PTTDockRow(otherParticipantNames: ["Sam Obi", "Dana Kord", "Lee Vance"])
            SVGatedControl(title: "WAITING ON SAM")
        }
    }
}

/// The quiet line itself. Accent ink on a `surface` strip with an accent
/// hairline — an invitation, not a button: spec §9a says any crewmate can
/// tap it and that nothing happens on its own, and a filled accent slab
/// would read as the crew's next step rather than as an option.
struct SVSkipOffer: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        Button(action: {}) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: "forward.end")
                        .font(.system(size: 12, weight: .bold))
                    Text(SVFixtures.skipOffer)
                        .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.accent)

                Text(SVFixtures.skipWaited)
                    .font(GSFont.body(11.5, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral700)
                Text(SVFixtures.skipConsequence)
                    .font(GSFont.body(11.5, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
            }
            .svStrip()
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(theme.accent, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 10 · spotter mode

/// `round-spotter` — **an idle round is given something to do, with the
/// crew.**
///
/// Owner decision 7 and spec §1: spotter mode is what a lifter does in
/// rounds their prescription has no set for — cheer, talk, film — "with the
/// crew, not a solo recap". So the page says plainly that you have no set,
/// then shows the crew's round exactly as the resting frames do, then hands
/// you the three affordances. Talk is the existing dock (rule 6, its own home
/// directly above the primary), which is why only two doors are drawn: three
/// doors in a row at most, and the third one already exists.
///
/// ACCENT: CHEER, as the screen's one primary. This is the argument the frame
/// makes — in spotter mode the app owes you an act, not a readout — and it is
/// why the crew's turn ring is neutral here while it is accent on 07 and 08.
struct RoundSpotterView: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        SVScreen(kicker: "\(SVFixtures.crewName.uppercased()) · \(SVFixtures.spotterRound)",
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

            SVStationLines()
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
