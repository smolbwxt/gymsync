#if DEBUG
import SwiftUI

// MARK: - The crew lobby, second pass
//
// The owner picked variation a's arrival track and struck the roster under
// it: "the READY TO START roster is redundant — checked in IS ready (one
// signal)." What replaced it is not nothing. The lobby's job is buy-in, and
// the two frames below spend the space the roster gave back on the three
// things a crew actually buys into before Start: the WHOLE plan, how
// everybody is feeling, and a way to ask Coach about it.
//
// `lobby-crew-waiting-a`, `-b` and `lobby-crew-ready` are untouched and
// still render. These sit beside them.

// MARK: - 120 · the lobby, second pass

/// `lobby-crew-waiting-v2` — **the lobby is where a crew buys in, so it
/// shows the whole bargain.**
///
/// Four objects, in the order a lifter needs them:
///
///  1. **The arrival track**, exactly as variation a drew it and now the
///     lobby's ONLY presence signal. Start's caption counts its last column
///     and nothing else: "2 of 4 checked in".
///  2. **The whole session plan.** Round 1 showed one line — today's rung —
///     which asks the crew to agree to a quarter of a leg day. Every
///     exercise with its sets × reps @ load, the rung line above them, and a
///     Swap on each row for the leader (spec §3.1 keeps the plan card's swap
///     control; §3.4 mode 1 is what a swap becomes once Start has happened).
///  3. **The crew's readiness**, as self-reported energy. This is the buy-in
///     the roster's tick was pretending to be: a tick said "I pressed a
///     button", a 1-to-5 says how the session is likely to go. Three have
///     answered; the one who has not is you, so the widget carries a control
///     and not a nag about somebody else.
///  4. **Coach**, as one entry row — this session's focus, form questions,
///     demo videos — because the lobby is the last quiet moment before the
///     room gets loud.
///
/// Then the dock and Start, in their round-1 places.
///
/// ACCENT: Start, still, even disabled. "How are you feeling?" is the one
/// live act on the page and it is deliberately a raised face: a dimmed
/// primary is still the page's accent, a second one would be two, and the
/// warm-up frames already set the rule that an Accept beside a primary is
/// neutral.
struct LobbyCrewWaitingV2View: View {
    var body: some View {
        SVScrollScreen(kicker: "\(SVFixtures.crewName.uppercased()) · \(SVFixtures.crewSessionWhen.uppercased())",
                       title: SVFixtures.crewSessionTitle) {
            SVArrivalRail(lifters: SVFixturesV2.lobbyWaiting)

            SVPlanListCard(kicker: "THE SESSION",
                           rungLine: SVFixturesV2.crewRungLine,
                           rows: SVFixturesV2.crewPlan,
                           showsSwap: true)

            SVCrewEnergyCard(lifters: SVFixturesV2.lobbyWaiting,
                             reported: SVFixturesV2.energyReported)

            SVCoachEntryRow(title: SVFixturesV2.coachLobbyTitle,
                            detail: SVFixturesV2.coachLobbyDetail)
        } foot: {
            PTTDockRow(otherParticipantNames: ["Dana Kord", "Sam Obi"])
            SVPrimary(title: "START",
                      enabled: false,
                      note: SVFixturesV2.checkedInCaption)
        }
    }
}

// MARK: - 121 · locked in

/// `lobby-crew-ready-v2` — **when everyone is in, the lobby stops asking
/// questions and answers one.**
///
/// The owner: "the track widget's WHOLE content becomes a locked-in state —
/// one composition that reads as 'everyone's here, ready to roll' (a quiet
/// celebration, not confetti)."
///
/// So the three columns collapse into one card. The four avatars stand
/// together rather than in stages, each still carrying the energy they
/// reported — because the buy-in is now COMPLETE, and a widget that
/// disappears the moment it fills in never shows the crew that it did. One
/// green tick and one sentence carry the celebration; there is no confetti,
/// no badge and no second colour.
///
/// Under it, the plan's FIRST exercise, large, with the rest of the day named
/// in one quiet line beneath — what the crew is about to walk to a rack and
/// do, not the whole table they already agreed to upstairs.
///
/// The energy card, the Swap controls and Coach's row are gone from this
/// frame ON PURPOSE. They are decisions, and the decisions are made; a
/// locked-in screen that still offers four ways to change the plan is not
/// locked in.
///
/// ACCENT: Start, live, and the biggest thing on the page.
struct LobbyCrewReadyV2View: View {
    var body: some View {
        SVScrollScreen(kicker: "\(SVFixtures.crewName.uppercased()) · \(SVFixtures.crewSessionWhen.uppercased())",
                       title: SVFixtures.crewSessionTitle) {
            SVLockedInCard(lifters: SVFixturesV2.lobbyReady)

            SVFirstUpCard()
        } foot: {
            PTTDockRow(otherParticipantNames: ["Dana Kord", "Sam Obi", "Lee Vance"])
            SVPrimary(title: "START",
                      note: SVFixturesV2.lockedInStartNote)
        }
    }
}

/// The track's replacement once every stage but the last is empty: the crew
/// together, the sentence, and what each of them said about today.
///
/// Green does exactly one job here — present (rule 2) — on the tick and on
/// the word beside it. The avatars and the meters stay neutral.
///
/// The four columns are FIXED width and height, so the avatars share one
/// baseline and the meters share another whatever the names are.
struct SVLockedInCard: View {
    @Environment(\.gsTheme) private var theme

    let lifters: [SVLifter]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline
            HStack(spacing: 0) {
                ForEach(lifters) { lifter in
                    column(lifter)
                }
            }
            Text(SVFixturesV2.lockedInDetail)
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    private var headline: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.gsSuccess)
            Text(SVFixturesV2.lockedInHeadline)
                .font(GSFont.bold(20, relativeTo: .title3))
                .foregroundStyle(theme.text)
            Spacer(minLength: 0)
        }
    }

    private func column(_ lifter: SVLifter) -> some View {
        VStack(spacing: 6) {
            GSInitialsAvatar(name: lifter.name, size: 44)
            Text(lifter.isYou ? "You" : SVName.first(lifter.name))
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral700)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 13)
            SVEnergyMeter(value: lifter.energy)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80, alignment: .top)
    }
}

/// What the crew walks to the rack to do. The day's first exercise as the
/// card's hero, and the rest of it named — never silently dropped — in one
/// line under the rule.
struct SVFirstUpCard: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GSSectionHeader("FIRST UP")
            Text(SVFixturesV2.lockedInFirstUp)
                .font(GSFont.bold(21, relativeTo: .title2))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            GSDivider()
            Text(SVFixturesV2.lockedInThen)
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }
}
#endif
