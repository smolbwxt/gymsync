#if DEBUG
import SwiftUI

// MARK: - Rounds, second pass
//
// The owner picked variation b — the crew on the station cards — and gave
// four instructions for it: the recovery becomes a line graph, the spare
// real estate carries the routine, a Coach thread gets its own row, and the
// two station cards must ALIGN. `round-wait-a`, `-b`, `round-skip-offer` and
// `round-spotter` are untouched and still render.

// MARK: - The alignment fix

/// The station card, rebuilt so that two of them side by side agree on
/// everything the eye checks: the top edge, the title baseline, the avatar
/// row's baseline, and the card's own height.
///
/// **What was wrong.** Round 1's card sized itself to its content. Rack A
/// holds three people and one of them (Sam) carries a personal scale-down
/// line; Rack B holds two and nobody carries one. So Rack A's avatar column
/// was a line taller, Rack A's card was taller, and `maxHeight: .infinity`
/// inside a `fixedSize(vertical:)` row did not rescue it — the row sized to
/// the tallest card and the shorter one kept its own intrinsic height.
///
/// **The fix is slots, not stretching.** Every part of the card is a fixed
/// height: the title row is `titleHeight` whether the name is RACK A or RACK
/// B, each lifter column is `columnHeight` whether or not there is a
/// substitution under the name, and the card's content is
/// `contentHeight` regardless of how many people are on it. Two cards built
/// from constants cannot disagree. The scale-down keeps its own reserved
/// line, so Sam's row and Dana's row start at the same y.
///
/// This is the pass's ALIGNMENT RULE in one object: alignment is a property
/// of the layout, never a coincidence of the fixture.
struct SVStationCardV2: View {
    @Environment(\.gsTheme) private var theme

    let name: String
    let lifters: [SVLifter]
    var liftingID: Int? = nil

    /// The three constants two cards must share to line up.
    private static let titleHeight: CGFloat = 14
    private static let columnHeight: CGFloat = 70
    private static let contentHeight: CGFloat = titleHeight + 10 + columnHeight

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
                    .fixedSize()
            }
            .frame(height: Self.titleHeight)

            HStack(alignment: .top, spacing: 0) {
                ForEach(lifters) { lifter in
                    column(lifter)
                }
                Spacer(minLength: 0)
            }
            .frame(height: Self.columnHeight, alignment: .top)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.contentHeight + 24, alignment: .top)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)
    }

    /// One lifter: avatar, name, and a RESERVED line for the personal
    /// scale-down whether or not this lifter has one. The reserved line is
    /// what keeps Rack A and Rack B's avatar rows on one baseline.
    private func column(_ lifter: SVLifter) -> some View {
        VStack(spacing: 4) {
            GSInitialsAvatar(name: lifter.name, size: 36)
                .overlay(alignment: .bottomTrailing) { logged(lifter) }
                .overlay(ring(lifter))
            Text(lifter.isYou ? "You" : SVName.first(lifter.name))
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral700)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: 13)
            Text(lifter.scaleDown ?? " ")
                .font(GSFont.body(10, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 12)
        }
        .frame(width: 52, height: Self.columnHeight, alignment: .top)
    }

    @ViewBuilder
    private func logged(_ lifter: SVLifter) -> some View {
        if lifter.hasLogged { SVTick() }
    }

    @ViewBuilder
    private func ring(_ lifter: SVLifter) -> some View {
        if lifter.id == liftingID {
            RoundedRectangle(cornerRadius: 36 * 0.28)
                .strokeBorder(theme.accent, lineWidth: 2)
        }
    }
}

// MARK: - 123 · the round wait, second pass

/// `round-wait-v2` — **variation b, with the rest screen's two dead numbers
/// turned into a shape and the empty half of the page turned into the
/// plan.**
///
/// Four changes, all of them the owner's:
///
///  1. **The stations align.** See `SVStationCardV2` — fixed slots, not
///     stretching.
///  2. **Recovery is a curve.** `128 → 96` says where the heart started and
///     stopped. It does not say whether it is still falling, which is the
///     only question a lifter asks at 1:42 of rest. The graph puts the
///     elapsed clock and the recovery side by side on one row, which is also
///     what buys the room for change 3.
///  3. **The whole routine with where we are**, and NOT the volume-progress
///     line — the choice the owner left open. The argument: the rest screen
///     already has to answer "is the plan still achievable" (spec §2), and
///     achievable is a question about the four exercises that are LEFT, not
///     about a total. A volume line answers "how much have we done", which
///     the round counter in the kicker and the per-station `2/3` already
///     answer twice. Freestyle keeps the volume rail because there the
///     crew's spread IS the subject; here the plan is.
///  4. **The Coach thread**, as one row, with the reason it exists on the
///     line under it: the crew shares one thread and it is unlocked because
///     Mo is Pro. A shared feature that does not say whose subscription pays
///     for it invites the wrong argument in the group chat.
///
/// ACCENT: the ring on Sam, the lifter whose turn it is — variation b's
/// accent, in variation b's place. The soft gate at the foot stays a raised
/// neutral face: the next act belongs to the crew.
struct RoundWaitV2View: View {
    var body: some View {
        SVScrollScreen(kicker: "\(SVFixtures.crewName.uppercased()) · \(SVFixtures.roundNumber)",
                       title: "The round") {
            HStack(alignment: .top, spacing: 10) {
                SVStationCardV2(name: "RACK A",
                                lifters: SVFixtures.rackA,
                                liftingID: SVFixtures.rackA[1].id)
                SVStationCardV2(name: "RACK B",
                                lifters: SVFixtures.rackB)
            }

            SVRestCardV2()

            SVPlanListCard(kicker: "THE SESSION · WHERE WE ARE",
                           rungLine: SVFixturesV2.crewRungLine,
                           rows: SVFixturesV2.crewPlan,
                           showsProgress: true)

            SVCoachEntryRow(title: SVFixturesV2.coachThreadTitle,
                            detail: SVFixturesV2.coachThreadDetail,
                            note: SVFixturesV2.coachThreadNote)
        } foot: {
            PTTDockRow(otherParticipantNames: ["Sam Obi", "Dana Kord", "Lee Vance"])
            SVGatedControl(title: "WAITING ON SAM AND LEE")
        }
    }
}

/// The rest card, second pass: the elapsed clock and the recovery curve on
/// ONE row — the clock left at a fixed width so the graph's left edge is in
/// the same place on every render — then the rule, then spec §2's next
/// prescription and achievability check, unchanged from round 1.
struct SVRestCardV2: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                SVRestClock(elapsed: SVFixtures.restElapsed)
                    .frame(width: 96, alignment: .leading)
                SVHRRestGraph(samples: SVFixturesV2.restCurve,
                              duration: SVFixtures.restElapsed)
            }
            GSDivider()
            SVNextUp(prescription: SVFixtures.nextPrescription,
                     achievability: SVFixtures.achievability)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }
}

// MARK: - 124 · spotter mode, second pass

/// `round-spotter-v2` — **spotting is watching, so the screen shows what
/// there is to watch.**
///
/// CHEER stays the primary and Film stays beside it; talk is still the dock.
/// Two things are added, both the owner's:
///
///  * **The crew's live heart rates** while they lift. This is what turns
///     spotter mode from a waiting room into a job: the reason to be at the
///     rack is that you can see Dana is at 158 and Lee has come down to 121.
///     NEUTRAL INK and the zone as a WORD (`Z3`) — the owner's ruling for
///     this pass, because the language reserves red and gold and a heart
///     rate is not an error or a streak. Who is lifting is marked by WEIGHT,
///     not by colour.
///  * **The Coach thread row**, the same object `round-wait-v2` carries, in
///     the same place, saying the same thing about why it is unlocked.
///
/// The round-1 turn strip stays, because "who is lifting and who is next" is
/// the other half of what a spotter is tracking, and the heart-rate card
/// answers a different question (how hard) than the strip does (whose turn).
///
/// ACCENT: CHEER. The turn strip's ring is neutral here, exactly as it is in
/// `round-spotter`, and the new heart-rate rows spend nothing.
struct RoundSpotterV2View: View {
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

            SVCrewHeartRatesCard()

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

/// The crew's live readings, four rows on three aligned columns (the
/// number, the unit, the zone word). Owner decision 13 already shares heart
/// rate by default; this is the first screen that uses it for anybody other
/// than the lifter it belongs to.
struct SVCrewHeartRatesCard: View {
    @Environment(\.gsTheme) private var theme

    /// The owner's third-pass reversal: zone colours stay. Defaulted off so
    /// `round-spotter-v2` renders exactly as it was approved; `-v3` passes
    /// true and is otherwise the same frame.
    var zoneTinted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                GSSectionHeader("THE CREW, RIGHT NOW")
                Spacer(minLength: 8)
                Text("SHARED BY DEFAULT")
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.neutral500)
                    .fixedSize()
            }
            ForEach(Array(SVFixturesV2.spotterHeartRates.enumerated()), id: \.offset) { _, row in
                SVLiveHRRow(name: row.name,
                            bpm: row.bpm,
                            isLifting: row.isLifting,
                            zoneTinted: zoneTinted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }
}
#endif
